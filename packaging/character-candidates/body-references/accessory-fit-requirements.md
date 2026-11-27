# Universal accessory fitting

Accessories are independent of character sex and physique presets. Never deform the target body, head, facial features or skeleton to fit an accessory. Use the actual customized character landmarks, with a separate attachment frame per accessory family.

- Hair: fit scalp and hairline using scalp surface and head landmarks; preserve hairstyle, parting, length, texture and volume. Long hair additionally needs neck, shoulder, back and chest collision checks. Do not scale hair length with body mass.
- Eyewear: fit bridge, eye centers, temples and ear attachment landmarks. Preserve lens shape and optical alignment; adjust bridge and temple placement independently. Do not change nose, eyes or ears.
- Headwear: fit head circumference and crown height, preserving brim and design. Account for hair volume and permit explicit hairstyle/headwear compatibility rules. Do not silently flatten the head or discard hair.
- Other accessories: necklaces follow neck and chest; bracelets and watches follow wrist; earrings follow ear anchors. Maintain style and material identity.

Acceptance: reuse the same asset on different head widths, facial proportions, hair volumes and body builds; compare body/head geometry and parameters before and after accessory changes; inspect front, profile, rear and three-quarter views plus head turns and animation. Check intersections and attachment stability. Keep experimental assets out of production until verified. This is a requirements document, not evidence of runtime fitting support.
