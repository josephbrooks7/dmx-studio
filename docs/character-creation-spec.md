# DMX Studio — Advanced Adult Character Creation System (specification)

_Text of the specification PDF supplied by Joseph (11 pages), kept in the repo as the source of truth. Status per requirement: docs/character-status.md._

```
 DMX Studio
 Advanced Adult Character Creation System
 Complete consolidated development specification for Claude


 1. Project objective
 Develop the existing DMX Studio Character Studio into a realistic adult character creation and
 customization system for musicians, singers, dancers, band members and other stage performers.
 Draw inspiration from The Sims 4 Create a Sim (direct sculpting, facial controls and wardrobe), The
 Sims 3 Create-a-Style (material channels and patterns), Rock Band 3 (musicians and bands), Guitar
 Hero World Tour (performer identity and instruments), WWE 2K (costume layering and entrances),
 and inZOI (realistic humans). Borrow interaction concepts, not proprietary assets or cartoon
 graphics. The objective is realistic anatomy, high-quality 3D rendering and professional stage
 visualization. Adult characters only: no babies, toddlers, children or teenagers.


 2. Existing project requirements
 Audit the existing Character Studio architecture, meshes, imported assets, textures, rigs and
 animations before modifying anything. Reuse compatible assets, preserve existing features and
 saved characters/shows, avoid duplicate systems, back up original user-provided assets, and
 implement working functionality rather than decorative controls. Keep modules independent and
 isolate character editing from active show playback and DMX output. Coordinate with existing
 development work to avoid conflicting commits and duplicate builds.


 3. Character creation interface
 Provide a large central real-time 3D viewport with categories for Identity, Body, Face, Eyes, Skin,
 Hair, Facial Hair, Body Hair, Makeup, Tattoos, Clothing, Shoes, Accessories, Materials, Outfits,
 Instruments, Personality, Movement, Performance and Character Library.

 • Viewport: 360-degree rotation, smooth zoom, horizontal/vertical pan,
   front/rear/left/right/three-quarter views, full-body, upper-body, face and individual region
   close-ups.

 • Preview options: neutral/studio/stage lighting, adjustable background, floor visibility, neutral
   standing pose, T-pose, A-pose and performance pose.

 • Automatically frame the relevant region when editing face, shoes or clothing. Smooth transitions
   must preserve edits and camera state where appropriate.


 4. Character identity
 Name, stage name, adult age, male/female anatomical base, masculine/feminine/unrestricted
 fashion preferences, height, weight, musical role, genre, performance personality, dominant hand,
 vocal classification, description, reference photographs and thumbnail.





 Adult presets: young adult 18–34, adult 35–59, older adult 60+. These proposed ranges are not
 official Sims age categories. Continuous age controls should gradually influence wrinkles, facial
 volume, skin elasticity, hair pigmentation, muscle definition and posture. No underage models.


 5. Advanced body customization
 Use mesh morph targets, blend shapes, skeletal adjustments, corrective deformation and
 statistically supported anthropometric relationships. Both male and female base meshes must
 support substantial individual variation.

 • Global controls: height, weight, body mass, body fat, muscularity, muscle definition, skeletal
   frame size, body width/depth, proportions, soft tissue distribution, fitness appearance and
   posture.

 • Presets: very slim, slim, average, lean, athletic, toned, muscular, bodybuilder, broad, stocky,
   curvy, pear-shaped, hourglass, rectangular, heavyset and plus-size. Presets are starting points
   only. Weight, fat and muscle are separate properties; allow mixed body characteristics.

 • Head/neck: head size, width, height, depth; neck length, circumference, width, muscularity;
   trapezius size/definition and neck-to-shoulder transition.

 • Shoulders/upper torso: width, slope, height, depth; deltoid size/definition, clavicle prominence,
   torso length; rib cage width/depth/circumference; upper back width, musculature and latissimus
   development.

 • Male chest: pectoral size and definition, circumference, width, depth, upper chest development,
   lower chest fullness, asymmetry and soft tissue distribution.

 • Female bust: circumference, volume, projection, spacing, shape, upper/lower fullness, position,
   asymmetry, underbust circumference and gravity/support response. Preserve anatomical
   transitions into shoulders, ribs, abdomen and back. Clothing must not flatten or replace these
   features.

 • Abdomen/waist: size, projection, muscle development and definition, obliques, roundness,
   flatness, soft tissue thickness, width, circumference, depth, taper, lower abdominal fullness, love
   handles and torso length. Developed abdominal muscles may exist beneath soft tissue without
   visible definition.

 • Hips/pelvis: width, circumference, depth, pelvic width/tilt, curvature, hip dips, lower torso
   proportions and waist-to-hip transition.

 • Gluteal region: volume, projection, width, height, muscle development, soft tissue distribution,
   shape and asymmetry.

 • Arms: upper arm length/circumference, biceps/triceps, definition, elbow size, forearm
   length/circumference/musculature, wrist circumference and arm span.

 • Hands: length, palm width/thickness, finger length/thickness and individual proportions, knuckles,
   nail length/shape. Preserve instrument interaction.

 • Legs: overall, upper and lower leg length; thigh circumference/width, quadriceps, hamstrings,
   inner thigh fullness, knee size/position, calf circumference/definition, shin length, ankle
   circumference and alignment.





 • Feet: length, width, volume, arch height, heel width, toe length, shoe size, left/right variation.
   Support US men's/women's, UK, EU and centimeters. Geometry is authoritative; commercial sizes
   vary by manufacturer.


 6. Anatomical correlation system
 Changing major measurements should intelligently influence related features using validated
 statistical relationships, not uniform scaling. A 180 cm adult is not merely a scaled-up 165 cm adult.
 Preserve individual variation and avoid forcing identical proportions on people of the same height or
 weight.

 • Height: arm and leg lengths, arm span, hands, feet, neck and torso lengths.

 • Weight: waist, hips, chest, thighs, upper arms and facial fullness.

 • Muscle: shoulders, chest, back, upper arms, forearms, abdomen, thighs and calves.

 • Fat: abdomen softness, waist, facial fullness, arms, hips, thighs, chest and gluteal soft tissue.

 • Other dependencies: head size affects hair/hats/glasses; bust and hips affect garment fit; foot
   size affects footwear; age affects skin/hair/posture.

 Every correlated feature supports Automatic (predicted), Relative (offset from prediction), Manual
 (exact setting) and Locked (protected from unrelated changes). Example: a locked US men's size 12
 shoe must remain unchanged when height changes.

 Store anatomical baseline, predicted value, individual variation, user adjustment, lock status and
 resolved measurement. Conceptually: resolved = anatomical prediction + individual variation +
 user adjustment; locked values override. Use deterministic dependency graphs or constrained
 solvers; avoid circular dependencies. Validate coefficients against appropriate adult anthropometric
 datasets; do not invent training data or present unvalidated estimates as facts.


 7. Direct mesh sculpting
 Follow The Sims 4 interaction concept. Click and drag shoulders outward, waist inward, hips
 outward, abdomen/chest forward, thighs outward, glutes backward, neck upward, nose forward or
 jaw outward to modify the corresponding feature. Highlight editable regions on hover; display
 feature name and measurement. Keep sliders, numeric inputs and direct manipulation
 synchronized. Support symmetric and independent left/right editing, fine adjustment, reset
 feature/region/character, feature locks, undo/redo and randomize region/unlocked features. Use
 controlled morphs and constraints, not unrestricted vertex dragging that damages topology.


 8. Facial customization
 Use presets (oval, round, square, heart, diamond, rectangular, triangular, long, broad, angular)
 combined with detailed sculpting and front/profile/three-quarter views.

 • Forehead: height, width, projection, slope, curvature, brow ridge, temples.

 • Eyebrows: shape, thickness, density, length, height, angle, arch, spacing, color, independent
   sides.





 • Eyes: size, width, height, spacing, depth, angle, inner/outer corners, iris size/color, upper/lower
   lids, hooding, crease, under-eye fullness, tear troughs, heterochromia, blinking and eye tracking.

 • Nose: size, length, width, bridge height/width/curvature, projection, tip size/angle/projection,
   nostril width/shape/flare and columella.

 • Cheeks: cheekbone height/width/projection, fullness, hollowness, buccal fat and softness.

 • Mouth/lips: width, height, upper/lower thickness, projection, Cupid's bow, contour, corners, angle,
   philtrum length/definition.

 • Jaw/chin: width, height, depth, angle, definition, projection, roundness, cleft and under-chin
   fullness.

 • Ears: height, width, angle, projection, position, earlobe size/attachment, asymmetry.

 • Teeth/mouth interior: tooth color, shape, spacing, size, alignment, gums, missing teeth and
   braces.

 Preserve compatibility with expressions, talking, singing and lip-sync.


 9. Skin rendering and surface details
 Use physically based rendering: base color, normal, roughness, ambient occlusion, subsurface
 scattering, detail normals, optional displacement and regional masks. Avoid plastic/rubber
 appearance, excessive bloom and washed-out skin.

 Controls: continuous skin tone, undertone, complexion, texture, pores, freckles, moles, beauty
 marks, birthmarks, scars, stretch marks, vitiligo, redness, dryness, oiliness, shine, sweat, tan lines,
 wrinkles and age spots. Allow opacity, intensity, scale, placement and color where appropriate. Test
 red, blue, green, violet, amber and white stage lights.


 10. Hair customization
 Reusable hair assets must fit different male/female head shapes. Styles: bald, buzz, crew, fade,
 short textured, side-parted, pompadour, slicked back, undercut, medium layered, bob, pixie, long
 straight/wavy/curly, Afro, coils, cornrows, braids, locs, ponytail, bun, updo, mohawk, spikes,
 alternative/fantasy styles and stage wigs.

 Supported controls: length, volume, thickness, density, curl, hairline, parting, recession, strand
 direction, roots, primary/secondary colors, highlights, streaks, tips, ombre, shine, roughness and
 wetness. Use hair cards, strands or optimized meshes as appropriate. Long hair supports gravity
 and secondary motion. Account for head shape, shoulders, jackets, hats and accessory collisions.


 11. Facial and body hair
 Facial styles: clean-shaven, light/heavy stubble, short/full/long beard, goatee, mustache, chin strap,
 sideburns and combinations. Color, length, density, thickness and coverage; conform to customized
 jaw, chin, cheeks and facial expressions.

 Body hair: chest, abdomen, back, shoulders, arms, forearms, legs and underarms. Independent
 region density, coverage, length and color.





 12. Makeup and cosmetics
 Available to every adult anatomical base and fashion preference. Foundation, concealer, contour,
 blush, bronzer, highlighter, eyeshadow, eyeliner, mascara, false lashes, eyebrow makeup, lipstick,
 gloss, liner, face/body paint, glitter, metallic cosmetics, stage/special effects makeup, fingernail and
 toenail polish. Controls: color, opacity, coverage, intensity, placement, roughness, gloss, reflectivity,
 gradient and blend strength. Support facial animation and stage lighting. Nails also support length
 and shape.


 13. Tattoos and decals
 Layered decals using UV textures or surface projections. Regions: face, neck, shoulders, chest,
 back, abdomen, upper arms, forearms, wrists, hands, fingers, hips, thighs, calves and ankles.
 Controls: position, scale, rotation, mirror, opacity, color, fading, edge softness and layer order.
 Import transparent PNG artwork; allow overlapping designs. Decals follow deformations and remain
 attached to the same surface. Reuse architecture for face paint, temporary tattoos, scars, makeup
 patterns and clothing graphics.


 14. Wardrobe system
 Independent clothing assets must not permanently modify underlying anatomy. All compatible
 garments, hair, makeup, shoes and jewelry are available across male/female bases; optional fashion
 filters can be disabled.

 • Tops: tees, graphic tees, tanks, crop tops, athletic tops, button-downs, dress shirts, flannel, polos,
   blouses, sweaters, turtlenecks, sweatshirts, hoodies, vests, corsets, cardigans, blazers,
   denim/leather/bomber jackets, coats and performance jackets.

 • Bottoms: skinny/slim/straight/relaxed/baggy/flared jeans, trousers, chinos, cargo pants, joggers,
   sweatpants, leather pants, leggings, athletic/denim/casual shorts, mini/midi/maxi/pleated skirts,
   tights and fishnets.

 • Full body: dresses, suits, tuxedos, jumpsuits, rompers, overalls, bodysuits, tracksuits, uniforms,
   costumes, fantasy outfits, performance costumes, dancewear and swimwear.

 • Base garments: briefs, boxers, boxer briefs, bras, sports bras, bralettes, undershirts, camisoles,
   compression garments, shapewear, slips, socks and stockings. Optional independent layers
   influence fit, support, silhouette and thickness.


 15. Dynamic clothing fit
 Critical: preserve the character's customized chest, bust, shoulders, arms, waist, hips, thighs and
 other features across clothing changes. A masculine shirt on a female base must retain her bust; a
 fitted shirt on a muscular male must retain his chest and arm geometry. Slim and heavyset bodies
 must remain intact under oversized or fitted garments. Body-region visibility masks may prevent
 hidden clipping but must not alter stored anatomy or visible silhouette.

 Fit options: compression, skin-tight, tight, slim, fitted, regular, relaxed, loose, oversized and custom.
 Independently adjust chest, shoulder, waist, hip, upper arm, thigh, sleeve fit, leg opening and
 torso/sleeve/hem length where supported.




 Construction controls: neckline depth/width, collar shape, sleeve length, shirt length, waist rise,
 trousers/skirt length, leg opening, zipper position, buttons, tucked/untucked, rolled sleeves,
 open/closed jacket and hood position. Only expose controls for which each asset has valid geometry
 or authored morphs; store capability metadata.

 Silhouette behavior must consider body shape, fabric thickness, elasticity, stiffness, garment ease,
 tension, compression, gravity, motion, layers, support garments and contact/collision.
 Tight/lightweight fabrics may show anatomical contours or muscle definition more strongly than
 thick, loose or structured fabrics. Loose garments drape instead of tracing every anatomical surface.
 Keep behavior physically plausible rather than exaggerated.


 16. Fabric and material system
 Library: cotton, jersey, denim, leather, faux leather, suede, silk, satin, polyester, nylon, spandex,
 Lycra, velvet, wool, linen, knitwear, lace, mesh, chiffon, organza, latex, vinyl, metallic fabrics,
 sequins and reflective materials.

 Properties: base color, thickness, density, weight, stretch, elastic recovery, stiffness, bend
 resistance, friction, roughness, gloss, metallic response, transparency, light transmission, texture,
 normal intensity and wrinkles. Separate visual shader parameters from physical cloth parameters;
 connect them only where appropriate. Silk and leather may have similar gloss but different stiffness
 and drape.


 17. Independent material channels
 Inspired by The Sims 3 Create-a-Style. Separate regions for main fabric, sleeves, collar, cuffs, lining,
 zipper, buttons, stitching, pockets, graphics and decoration. Provide color wheel, RGB/HEX, palettes,
 gradients, materials, textures, custom images and surface finishes. Patterns: solid, stripes, plaid,
 checks, polka dots, floral, animal, camouflage, geometric, abstract, metallic and custom. Pattern
 scale, rotation, position, repetition and independent colors where supported. Save reusable
 materials and apply to compatible assets.


 18. Clothing layering architecture
 From inner to outer: anatomy/skin, body decals, base garments, primary clothing, mid-layer,
 outerwear, accessories, performance equipment. Support undershirt under open button-down, tee
 under jacket, shirt/vest/blazer, leggings under skirt, socks inside boots, necklace above shirt and
 microphone pack on waistband. Use compatibility rules; attempt corrective deformation before
 rejecting combinations.


 19. Cloth simulation
 Editing mode: responsive morph fitting, skeletal deformation, corrective shapes, collision proxies,
 surface offset corrections and cached fit results. Performance mode: optional gravity, inertia,
 secondary motion, folds, wind, body collision, garment-to-garment and hair-to-garment collision.
 Loose dresses, skirts, sleeves and jackets move naturally during walking, dancing and playing.
 Adjustable simulation quality; never interrupt DMX output, audio or timeline synchronization.





 20. Footwear
 Sneakers, running/casual/dress shoes, loafers, sandals, flip-flops, ballet flats, heels, platforms,
 wedges, ankle/combat/cowboy/knee-high/thigh-high boots, dance and performance footwear. Adapt
 to foot length/width, arch, heel width, ankle, toe shape and shoe size. Heels change ankle rotation,
 foot angle, knee position, pelvic compensation, posture, ground contact and effective standing
 height, not stored anatomical height. Maintain floor contact during animations.


 21. Accessories
 • Head: baseball caps, beanies, cowboy hats, berets, fedoras, bucket hats, headbands, bandanas,
   clips, bows, crowns, tiaras and fantasy headwear.

 • Eyewear: prescription, sunglasses, aviators, round, rectangular, oversized, decorative and
   performance glasses.

 • Jewelry: earrings, necklaces, chains, chokers, pendants, bracelets, watches, rings, anklets and
   piercings.

 • Clothing accessories: belts, suspenders, gloves, scarves, ties, bow ties, arm/leg warmers, bags,
   crossbody bags and backpacks.

 • Medical/accessibility: hearing aids, braces and prosthetics where assets support them.

 • Performance: in-ear monitors, wireless packs, headset/handheld microphones, straps, cables and
   props.

 Use skeletal sockets, surface anchors and transforms. Glasses adapt to head width, nose bridge and
 ears; hats to skull/hair; rings to fingers; necklaces to neck/chest; bracelets to wrists; belts to
 waist/hips; straps to torso and instrument. Manual position, rotation and scale overrides.


 22. Outfit management
 Categories: everyday, casual, formal, athletic, rehearsal, soundcheck, nightlife, party, summer,
 winter, swimwear, loungewear, main stage, alternate stage, dance, music video and custom. Each
 outfit independently stores garments, shoes, hair/style/color, makeup, jewelry, accessories,
 materials, graphics and equipment. Never alter identity, anatomy or face when switching outfits.
 Support save, duplicate, rename, delete, import/export, copy across compatible characters,
 randomization, garment presets and stage-light preview. Schedule costume changes on timeline
 and preload assets to prevent interruptions.


 23. Wardrobe library
 Searchable thumbnails, names, category/subcategory, fashion preference, compatible rigs, material
 channels, fit capabilities, colors, morph targets, attachment data, simulation capabilities,
 source/license, polygon counts and LOD. Filters: category, color, material, style, formality, genre,
 season, purpose, fit, favorites, recently used, imported and compatible. Custom collections and
 favorites.





 24. Performer personality
 Presets: pop, rock, alternative, indie, punk, metal, glam, goth, electronic, EDM, fantasy, R&B, soul,
 hip-hop, country, jazz, classical and musical theater. Suggest clothing and animation but never
 restrict edits or change anatomy. Independent controls: confidence, energy, expressiveness,
 movement frequency/intensity, presence, crowd interaction, gestures, facial expression, dance
 ability, flexibility, posture, walking style, restlessness and theatricality.


 25. Instruments and equipment
 Electric/acoustic guitar, bass, grand/upright/digital piano, keyboard, synthesizer, keytar,
 acoustic/electronic drums, percussion, violin, cello, saxophone, trumpet, trombone, flute, DJ
 controller, turntables, handheld and stand microphones. Customize color, materials, finish, shape,
 hardware, strings, fretboard, pickguard, knobs, graphics/logos, straps, dimensions, stand height and
 position where applicable. Use inverse kinematics and role-specific animations; hand position
 adapts to height, arm length, hand size and instrument geometry. Left/right-handed configurations.


 26. Performance animation
 General: standing, sitting, walking, running, turning, looking, breathing, blinking, head motion,
 gestures, crowd interaction, bows, entrances and exits. Vocal: singing, microphone/stand
 interaction, breaths, expressions, lip-sync, head and hand gestures. Use phonemes/visemes when
 reliable vocal analysis exists, not simply overall volume-driven mouth opening. Instrument actions:
 piano/keyboard, guitar strumming/picking, bass, drums, percussion, DJ, strings and winds. Respect
 equipment location and anatomy. Dance: basic, freestyle, choreographed, pop, hip-hop, electronic,
 rock and theatrical. Blend animations smoothly.


 27. Audio-responsive performance
 Where reliable analysis or authored markers exist, identify tempo, beat, downbeat, intro, verse,
 pre-chorus, chorus, bridge, breakdown, instrumental, outro, intensity and vocal activity. Calmer
 verses, expressive choruses, distinctive breakdown choreography, instrumentalist emphasis during
 solos and closing gestures at endings. Automatic behavior remains editable and must never
 override programmed choreography.


 28. Character library and reuse
 Persistent library with stable identifiers and versioned data. Create, save, duplicate, rename,
 import, export, delete, favorite, collections, assign to bands and multiple shows. Save anatomy,
 face, wardrobe and performance presets plus complete band configurations. Reuse characters
 across venues without rebuilding.





 29. Import and asset pipeline
 Support compatible GLTF/GLB, FBX, OBJ, USD/USDZ and texture formats. Validate topology, skeletal
 hierarchy, skin weights, morphs, materials, textures, UVs, scale, orientation, rig and animation
 compatibility and licensing. Imported assets may need conversion; do not assume immediate
 compatibility. Preserve original uploads separately from optimized derivatives. Maintain registry to
 prevent loss or duplication. Only use appropriately licensed assets.


 30. Character data architecture
 Separate persistent data into Identity, Anatomy, Skeleton, FacialMorphs, SkinMaterials, SkinDetails,
 Hair, FacialHair, BodyHair, Cosmetics, Tattoos, Wardrobe, Footwear, Accessories, OutfitCollection,
 InstrumentAssignments, Personality, AnimationSettings, PerformanceSettings, FeatureLocks,
 AssetReferences and VersionMetadata. Anatomy independent of clothing; clothing independent of
 cosmetics/hair/accessories/role. Resolve rendered appearance from stable definition and
 assets/materials/animation rather than rebuilding identity with every outfit. All edits serializable and
 recoverable. Version schema and migrate older saved projects safely.


 31. Performance optimization
 macOS real-time stage simulation: mesh LOD, texture resolution management, GPU skinning,
 optimized morphs, animation LOD, material batching, texture/asset caching, background asset
 preparation, asynchronous resource loading, cloth quality levels, simplified collision proxies,
 distance-based simulation and visibility culling. Quality presets: Draft (responsive large scenes),
 Standard (balanced), High (better skin/materials/hair/cloth/animation), Ultra (maximum supported
 preview and screenshot quality). Quality changes must not alter saved anatomy or appearance
 choices.


 32. Character Studio user experience
 Immediate editing upon selecting Character Studio; avoid redundant entry buttons. Large preview,
 clear categories, search, responsive sliders, numeric measurements, thumbnails, intuitive camera
 movement, smooth rotation, selection highlight, undo/redo, autosave, reset, before/after
 comparison, randomization, feature locks, favorites, recently used, presets. Metric/imperial units.
 Basic controls with expandable advanced sections; avoid hundreds of simultaneous sliders.


 33. Stage integration
 Assign characters to positions, groups, bands and venues; stage orientation, floor alignment,
 shadows, lighting and moving lights, LED wall illumination, choreography, instruments, costume
 changes, entrances/exits and reusable formations. Switch Character Studio/stage/timeline/other
 views without interrupting show. Isolate audio, DMX, timeline transport and editing. Avoid
 unintended background flicker and overexposure.


 34. Implementation priorities
 • Phase 1 — Foundation: audit assets, realistic male/female base meshes, skeletons, skin, viewport,
   persistence, body morphs and visual fixes.





 • Phase 2 — Anatomy: global/regional adjustments, correlations, locks, direct sculpting, facial
   controls and corrective deformation.

 • Phase 3 — Appearance: hair, facial/body hair, skin details, makeup, tattoos and eyes.

 • Phase 4 — Wardrobe: import assets, adaptive fit, shared compatibility, footwear, accessories,
   layering, material channels and outfits.

 • Phase 5 — Rendering: fabrics, hair, cloth, lighting, collisions and secondary motion.

 • Phase 6 — Performance: rigs, instruments, role animations, lip-sync, choreography, personalities
   and timeline events.

 • Phase 7 — Integration: venues, uninterrupted playback, multi-character optimization, persistence
   and legacy projects, asset validation, graphical fixes, actual screenshots and tested macOS build.


 35. Required testing
 Do not count a control as complete merely because its interface exists. Verify actual rendered
 results.

 • Anatomy: adult male/female characters across different heights, weights, muscle/fat, shoulders,
   chest/bust, waist, hips, arm/leg length and feet. Verify visible and plausible geometry.

 • Clothing: same compatible garment on slim, athletic, muscular and heavyset male; slim, athletic,
   curvy and plus-size female. Verify preserved anatomy, fit, clipping, silhouettes, materials,
   layering and animation deformation.

 • Accessories: glasses align, hats fit skull/hair, jewelry follows motion, shoes align with floor, straps
   follow torso, microphones align to hands/stands.

 • Persistence: reopen characters, locks, custom measurements, imported assets, garments,
   materials, outfits and saved show compatibility.

 • Performance: show and DMX continue while editing/switching views, audio stays synchronized,
   multiple performers work, animations remain stable, normal application quit works and resource
   use stays reasonable.


 36. Development completion rules
 For each phase: inspect implementation; identify reusable components; implement missing
 functionality; integrate; add and run tests; verify actual rendering; fix regressions; commit changes;
 document limitations. Report separately: implemented/tested, implemented/not visually verified,
 partial, planned, blocked. Never use conceptual screenshots or generated images as actual
 application screenshots. Coordinate existing development to avoid duplicate work and conflicting
 builds. Do not claim numerical anthropometry or physics accuracy unless validated.





 37. Final design philosophy and immediate next action
 Combine Sims 4 intuitive sculpting, Sims 3 material customization, Rock Band musician creation,
 Guitar Hero performer identity, WWE 2K performance customization and modern realistic rendering.
 Treat each character as a persistent anatomically defined adult human with independently editable
 physical appearance, clothing, accessories, materials, personality and performance. Changes in one
 system must not unnecessarily destroy another. Prioritize realistic appearance, flexibility, working
 features and professional live performance simulation. Improve actual character graphics and
 customization before unrelated venue expansion. Begin by auditing the current repository, classify
 requirements by implementation status, identify missing assets and continue actual development
 using the existing architecture.





```
