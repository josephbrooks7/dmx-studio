# Daz Female KIT — reference intake

Status: source archive received and verified externally; binary files not yet present in this branch. Reference only; do not bundle or redistribute until license is confirmed.

Expected original files (preserve paths):
- `source/Daz Female KIT.blend` (13,167,308 bytes; Blender 3.6 header; SHA-256 `483c351ec371bc5a188865b7bd613adc1aa9f76b73456b784e7ac30893d751b5`)
- `textures/internal_ground_ao_texture.jpeg` (18,049 bytes; SHA-256 `8f41e90be247774fe37283f78dcbde91aaf15f9431be49c437e26f772754d4c7`)
- Original ZIP SHA-256 `1a09e64286d30831411c11946881a167a9495197e882491115408a3194f92948`.

## Integration gates
1. Confirm provenance and permitted use; keep source outside runtime packaging until approved.
2. Inspect mesh objects, topology, rig, shape keys, UVs, units, and rest pose in Blender; record findings, not assumptions.
3. Normalize a working copy to meters, Y-up, front +Z, preserving original source. Define common anatomical landmarks (shoulders, chest, waist, hips, elbows, knees, ankles).
4. Fit each garment on its own mesh using body-specific landmark alignment, surface deformation or cage transfer and skin-weight transfer where appropriate. Preserve garment thickness and material slots; avoid replacing the body when changing clothing.
5. Validate clipping and deformation for multiple body types, poses and height/shape changes; capture front, side and posed views. No changes to existing stage, shows or currently bundled character assets until validation passes.
