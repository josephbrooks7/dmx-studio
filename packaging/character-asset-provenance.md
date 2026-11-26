# Character asset provenance and backup status

This document tracks the two **locally generated** DMX Studio preview assets. It is not a license grant, a completed cloud backup, or an approval to publish these meshes.

| Artifact | Local location (user Mac) | SHA-256 | Size (approx.) | Remote binary backup |
| --- | --- | --- | --- | --- |
| Male base USDZ | `~/DMX-Character-Backup/male-body.usdz` | `a53db593ffda2dd17e74eabfd37aac8bc660b6232837bd209c6cf4170f115ca4` | 794 KiB | **Not yet uploaded** |
| Female base USDZ | `~/DMX-Character-Backup/female-body.usdz` | `d2d15b2602b71f8c65a995dcc410990b2549d74f9154370141ca0cfcce03a610` | 369 KiB | **Not yet uploaded** |

Source archive: `human-models-set-malefemale-rigged.zip` → `source/HumanModels.glb` → selected base character meshes → exported GLBs → Blender-exported USDZ. User verified these SHA-256 values after copying to a separate local backup.

**Rights gate:** source archive and models have no confirmed redistribution license. The repository is public; do not commit either USDZ, original GLBs, or derived versions to this repository or any public release until distribution permission is documented. Git LFS **does not** make the assets private. Avoid uploading source models or other third-party asset packs to public Git history for the same reason.

After rights verification, store approved assets using Git LFS (or private restricted-access binary storage), push, and verify with a fresh independent remote clone/pull and SHA-256 comparison before marking this entry as remotely backed up. Source archives and high-resolution derivations should remain versioned and recoverable.

The USDZ files are only basic skin-material body previews, not assembled characters. Continue separate work on distinctive heads, eyes, hair, clothing, fitting, lighting, and rendering with independently documented rights. Existing shows and stable release assets must remain untouched.
