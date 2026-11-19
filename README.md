# DMX Studio

Mac app by Red Velvet Studios that **learns a song** and builds a synced DMX light show for it.

- **Learn**: finds tempo, beats, kicks/snares/hi-hats, energy, silences and song sections
- **Create Show**: genre-based shows (Club/EDM, Hip-Hop/Trap, Pop, Rock, Chill/R&B, Latin) with endless variations
- **Lineups**: press Play, and music + lights run together, song after song
- **Idle Look**: what the lights do before play, between songs, and during silences
- **Wireless DMX**: Bluetooth-style scanning/pairing for Art-Net boxes like PKnight
- Built-in profile: **SHEHDS LED Beam 8x12W RGBW** (38ch per-head and 9ch modes)

Requires macOS 12 Monterey or newer (Intel or Apple Silicon).

## Build
`packaging/build-dmg.sh` → `build/DMX-Studio-<version>.dmg` (needs Xcode or Command Line Tools).
