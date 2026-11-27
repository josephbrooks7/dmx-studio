# Character creation: implementation status

Audit of `docs/character-creation-spec.md` against the code on branch `fix/darker-venue`
(Nov 27, 2026). Categories follow spec section 36. Nothing is counted complete because an
interface exists; "tested" means an automated check or a reviewed render.

Legend: **IT** implemented and tested · **INV** implemented, not visually verified in the app ·
**P** partial · **PL** planned · **B** blocked (reason given)

## Foundation decided today

- **Base body is now MakeHuman (CC0)**, replacing the two Rocketbox/Avatar-Studio dressed
  characters (Andre, Emma) as the foundation. Reason: those characters have no feet and no skin
  under their clothes, so garments could only be swapped with patches and liners. MakeHuman
  gives a full body, ~1,170 shape targets (macro sex/age/muscle/weight/height, measurements,
  breast, buttocks, stomach, torso, limbs, face), a 163-bone skeleton whose joints follow the
  body shape, and clothing bound to the body (MakeHuman proxy binding). The old characters stay
  in the app for existing shows until the MakeHuman characters render at least as well.
- **Adults only** (spec §1): the library and engine only use adult ages ("young" and "old"
  MakeHuman targets); baby and child targets are never used.

## Status by section

| § | Area | Status | Evidence / what's missing |
|---|---|---|---|
| 2 | Audit, reuse, preserve | P | Repo and assets audited; MakeHuman packs mirrored (release `makehuman-assets-1`); old characters preserved; this document |
| 3 | Viewport and categories | P | Existing Character Studio: turntable, face mode, front/side/back. Missing: new category tabs, pan, region auto-framing, pose choices |
| 4 | Identity | P | Name, role, body style exist. Missing: stage name, age, genre, dominant hand, vocal type, photos |
| 5 | Body customization | P | Engine: `CharacterBody` (height, weight, composition, anatomy params) **IT** (CI self-test). MakeHuman targets in library **IT** (local build). Not yet: targets driven by the engine, morphs visible in the app |
| 6 | Correlation system | P | ANSUR II model learned in CI (4,082 men, 1,986 women, 97 measurements); conditional prediction on height+weight; overrides survive; correlation 0..1 — **IT** (13 CI checks). Missing: per-feature Automatic/Relative/Manual/Locked modes (overrides = Manual today), shoe-size lock |
| 7 | Direct sculpting | PL | Design in `docs/character-studio-design.md` |
| 8 | Face | P | 15 nose morph presets (earlier); MakeHuman face targets in library. Not wired to UI |
| 9 | Skin | P | Texture-preserving skin tone (earlier); MakeHuman skins01/02 in library build. Missing: PBR detail maps, details (freckles, scars...) |
| 10 | Hair | P | 33 hairstyles + head-measured fitting on old characters; MakeHuman hair01 in library build. Not yet fitted to MakeHuman heads in the app |
| 11 | Facial / body hair | PL | Beard packs mirrored (bodyparts05/06); not built yet |
| 12 | Makeup | PL | |
| 13 | Tattoos / decals | PL | Print-zone rules in `anatomy-reference.md` §5c |
| 14 | Wardrobe | P | MakeHuman shirts, pants, shoes, suits, socks in the library build; Andre/Emma garment cross-fitting (Blender) works for tops/trousers |
| 15 | Dynamic fit | P | Cross-body fitter (skeleton retarget + body-surface ease + bone-length stretch + hem/shoe collision) — reviewed renders: shirts good, tees good except one pairing, trousers good, shoes poor. MakeHuman binding replaces this for MakeHuman garments |
| 16 | Fabric / material system | PL | Fabric types documented (knit, rigid, flowy...) |
| 17 | Material channels | PL | |
| 18 | Layering | P | Liner approach on old characters; real layering planned on MakeHuman |
| 19 | Cloth simulation | PL | Fixed-timestep spring-bone plan in `anatomy-reference.md` §7 |
| 20 | Footwear | P | Shoe sizing rules documented; cross-body shoe fitting poor (old characters) |
| 21 | Accessories | P | Top hat + glasses fitting on old characters; accessory fitting library (Python, tested); MakeHuman hats/glasses packs mirrored |
| 22 | Outfits | P | Outfit switching (tee / shirt / formal) on old characters |
| 23 | Wardrobe library | P | Library `catalog.json` with slot, style tags, gender, license, author, thumbnails, vertex counts |
| 24 | Personality | P | Presets listed in design doc; role + pose exist |
| 25 | Instruments | P | Roles exist; instrument props on stage exist. Missing: IK, customization |
| 26 | Performance animation | P | 12 gestures render correctly in review (joint-to-joint aiming) — **IT** in Blender review. Missing in the app; real mocap clips not yet imported |
| 27 | Audio-responsive | P | Song sections, beats and energy already detected for lights; not yet driving performers |
| 28 | Character library | P | Saved performers exist; missing bands, collections, import/export |
| 29 | Import pipeline | P | Asset import scripts, provenance manifests, license checks in CI |
| 30 | Data architecture | P | `CharacterBody` versioned and migrating (older shows load) — **IT**. Other parts of the spec's structure not yet split out |
| 31 | Performance optimization | P | Light/high quality modes exist; LOD etc. planned |
| 32 | UX | P | Design principles agreed (natural surface, Fine-tune panel) |
| 33 | Stage integration | P | Performers on stage, darker venue + house lights dim with the show (not yet visually verified on Joseph's Mac) |

## Blocked / needs Joseph

- **Real animation clips**: decided 2026-11-27, no Mixamo (Joseph has no Adobe sign-in). Sources:
  - Quaternius Universal Animation Library 1 and 2, free standard versions (CC0): idles,
    8-direction locomotion, emotes, sitting. Built for retargeting.
  - CMU Graphics Lab Motion Capture Database: free for all uses, may ship inside a commercial
    product, but the data can't be resold on its own. Covers dance, walks, gestures and pantomime.
    Hand and toe channels are noisy and need smoothing; finger joints aren't captured.
  - MakeHuman's own CC0 poses and expressions.
  - Retargeted onto the MakeHuman 163-bone rig in CI (Blender), then clamped by the joint-limit
    table. A credits file is added for CMU.
- **Visual verification inside the app**: CI renders are from Blender; screenshots of the actual
  app need the Mac (diagnostic capture exists) or a macOS CI capture step (planned).

## Next increments (Phase 1 → 2)

1. Library build in CI (running): skeleton, targets, skins, starter clothes, dressed review render.
2. Swift loader for the library: MakeHuman body + targets driven by `CharacterBody`, skeleton
   from joints, skin weights, clothes via binding; shown in Character Studio next to the old
   characters, behind a switch.
3. Map engine measurements to MakeHuman targets (height, weight, muscle, shoulders, bust, waist,
   hips, limb lengths) and verify measured results against the ANSUR predictions.
4. Natural UI: body type presets, height/weight, drag-to-sculpt, Fine-tune panel.
