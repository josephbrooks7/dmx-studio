Hat Fit, Head Anatomy and Hair Deformation

Character Creator and Accessory Physics Reference for DMX Studio

When a person wears a hat, the hat interacts with the shape of the skull, forehead, scalp, hair, ears and surrounding soft tissue. A realistic character simulation should account for these interactions rather than simply placing a hat over an existing hairstyle.

The hat should adapt to the character’s head dimensions, while the hair should dynamically respond to the hat’s internal shape, available space, material and tightness.

1. Impact on head shape

An adult human skull is rigid and does not significantly change shape when wearing a normal hat. However, the soft tissue surrounding the skull can experience minor compression.

* The forehead may develop a temporary indentation from a tight hatband.
* Scalp tissue can compress slightly.
* The upper ears may bend or flatten if covered by the hat.
* Skin may bunch slightly around the edges of an excessively tight hat.
* A tight hat may leave temporary pressure marks.
* The skull, facial structure and overall head proportions should remain unchanged.

The simulation should distinguish between rigid anatomical geometry and deformable soft tissue.

2. Hair compression inside a hat

Hair should not maintain its original volume underneath a fitted hat. It should compress, flatten, bend and redistribute according to the available interior space.

Uncompressed hair

Natural height, volume and direction.

Compressed hair

Reduced volume and altered hair direction.

Hair compression depends on several variables:

* Hair thickness and density.
* Individual strand diameter.
* Straight, wavy, curly or coily texture.
* Hair length.
* Styling products and stiffness.
* Hat crown height and internal dimensions.
* Hatband tightness.
* Hat material and structural rigidity.
* Duration of wear.
* Moisture and humidity.

Hair volume reduction should be localized to areas where the hat contacts the hair. Hair outside the hat should retain most of its natural characteristics.

3. Hair type and compression behavior

The following percentages are suggested initial simulation parameters, not clinically measured universal compression values. They should be adjustable and calibrated against real reference images.

Hair type	Suggested volume reduction under firm contact	Expected behavior
Shaved head	0–5%	Minimal deformation
Buzz cut	5–15%	Slight flattening
Short straight hair	20–50%	Flattens toward scalp
Medium straight hair	30–65%	Bends and redistributes
Wavy hair	25–60%	Waves become flatter
Curly hair	30–70%	Curls compress and cluster
Coily hair	30–75%	Dense volume compresses
Afro hairstyle	35–80%	Significant localized compression
Pompadour or quiff	40–85%	Height collapses and bends
Braids	5–25%	Limited compression; positional movement
Locs	5–30%	Redistribution and bending
Long hair	20–60%	Upper sections flatten; ends remain free

These values refer to local hairstyle volume or thickness under contact, not a reduction in the length of individual hair strands.

4. Hair redistribution

Hair should not simply shrink uniformly when a hat is equipped. It should move into available space.

For example, when a person with a large hairstyle wears a baseball cap, the hair may flatten on top while extending outward around the sides, temples and back of the head.

Curly hair with a baseball cap

Hair compresses beneath the crown while exposed curls retain their volume and may extend around the edges.

Ponytails and long hair

Hair can pass through an appropriate rear opening or extend beneath the hat without intersecting its material.

Hair beneath a beanie

The covered hair compresses while exposed sections remain relatively natural.

The system should preserve hair length, texture, color and identity while modifying its position and volume.

5. Hat tightness and fit

Hat tightness should be calculated using the character’s head circumference at the actual wearing position, the hat’s internal circumference, compressed hair thickness and the elasticity of the hat material.

Adult head circumferences commonly fall around 53–62 cm, although individuals can fall outside this range. Head shape also varies considerably between people with identical circumferences.

A circular hat opening should not be assumed to fit every head. Human heads are generally oval when viewed from above, with varying front-to-back lengths and side-to-side widths.

Hat tightness simulation

Loose

Comfortable fit

Tight

Illustrative hair compression

40%

Contact pressure

Moderate

Conceptual visualization of adjustable fit, not a validated biomechanical model.

Fit level	Physical behavior
Oversized	Air gaps, sliding and greater movement
Loose	Minimal pressure and hair compression
Comfortable	Secure contact and moderate compression
Snug	Increased hair compression and friction
Tight	Strong compression and possible skin indentations
Excessively tight	Pressure marks, discomfort and possible inability to fit

A rigid hat that is too small may sit higher on the head instead of forcing the head or hat to deform.

6. Different hat types and their effects

Baseball cap

Compresses hair around the forehead, temples, upper scalp and back of the head. Adjustable straps change the fit.

Beanie

Stretches around the head and hair. Applies distributed compression and can conform to the shape of a bulky hairstyle.

Top hat

Primarily contacts the head through its internal sweatband. The tall crown may provide substantial space for hair without compressing the top.

Fedora

Applies pressure around the sweatband. Crown indentations may compress taller hairstyles.

Cowboy hat

A relatively structured crown with concentrated contact around the sweatband. Hair compression depends on crown clearance.

Bucket hat

Flexible construction allows the material to adapt to the hair and head, with relatively distributed pressure.

Beret

Concentrated pressure around the opening, with additional space inside the upper portion of the hat.

7. Hat material and structural physics

Material	Elasticity	Structural rigidity
Knitted wool	High	Low
Cotton fabric	Low–moderate	Low
Stretch polyester	High	Low
Structured cotton	Low	Moderate
Felt	Low	Moderate–high
Leather	Low	Moderate–high
Straw	Very low	Moderate–high
Rigid formal hat shell	Very low	High

Flexible hats should deform around the head and hair. Structured hats should retain their manufactured shape, requiring the hair to accommodate the available space.

The simulation should also distinguish between the outer shell, inner lining, sweatband and adjustable fastening system.

8. Hair collision and clipping prevention

The hat should contain an internal collision mesh, separate from its visible external mesh.

Cross-section illustrating the relationship between the rigid hat shell, available interior space, compressed hair and anatomical head geometry.

The collision system should:

* Prevent hair from penetrating the hat crown.
* Prevent the forehead or scalp from penetrating the hat.
* Preserve hair visible below the brim.
* Allow hair to pass through intentional openings.
* Prevent ponytails, buns and braids from clipping through solid material.
* Allow soft hats to expand when physically appropriate.
* Maintain a small collision clearance to prevent visible flickering.
* Recalculate collisions whenever head dimensions or hairstyles change.

Simply hiding the entire hairstyle when a hat is equipped should not be the default solution.

9. Dynamic head customization

Whenever the user adjusts a character’s head, the hat and hair fitting systems should automatically recalculate.

Relevant anatomical adjustments include:

* Head circumference.
* Head width and depth.
* Skull height.
* Forehead height, width and curvature.
* Temple width.
* Back-of-head curvature.
* Ear height, size and protrusion.
* Hairline position.
* Scalp shape.

Male and female characters should use the same underlying fitting system, based on individual anatomical measurements rather than fixed gender-specific hat placements.

Changing body height may influence default head dimensions, but head size and hat size should remain independently adjustable.

10. Recommended character creator controls

Control	Function
Hat size	Adjusts internal dimensions
Hat tightness	Adjusts fit and contact pressure
Wearing height	Positions the hat vertically
Forward/backward tilt	Adjusts wearing angle
Side tilt	Allows asymmetrical styling
Rotation	Changes hat orientation
Crown height	Adjusts internal vertical clearance
Hair compression	Controls hair deformation
Hair redistribution	Controls displacement around edges
Material stiffness	Determines hat deformation
Elasticity	Determines stretching behavior
Automatic fitting	Fits the hat to individual anatomy
Manual adjustment	Allows custom styling overrides

Automatic fitting should be enabled by default, while still allowing the user to override the resulting position and fit.

11. Hat hair after removal

Hair should not necessarily return to its original shape immediately after a hat is removed.

Depending on hair texture, styling products, moisture, compression and duration of wear, hair may temporarily retain the shape imposed by the hat.

This can include flattened roots, reduced crown volume, bent strands, disrupted curls, a visible band-shaped indentation and increased volume around the sides.

A hair recovery system could gradually restore the original hairstyle, with an optional instant reset or persistent hat-hair setting.

12. Movement and animation

During character animations, the hat should follow the head bone while allowing physically appropriate secondary movement.

A tightly fitted hat should remain relatively stable during dancing, walking and head movements. A loosely fitted hat may shift, tilt or bounce slightly.

Exposed hair should continue to respond to gravity, movement, inertia and wind, while hair contained beneath the hat should have restricted movement.

For live stage performances, these calculations should be optimized so that hair and accessory physics do not interfere with audio playback, lighting synchronization or stage rendering performance.

13. Recommended implementation architecture

DMX Studio should maintain separate but interconnected systems for:

* Anatomical head geometry.
* Scalp and soft tissue.
* Original hairstyle geometry.
* Deformed hairstyle geometry.
* Hat exterior geometry.
* Hat interior collision geometry.
* Hatband and fastening constraints.
* Material elasticity and stiffness.
* Accessory positioning and attachment.
* Hair recovery and secondary animation.

The original hairstyle and head geometry should always be preserved as non-destructive source assets. Equipping or removing a hat should never permanently alter the underlying character model.

The overall objective is to simulate a person actually wearing a hat, rather than a 3D hat floating above or intersecting a character’s existing hairstyle. The head should retain its anatomical identity, the hair should respond naturally to compression and available space, and the hat should behave according to its construction, size and material.