"""Builds DMX Studio's High Quality stem splitter: Meta's open-source Demucs (htdemucs_6s: vocals, drums,
bass, guitar, piano, other) converted to Core ML. The network runs in Core ML; the app does the
spectrogram steps itself (demucs_dsp.py shows the same math in numpy).

Usage: export_demucs.py out_dir [verify.wav]
Writes out_dir/DemucsHQ.mlpackage and, with a test song, checks that the converted pipeline matches Demucs."""
import json, math, os, sys, time, wave
import numpy as np
import torch
from torch.nn import functional as F
from demucs.pretrained import get_model
from demucs.apply import apply_model
sys.path.insert(0, os.path.dirname(__file__))
import demucs_dsp as dsp

out_dir = sys.argv[1]
os.makedirs(out_dir, exist_ok=True)
bag = get_model("htdemucs_6s")
m = bag.models[0] if hasattr(bag, "models") else bag
m.eval()
SR = m.samplerate
SEG = int(m.segment * SR)
print("sources", m.sources, "segment", SEG, "samplerate", SR, "cac", m.cac)

class Core(torch.nn.Module):
    """HTDemucs forward between the spectrogram and the inverse spectrogram."""
    def __init__(self, m):
        super().__init__(); self.m = m
    def forward(self, mix, mag):
        m = self.m
        x = mag
        B, C, Fq, T = x.shape
        mean = x.mean(dim=(1, 2, 3), keepdim=True)
        std = x.std(dim=(1, 2, 3), keepdim=True)
        x = (x - mean) / (1e-5 + std)
        xt = mix
        meant = xt.mean(dim=(1, 2), keepdim=True)
        stdt = xt.std(dim=(1, 2), keepdim=True)
        xt = (xt - meant) / (1e-5 + stdt)
        saved, saved_t, lengths, lengths_t = [], [], [], []
        for idx, encode in enumerate(m.encoder):
            lengths.append(x.shape[-1])
            inject = None
            if idx < len(m.tencoder):
                lengths_t.append(xt.shape[-1])
                tenc = m.tencoder[idx]
                xt = tenc(xt)
                if not tenc.empty:
                    saved_t.append(xt)
                else:
                    inject = xt
            x = encode(x, inject)
            if idx == 0 and m.freq_emb is not None:
                frs = torch.arange(x.shape[-2], device=x.device)
                emb = m.freq_emb(frs).t()[None, :, :, None].expand_as(x)
                x = x + m.freq_emb_scale * emb
            saved.append(x)
        if m.crosstransformer:
            if m.bottom_channels:
                b, c, f, t = x.shape
                x = x.reshape(b, c, f * t)
                x = m.channel_upsampler(x)
                x = x.reshape(b, -1, f, t)
                xt = m.channel_upsampler_t(xt)
            x, xt = m.crosstransformer(x, xt)
            if m.bottom_channels:
                b, c, f, t = x.shape
                x = x.reshape(b, c, f * t)
                x = m.channel_downsampler(x)
                x = x.reshape(b, -1, f, t)
                xt = m.channel_downsampler_t(xt)
        for idx, decode in enumerate(m.decoder):
            skip = saved.pop(-1)
            x, pre = decode(x, skip, lengths.pop(-1))
            offset = m.depth - len(m.tdecoder)
            if idx >= offset:
                tdec = m.tdecoder[idx - offset]
                length_t = lengths_t.pop(-1)
                if tdec.empty:
                    pre = pre[:, :, 0]
                    xt, _ = tdec(pre, None, length_t)
                else:
                    skip = saved_t.pop(-1)
                    xt, _ = tdec(xt, skip, length_t)
        S = len(m.sources)
        x = x.view(B, S, -1, Fq, T)
        x = x * std[:, None] + mean[:, None]
        xt = xt.view(B, S, -1, mix.shape[-1])
        xt = xt * stdt[:, None] + meant[:, None]
        return x, xt

core = Core(m).eval()
rng = np.random.default_rng(0)
test = (rng.standard_normal((2, SEG)) * 0.1).astype(np.float32)
mag = dsp.cac(dsp.spec(test.astype(np.float64))).astype(np.float32)[None]
with torch.no_grad():
    ref = m(torch.from_numpy(test)[None]).numpy()[0]
    xs, xt = core(torch.from_numpy(test)[None], torch.from_numpy(mag))
    ours = dsp.ispec(dsp.uncac(xs.numpy()[0].astype(np.float64)), SEG) + xt.numpy()[0]
print("wrapper vs demucs: max diff", float(np.abs(ours - ref).max()), "ref max", float(np.abs(ref).max()))

import coremltools as ct
# PyTorch's fused "fast path" attention isn't something Core ML can read: use the plain ops
if hasattr(torch.backends, "mha"): torch.backends.mha.set_fastpath_enabled(False)
# (traced with gradients on: PyTorch only takes the fused attention shortcut when they're off)
traced = torch.jit.trace(core, (torch.from_numpy(test)[None], torch.from_numpy(mag)), check_trace=False)
t0 = time.time()
ml = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.macOS12,
                inputs=[ct.TensorType(name="mix", shape=(1, 2, SEG)), ct.TensorType(name="mag", shape=mag.shape)],
                outputs=[ct.TensorType(name="spec"), ct.TensorType(name="wave")],
                compute_precision=ct.precision.FLOAT32)
ml.short_description = "Demucs htdemucs_6s (Meta, MIT license): vocals, drums, bass, guitar, piano, other"
ml.user_defined_metadata["sources"] = ",".join(m.sources)
ml.user_defined_metadata["segment"] = str(SEG)
ml.save(os.path.join(out_dir, "DemucsHQ.mlpackage"))
print("converted in %.0f s" % (time.time() - t0))
json.dump({"sources": m.sources, "segment": SEG, "samplerate": SR, "nfft": dsp.NFFT, "hop": dsp.HL,
           "frames": int(mag.shape[-1])}, open(os.path.join(out_dir, "DemucsHQ.json"), "w"))

# Check the Core ML network on the same input
pred = ml.predict({"mix": test[None], "mag": mag})
cs, cw = pred["spec"], pred["wave"]
coreml = dsp.ispec(dsp.uncac(cs[0].astype(np.float64)), SEG) + cw[0]
print("core ml vs demucs: max diff", float(np.abs(coreml - ref).max()))

if len(sys.argv) > 2:
    # Full song: the app's way (normalize, 7.8 s windows overlapping 25 %, triangle weights) vs Demucs
    w = wave.open(sys.argv[2]); x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768
    x = x.reshape(-1, w.getnchannels()).T
    if x.shape[0] == 1: x = np.repeat(x, 2, 0)
    L = x.shape[1]
    refm = x.mean(0); mu, sd = refm.mean(), refm.std()
    xn = (x - mu) / sd
    stride = int(0.75 * SEG)
    weight = np.concatenate([np.arange(1, SEG // 2 + 1), np.arange(SEG - SEG // 2, 0, -1)]).astype(np.float64)
    weight /= weight.max()
    outp = np.zeros((len(m.sources), 2, L)); wsum = np.zeros(L)
    t0 = time.time()
    for off in range(0, L, stride):
        chunk = xn[:, off:off + SEG]; n = chunk.shape[1]
        seg = np.zeros((2, SEG), np.float32); seg[:, :n] = chunk
        mg = dsp.cac(dsp.spec(seg.astype(np.float64))).astype(np.float32)[None]
        p = ml.predict({"mix": seg[None], "mag": mg})
        y = dsp.ispec(dsp.uncac(p["spec"][0].astype(np.float64)), SEG) + p["wave"][0]
        outp[:, :, off:off + n] += y[:, :, :n] * weight[:n]; wsum[off:off + n] += weight[:n]
    outp = outp / wsum * sd + mu
    print("core ml pipeline: %.1f s for %.1f s of audio" % (time.time() - t0, L / SR))
    with torch.no_grad():
        dm = apply_model(bag, torch.from_numpy(((x - mu) / sd)[None].copy()), split=True, overlap=0.25, shifts=0)[0].numpy() * sd + mu
    base = sys.argv[2].rsplit(".", 1)[0]
    def sdr(r, e): return 10 * np.log10((r ** 2).sum() / (((r - e) ** 2).sum() + 1e-9) + 1e-12)
    res = {}
    for k, name in enumerate(m.sources):
        line = f"{name}: matches demucs {sdr(dm[k], outp[k]):.1f} dB"
        tp = f"{base}.{name}.wav"
        if os.path.exists(tp):
            w = wave.open(tp); r = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32).reshape(-1, 2).T / 32768
            line += f", vs true part: ours {sdr(r, outp[k]):.1f} dB, demucs {sdr(r, dm[k]):.1f} dB"
            res[name] = sdr(r, outp[k])
        print(line)
    json.dump(res, open(os.path.join(out_dir, "check.json"), "w"))
