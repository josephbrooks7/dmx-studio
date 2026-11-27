# Body candidate compatibility audit

Source: successful CI run 45959510749, artifact 15180151921 (body-candidate-inventory.json report in ZIP). These are existing USDZ candidates, not the newly supplied Daz Blender kit and not necessarily the active Rocketbox runtime presets.

| Candidate | Mesh inventory | Rig |
|---|---|---|
| male.usdz | 7 Tripo-named chunks, 394,992 total vertices, shared material tripo_mat_d0bcade7, UVMap | No armatures, modifiers or vertex groups |
| female.usdz | CC_Base_Body_001: 14,164 vertices, 14,046 polygons; separate hair, eye, mouth and underwear meshes | No armatures, modifiers or vertex groups |

The female candidate's skin slots distinguish head, body, arm and leg. Its body world Z bounds are approximately -0.0076 to 1.7322. The male candidate spans approximately -0.5 to +0.5 in world Z; its overall horizontal extent is much greater along Y than X. Do not infer forward direction, physical scale or anatomical landmarks solely from these bounds. Male mesh chunks may represent export splits, not clothing boundaries.

## Integration order
1. Inspect original rigged source files (including supplied basemeshes) rather than assuming these baked USDZ files retain skinning. Preserve asset provenance and distribution permissions.
2. Use CC_Base_Body_001 alone as the female geometric fitting surface; exclude hair, underwear and facial accessory meshes.
3. Determine male surface topology, orientation and clothing boundaries visually; avoid automatically treating all seven chunks as bare skin.
4. Establish explicit normalized coordinate transforms and verified anatomical landmarks. Extract measurements from skin-only surfaces.
5. Test static garment fit on actual human geometry before transferring weights. For animation require validated target skeleton and normalized vertex weights; do not invent them or silently fall back.
6. Compare rest and posed garment screenshots and triangle collision diagnostics before enabling any runtime garment. Preserve current presets and shows.

The current regression and synthetic Blender smoke tests passed. No actual human garment fit or runtime compatibility has been established. The newly supplied Daz kit is not stored in GitHub and remains subject to provenance/license verification.
