# Character Studio design

Goal: create believable performers the way music games do (fast, fun, presets and parts),
while the engine underneath handles real anatomy, clothing fit and physics
(see `anatomy-reference.md`). References: Rock Band 2/3 (musician creation, roles, band),
Guitar Hero World Tour (rock-star personality, equipment), The Sims 4 (body sculpting,
outfits), WWE 2K (physique, entrances, layered costumes). Ideas only; no assets, characters,
logos or designs from these games are used.

## Principles

1. **Natural first.** Each section opens on a few big, visual choices (presets, swatches,
   thumbnails). Detail lives in a collapsed "Fine-tune" panel. No wall of sliders.
2. **Direct manipulation.** Drag on the body or face to sculpt (wider shoulders, longer legs,
   fuller lips); the drag maps to the right measurements and morphs underneath.
3. **Everything adapts.** Clothes, hair, hats, glasses and shoes refit to whatever body is chosen;
   nothing has to be adjusted by hand to "make it fit".
4. **Presets are starting points.** Any outfit, personality, instrument or animation works
   with any character; presets never lock anything.
5. **A character is not tied to a role.** The same performer can sing, play guitar, bass,
   drums or keys (assign per show), like Rock Band 2's role assignment.
6. **Undo, redo, reset one feature, "Surprise me"** (realistic random from population data).

## Sections (tabs)

| Tab | Up front | Fine-tune |
|---|---|---|
| Identity | Name, stage name, hometown, band | Notes |
| Body | Body type presets (slim, lean, average, athletic, muscular, broad, curvy, fuller, heavyset), height, weight, drag-to-sculpt | Exact cm measurements, regional muscle and fat, correlation strength, locks |
| Face | Face presets, drag-to-sculpt | Nose, eyes, brows, lips, jaw, chin, cheekbones, ears, asymmetry |
| Hair | Style thumbnails, color swatches | Length, volume, curl, highlights, facial hair |
| Skin | Tone and undertone swatches | Freckles, moles, stage makeup, glitter, tattoos and body paint |
| Wardrobe | Outfit presets and per-slot picks (top, bottom, shoes, layers) | Fit, length, sleeves, neckline, rise, fabric, thickness, stretch, sheen, prints/logos |
| Accessories | Glasses, hats, jewelry, belts, gloves | Color, position, cap forward/back |
| Instruments | Instrument per role, color | Body shape, finish, mic and stand type, in-ear monitors |
| Performance | Personality preset (Rock, Pop, Metal, Electronic, R&B/Soul, Jazz, Punk, Glam, Goth) | Energy, confidence, stage movement, crowd interaction, left/right-handed, seated/standing |

Personality presets suggest outfits and set idle style, gestures and movement energy; they can
be mixed with anything.

## Preview

360° turntable, face close-up, front / side / back / three-quarter, neutral inspection
lighting vs live stage lighting, animation preview (idle, gestures from the gesture library,
walk), garment comparison, measurement overlay in cm (Fine-tune only).

## Stage and show features

Multiple saved outfits per performer and costume changes during a show; saved bands; walking
between stage positions and custom entrances/exits; mic handling and stand interaction;
instrument-specific hand movement; performer movement synced to song sections; lip-sync to
imported vocals (later); importing custom clothing, hair, instruments and accessories (licensed
assets only).

## Mapping to the engine

| Surface control | Engine parameters |
|---|---|
| Body type preset | Height/weight starting point, composition, regional muscle and fat, variation z-scores |
| Height, weight | CharacterBody.heightCm / weightKg; all correlated measurements update, overrides kept |
| Drag shoulders / waist / legs | manualOverrides or variation for the matching measurement |
| Outfit pick | Garment + fit mode (auto-fit default) + fabric profile |
| Personality preset | Idle set, gesture weights, movement energy, outfit suggestions |
| "Surprise me" | Sample a realistic body from ANSUR II statistics plus random style choices |
