# Current character integration priorities

The user reports updated models and new renders running on their Mac. Do not duplicate asset acquisition, conversion or rendering work or overwrite their candidate assets. Local results have not yet been independently verified.

Software priorities: normalize imported model axes and height; support persistent manual front-facing correction when metadata is ambiguous; ground performers on the stage; ensure Face Mode starts at the face and front/back/side controls remain predictable during appearance edits; verify preview exposure, head-relative hair and accessory fitting, and live stage visibility. Placement and camera control commits have passed component preflight, but visual validation remains pending.

Integrate the user's updated assets once available and licensed. Preserve saved shows, Intel/macOS 12 compatibility and existing updater. Deliver one consolidated DMX Studio.app release, not separate component apps. Defer venue work until character integration is verified.

## Incoming local customization assets
The user reports new nose, skin, clothing and hair assets arriving in ~/Downloads on their Mac, ready for processing. Inventory accessible files and compare hashes, licenses, existing manifests and candidate assets before conversion. Preserve originals and backups. Categorize by body compatibility, rig, UV layout and attachment points; use compatible morph targets for nose shapes, compatible material maps for skins, fitted garments and head-local hair. Do not assume arbitrary meshes are interchangeable. Reuse already converted assets and coordinate with local renders. Package verified assets in the existing app and expose individual choices in Character Studio. Local files not accessible to the current environment remain unverified.

## Exclusive customization slots
Nose presets replace the prior nose morph: reset the nose channel to its neutral baseline before applying the selected compatible target, never add a second nose mesh or accumulate preset deltas. Preserve unrelated morph channels and materials. Face, hairstyle, skin, eye appearance, eyebrows, shirt, pants, shoes and hat each use a single active selection per slot; replace the previous selection atomically. Allow compatible accessories and intentional clothing layers in separate slots. Persist stable selection IDs and test repeated A/B/A switching for no accumulation or duplicate geometry. Existing saved shows must remain compatible.

Anatomical feature slots also include ears (paired by default), lips, jaw, chin and cheeks. Prefer topology-compatible morphs; when using replacement geometry, remove the corresponding original geometry and validate seam continuity, alignment and material compatibility. Never overlay duplicate anatomy. Preserve independent selections and test switching back to neutral.

## v1.0.411 acceptance correction
Existing candidates are not delivered features. Prioritize packaging verified LFS payloads with attribution, a runtime catalog with stable IDs and compatible body/slot metadata, actual selectable options, and preview/stage parity. Verify installer contents and each selectable asset in the running application. Do not count uploaded files as integrated. Do not ship unverified-license female body or incompatible morphs. No additional asset acquisition unless a concrete compatibility gap is identified.
