"""Demucs' spectrogram steps in plain numpy (what the app does in Swift around the Core ML network).
Matches demucs.htdemucs._spec / _ispec (torch.stft/istft, normalized, centered, reflect padding)."""
import math
import numpy as np
NFFT = 4096
HL = 1024
WIN = (0.5 - 0.5 * np.cos(2 * np.pi * np.arange(NFFT) / NFFT))      # periodic Hann (torch default)

def _reflect(x, left, right):
    return np.pad(x, [(0, 0)] * (x.ndim - 1) + [(left, right)], mode="reflect")

def spec(x):
    """x: (C, L) -> complex (C, 2048, le)"""
    L = x.shape[-1]
    le = int(math.ceil(L / HL))
    pad = HL // 2 * 3
    x = _reflect(x, pad, pad + le * HL - L)
    x = _reflect(x, NFFT // 2, NFFT // 2)                             # stft center=True
    n = (x.shape[-1] - NFFT) // HL + 1
    idx = np.arange(NFFT)[None, :] + HL * np.arange(n)[:, None]
    frames = x[:, idx] * WIN                                           # (C, n, NFFT)
    z = np.fft.rfft(frames, axis=-1) / np.sqrt(NFFT)                   # normalized=True
    z = np.transpose(z, (0, 2, 1))[:, :-1, :]                          # (C, 2048, n)
    return z[:, :, 2:2 + le]

def ispec(z, length):
    """z: (..., 2048, le) complex -> (..., length)"""
    *other, F, T = z.shape
    z = z.reshape(-1, F, T)
    z = np.pad(z, [(0, 0), (0, 1), (2, 2)])
    pad = HL // 2 * 3
    le = HL * int(math.ceil(length / HL)) + 2 * pad
    n = z.shape[-1]
    frames = np.fft.irfft(np.transpose(z, (0, 2, 1)), n=NFFT, axis=-1) * np.sqrt(NFFT) * WIN   # (B, n, NFFT)
    total = NFFT + HL * (n - 1)
    y = np.zeros((z.shape[0], total)); wsum = np.zeros(total)
    for i in range(n):
        y[:, i * HL:i * HL + NFFT] += frames[:, i]; wsum[i * HL:i * HL + NFFT] += WIN ** 2
    y = y / np.where(wsum > 1e-11, wsum, 1)
    y = y[:, NFFT // 2:NFFT // 2 + le]                                 # undo center padding, istft length=le
    y = y[:, pad:pad + length]
    return y.reshape(*other, length)

def cac(z):
    """complex (C, F, T) -> real (C*2, F, T): [re0, im0, re1, im1]"""
    C, F, T = z.shape
    return np.stack([z.real, z.imag], axis=1).reshape(C * 2, F, T)

def uncac(m):
    """real (S, C*2, F, T) -> complex (S, C, F, T)"""
    S, C2, F, T = m.shape
    m = m.reshape(S, C2 // 2, 2, F, T)
    return m[:, :, 0] + 1j * m[:, :, 1]
