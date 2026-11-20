"""Acts like a PKnight: listens for Art-Net (6454) and sACN (5568) and checks what DMX Studio sends."""
import select, socket, struct, sys, time
def sock(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"): s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    s.bind(("0.0.0.0", port)); s.setblocking(False); return s
a, e = sock(6454), sock(5568)
end = time.time() + float(sys.argv[1] if len(sys.argv) > 1 else 6)
art, sacn, last, first_t, last_t = {}, 0, None, None, None
while time.time() < end:
    ready, _, _ = select.select([a, e], [], [], 0.05)
    for s in ready:
        try: d, _ = s.recvfrom(2000)
        except BlockingIOError: continue
        now = time.time(); first_t = first_t or now; last_t = now
        if d[:8] == b"Art-Net\x00" and d[8:10] == b"\x00\x50":
            uni = d[14] | (d[15] << 8); n = (d[16] << 8) | d[17]
            assert d[10:12] == b"\x00\x0e" and n == 512 and len(d) == 18 + 512, "bad ArtDmx"
            art[uni] = art.get(uni, 0) + 1; last = d[18:]
        elif d[4:13] == b"ASC-E1.17":
            assert len(d) == 638 and d[125] == 0, "bad sACN"
            sacn += 1
ok = True
def check(c, m):
    global ok; print(("PASS " if c else "FAIL ") + m); ok = ok and c
check(0 in art and 1 in art, f"Art-Net on universes 0 and 1: {art}")
check(sacn > 0, f"sACN packets: {sacn}")
span = max(0.5, (last_t or 1) - (first_t or 0))
rate = sum(art.values()) / max(1, len(art)) / span
check(rate > 25, f"about {rate:.0f} frames/sec per universe")
if last:
    print("Bar channels 1-14:", list(last[:14]))
    check(last[4] > 0, f"SHEHDS dimmer (ch5) = {last[4]} (idle look lights the bars)")
    check(last[2] == 0, f"SHEHDS built-in effects (ch3) = {last[2]} (must be 0 so DMX controls the lights)")
    check(any(last[6:38]), "per-head RGBW channels 7-38 carry color")
sys.exit(0 if ok else 1)
