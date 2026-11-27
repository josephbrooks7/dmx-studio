# Anatomy reference for DMX Studio characters

The rules the character skeleton, poses, gestures, body sliders and clothing must follow so
performers move and look like real people. Values are typical adult ranges collected from the
clinical sources listed at the end; people vary, so these are limits for "natural", not exact
measurements. Angles are from the anatomical neutral position (standing, arms at the sides,
palms forward), which is not the same as the T/A rest pose our meshes are stored in.

## 1. Joint types (what kind of movement each joint allows)

| Type | Movement | Our bones (Mixamo names) |
|---|---|---|
| Ball and socket | Forward/back, out/in and twist (3 axes) | `Arm` (shoulder), `UpLeg` (hip) |
| Hinge | Bend and straighten only (1 axis) | `ForeArm` (elbow), `Leg` (knee), finger joints 2-3, toes |
| Pivot | Twist only | Head turn (top of neck), forearm palm-up/palm-down twist |
| Ellipsoid / condyloid | Everything except twist (2 axes) | `Hand` (wrist), finger joint 1 (knuckles) |
| Saddle | Two axes, shaped for opposition | `HandThumb1` (base of thumb) |
| Plane / slightly mobile | Small glides; large motion only as a sum of many | `Spine`, `Spine1`, `Spine2`, `Neck`, `Shoulder` (shoulder blade) |

## 2. Joint ranges (degrees from neutral)

| Joint | Movement | Range |
|---|---|---|
| Shoulder (`Arm`) | Raise forward (flexion) | 0-180 |
|  | Reach back (extension) | 0-50 |
|  | Raise to the side (abduction) | 0-180 |
|  | Across the body (adduction) | 0-50 |
|  | Twist in / out (arm at 90° out) | 90 / 90 |
| Elbow (`ForeArm`) | Bend | 0-145, never backward (0 = straight) |
| Forearm | Palm down / palm up | 80 / 80 |
| Wrist (`Hand`) | Bend down / up | 70 / 70 |
|  | Toward thumb / toward little finger | 20 / 30 |
| Finger knuckle (joint 1) | Curl / bend back | 90 / 30 (side spread 20-30) |
| Finger middle (joint 2) | Curl | 100-110, no bend back |
| Finger tip (joint 3) | Curl / bend back | 70-80 / 0-10 |
| Thumb base (joint 1) | Curl / spread away from palm | 45-50 / 60-70 |
| Thumb middle / tip | Curl | 55 / 80 |
| Hip (`UpLeg`) | Lift forward (flexion) | 0-120 (knee bent), ~90 (knee straight) |
|  | Leg back (extension) | 0-30 |
|  | Out to the side / across | 45 / 20-30 |
|  | Twist in / out | 40 / 50 |
| Knee (`Leg`) | Bend | 0-140, forward only. No sideways bend, no sliding, small twist only when bent |
| Ankle (`Foot`) | Toes up / toes down | 20 / 50 |
|  | Sole in / sole out | 35 / 15 |
| Toes | Curl / bend up | 40 / 60-70 |
| Neck + head | Nod down / look up | 80-90 / 50-70 (AAOS; other sources 45-60 / 60-75) |
|  | Tilt ear to shoulder | 20-45 per side |
|  | Turn left or right | 70-90 per side |
| Upper back (thoracic) | Bend forward / back | 30-40 / 20-30 (stiffest region: ribs) |
|  | Twist | ~35 |
|  | Side bend | 20-25 |
| Lower back (lumbar) | Bend forward / back | 40-60 / 25-35 |
|  | Twist | 10-15 (very little) |
|  | Side bend | 20 |

**Which ranges apply.** The values above are active ranges (what a person reaches under their
own power); passive ranges, pushed by an outside force, are larger. Performers use active
ranges, and gestures stay comfortably inside them (about 80% of the limit), because people
rarely perform at their end range and end-range poses look strained.

**Individual flexibility.** Default characters allow only 0-5° of elbow and knee overextension
and modest finger back-bend. Clinical hypermobility (Beighton score, 5+ of 9 in adults) starts
at more than 10° of elbow or knee overextension, little-finger knuckle bending back beyond 90°,
thumb to forearm, and palms flat on the floor with straight knees. A later per-character
flexibility setting (stiff / average / flexible) scales the limits, e.g. dancers vs. stiff
rockers, never past the hypermobile thresholds by default.

## 3. Joints move together (coordination rules)

- **Shoulder rhythm.** Raising the arm is shared between the shoulder joint and the shoulder
  blade at about 2:1 (90° of arm raise = ~60° at the joint + ~30° of shoulder-blade rotation).
  The first ~30° is mostly the joint. For our rig: the `Shoulder` bone takes about one third of
  any arm raise above 30°. Without this, raised arms look pinned to a rigid torso.
- **Back and hips when bending forward.** The lower back leads early in the bend, the hips take
  over toward the end (the hips supply roughly two thirds of a full forward bend). Coming back
  up reverses it: hips first, back last. Never put a whole bend into one spine bone.
- **Spine bends are spread out.** Bending and twisting are divided across `Spine`, `Spine1` and
  `Spine2` (lumbar gets little twist, thoracic most of it), plus `Neck` and `Head` for the head.
- **Head turns.** Most head rotation happens at the very top of the neck; the rest spreads
  through the neck.
- **Head tilt couples with a small turn.** Tilting the ear toward a shoulder brings a few
  degrees of turn the same way, instead of a rigid single-axis tilt.
- Neck mobility drops with age (if older characters are added later, their neck limits shrink).
- **Knees.** Ligaments stop the shin sliding forward/back under the thigh and stop sideways
  bending. In the rig the knee only rotates, never translates, and only about its bend axis
  (a little twist allowed when bent).
- **Thumb.** Sits rotated about 80° relative to the other fingers so it can oppose them; a
  "closed fist" or "mic grip" wraps the thumb across the fingers, not alongside them.

## 4. Muscles and what they mean for body sliders and deformation

Sliders shape real muscle groups rather than inflating the body. Each group listed with its
slider and the clothing area it pushes on.

| Region | Muscle groups | Slider | Notes |
|---|---|---|---|
| Chest | Pectoralis major: upper (clavicular) and lower (sternal) heads | Chest / pecs, bust | Upper and lower shaped separately; shirts drape from here |
| Shoulder | Deltoid (cap), rotator cuff (deep, stabilizes) | Shoulder width / delts | Sets shirt shoulder seam |
| Upper arm | Biceps, brachialis (front); triceps (back) | Biceps, triceps | Biceps bulges slightly as the elbow bends |
| Forearm | Flexors (front), extensors (back) | Forearm thickness |  |
| Hand | Thumb pad muscles | none | Keep volume when the thumb moves |
| Abdomen | Rectus abdominis: paired vertical strap from ribs 5-7 to the pubic bone, crossed by three tendinous bands, which is the "six-pack" when developed; split down the middle by the linea alba | Abs definition | Definition = deeper grooves at the three bands and the midline, not a bigger belly |
|  | External oblique (outermost, fibers run down-and-in like hands into front pockets), internal oblique, transversus | Obliques / love handles, waist | Fuller stomach and love handles sit over these |
| Stomach fat | Subcutaneous fat layer over the wall | Stomach (flat - rounded - fuller), upper vs lower | Separate from muscle definition |
| Glutes | Gluteus maximus (largest, main hip extensor), medius, minimus | Buttocks size and shape | Trousers must follow |
| Thigh | Quadriceps (front), hamstrings (back), adductors (inner) | Thigh thickness | Separate front/back/inner shaping |
| Lower leg | Gastrocnemius + soleus (calf) | Calf size |  |

## 4. Shoulders

- Three bones (shoulder blade, collarbone, upper arm) and the most mobile joint in the body:
  the ball is about 4x the socket's surface, in a loose capsule, allowing forward raise, side
  raise, across, rotation in/out and full circles (arm circles are valid within the limits).
- The ball stays centered in the socket (rotator cuff pulls it in): the `Arm` bone only rotates
  about a fixed pivot, never translates. Whole-shoulder shifts (shrug, reach, the shoulder
  blade's third of an arm raise) come from the `Shoulder` bone (collarbone + shoulder blade).
- Two shoulder widths, two sliders:
  - **Frame (biacromial, bone tip to bone tip):** spacing of the `Shoulder` bones. Men 5th /
    50th / 95th percentile 15.1 / 16.3 / 17.6 in (median 41.5 cm); women 13.2 / 14.4 / 15.6 in
    (median 36.5 cm).
  - **Muscle (bideltoid, across the deltoids):** deltoid slider on top of the frame. Men
    18.1 / 20.0 / 22.3 in (median 50.9 cm); women 16.0 / 17.7 / 19.7 in (median 45.0 cm).
  - Realistic mode tops out near the 95th percentile ("very broad"); stylized can go further.
  - V-taper marker: shoulder circumference / waist circumference ~1.6 is the often-quoted
    athletic ideal (an aesthetic reference, not an average) for the athletic end of the build
    slider. Shirt shoulder seams key off the frame width.
- Raised arms: the deltoid bunches and the armpit opens; corrective shapes keep the shoulder
  and sleeve round instead of pinching (arms-up, victory V, fist up).

## 4a. Hips and glutes

- Hip = femur head in the deep pelvic socket (ball and socket), see section 2 for ranges.
- **Pelvis stays nearly level on one leg:** gluteus medius/minimus hold it, so contrapposto and
  mid-step pelvis tilt is small (a big drop on the free side reads as a limp).
- **Walking stride:** the back leg extends about 20° behind the body at a comfortable pace.
- **Hip width is bony:** the greater trochanter (outer upper thigh) is the widest point of the
  hips; the hip measurement and trouser fit key off it. Glute and body-fat sliders add shape
  around it; the bony width is fixed per skeleton (a separate pelvis-width slider changes it).
- **Glute slider = gluteus maximus** (the large buttock muscle, main hip extender); it firms
  when a performer steps back, pushes off or stands from a crouch.
- **Seated performers** (drums, keys) bear weight on the two sit bones; the seat and the
  trousers' seat area compress there instead of floating above the stool.

## 4b. Hands

- Structure: 27 bones (8 carpals, 5 metacarpals, 14 phalanges). Our skeleton's three bones per
  finger plus the wrist cover what's visible; the thumb's base joint rotates it across the palm.
- **Resting hand (default for every performer):** never flat. Fingers form a cascade of
  increasing curl from index to little finger; knuckles roughly 45-75°, middle joints about 10°,
  tips 0-10°, wrist slightly bent back, thumb slightly away from the palm. The palm cups a little
  (transverse and lengthwise arches).
- **Wrist-finger coupling:** bending the wrist back curls relaxed fingers further; bending it
  down opens them. Applied automatically to relaxed hands so they react to every wrist move.
- **Mic grip = power (cylindrical) grip:** all four fingers wrapped around the handle, thumb
  closing over them, wrist near neutral. Not a fingertip hold.
- **Precision (pinch) grip:** thumb pad against finger pads for a guitar pick, drumstick tip,
  setlist or water bottle cap.
- **Thumb:** rests rotated about 80° relative to the other metacarpals so it faces the fingers.
  Its base joint is the most mobile in the hand: ~40-50° flexion/extension, ~80° spread,
  70-110° twist, which is what lets it close over a mic or meet the fingertips.
- **Finger spread:** knuckles fan only about 25-30° in total for each finger; the little finger
  spreads most (it spans objects). Open hands and horns never splay past this.
- **Knuckle row curves** (distal transverse arch), it is not a straight line.
- **Fists and grips converge:** curling fingers angle slightly toward the base of the thumb
  rather than folding straight down, so a fist or mic grip looks compact, not claw-like.
- Gesture hands (peace sign, rock horns, fist, point) start from these shapes and stay within
  the finger ranges in section 2; fingers never bend backward or sideways past their limits.

## 5b. Clothing sizes and body measurements

Characters are measured like a tailor would, by slicing the body mesh at standard landmarks:
- **Waist:** around the natural waist, about 1 in (2.5 cm) above the navel.
- **Hip:** around the fullest part of hips and seat, about 8 in (20 cm) below the natural waist.
- **Inseam:** crotch to ankle bone along the inside of the leg; **outseam:** natural waist to
  ankle along the outside.
- **Thigh:** around the fullest part, about 1 in below the crotch.
- **Underbust / band:** snug around the ribcage just beneath the bust (the torso frame).
- **Bust:** loosely around the fullest point. Cup = bust minus band, one cup per inch
  (<1" AA, 1" A, 2" B, 3" C, 4" D, 5" DD/E, 6" DDD/F ... up to about 11" K).
- **Chest (male):** around the fullest point of the chest; pectoral development is separate.
- **Shoulder point:** the natural end of each shoulder; shoulder width is measured across the
  back from shoulder bone to shoulder bone.
- **Torso length:** base of the neck to the natural waist (sets where a top's waist and hem
  land on short vs long torsos).
- Size labels are only a display computed from real measurements; labels vary by brand and era
  and are never the source of truth.
- **Era presets** (themed shows): adjust waist height, shoulder width, hip room, sleeve length
  and button height on any garment, e.g. mid-century = higher waist, narrower shoulders, fitted
  waist with generous hip room, darted bodice; vintage men's jackets = higher buttons, shorter
  sleeves, narrower shoulders.
- **Sleeve length:** nape of the neck to the shoulder point, plus shoulder point to the wrist
  bone (= half the shoulder width + arm length from the skeleton), arm relaxed and slightly bent.
  Sleeves include a small movement allowance because raising or bending the arm pulls fabric up
  the arm; sleeve length is verified in the pose tests too (in arms-up and mic-hold a full sleeve
  rides up only modestly, never baring half the forearm).

Fit checkpoints the fitter verifies on every garment and body (tailoring rules):
- **Shoulder seam** ends at the natural shoulder point; down the arm = too big, pulling or
  dimpling = too small. Shoulders are fitted first when moving a top to a new body.
- **Sleeves end at their style's landmark on the wearer's own arm** (works on any arm length):
  cap = outer edge of the shoulder (covers only the deltoid); short = about mid-bicep;
  elbow = at or just past the elbow; three-quarter = slimmest part of the forearm;
  bracelet = just above the wrist bone; full shirt = cuff meets the base of the thumb, just
  covering the wrist bone; suit jacket = about 1/2 in above the shirt cuff; coat = up to the
  knuckles. One garment can be offered in several sleeve lengths by ending the sleeve at a
  different landmark. The hand-coverage check compares each sleeve with its own style's
  landmark (a coat at the knuckles passes; a tee there fails).
- **Sleeve shape** is independent of length: fitted (follows the arm, low ease), tapered (wider
  at the shoulder, narrowing to the cuff), flared (widens toward the end), bell (dramatic flare,
  volume and movement), oversized. Flared and bell sleeves count as loose fabric and swing with
  secondary motion; fitted and tapered stay skinned to the arm.
- **Jacket length** covers the seat; hem near the thumb knuckle with arms relaxed.
- **Collar:** about 1/2 in of shirt collar shows above a jacket collar; lapels lie flat.
- **Layering:** inner layers show at collar and cuffs and never poke through outer layers.
- **Trouser break** is chosen, not accidental: no break (hem just touches the shoe top),
  half break (one small fold, the default), full break (deeper fold).
- **Oversized and boxy fits** (tops): oversized carries about 30% extra chest ease (e.g. a
  130 cm garment chest on a 100 cm body), wider sleeves, more room at chest and waist, a body
  about 10 cm longer (hem at hip or mid-thigh depending on torso length) and dropped shoulders
  (seam intentionally below the natural shoulder point, exempt from the shoulder-seam check).
  Oversized drapes and moves (loose fabric, secondary motion); boxy is equally roomy but keeps
  a structured, squared shape. Wearing a garment one or two sizes up is a deliberate style
  option that intensifies the look.
- **Trouser leg shape** (independent of fabric: "joggers are a cut, sweatpants a fabric"):
  tapered (closes in from knee to ankle, about 2 in narrower at the ankle than the knee),
  straight / slightly open (looser fall), slim, bootcut, wide. **Hem type:** ribbed or elastic
  cuff locked at the ankle bone (keeps the hem off the shoe, no break options), or open hem
  using the break settings. Seat and thigh keep enough ease before any taper, so fuller glutes
  and thighs are never flattened by a slim cut. Fleece = heavier knit: more volume, softer
  folds, less cling than thin performance knit.
- **Trouser spec points** (factory tech-pack style, measured by the fitter on every fitted
  garment for a QA spec sheet): waist relaxed and stretched (half widths), waistband height,
  hip, front rise, back rise, thigh 2.5 cm below the crotch, knee, inseam, outseam, leg opening
  (relaxed and stretched on cuffs), cuff height, pocket placement. Rules: back rise is longer
  than front rise (follows the seat; never flatten glutes or dip the back waistband); outseam
  exceeds inseam by about the rise (automatic check); elastic waistbands settle on the body's
  waist anywhere between their relaxed and stretched widths; tolerances are looser for knits
  and for long measurements than for wovens and short ones.
- **Chest:** room for a flat hand under a jacket; fabric pulling into an "X" = too small.
- Fit types: slim (hugs the body, more taper), modern (some room, tapered), classic (more room
  through chest and middle). Suit length letters by height: S 5'5"-5'8", R 5'9"-6'0",
  L 6'1"-6'3", XL 6'4"+.

Bust controls are three independent sliders: ribcage (band, from build/weight), bust size
(cup, in real inches over the band, AA to K), and shape (shallow / average / full projection).
The ribcage doesn't change when the bust does. Male chest: frame circumference plus a separate
pectoral-development slider. Tops report chest ease in inches on every body and flag a top too
tight across the bust instead of flattening the body.

Each character gets real measurements and a size label (men's waist x inseam, women's numeric
and S/M/L), shown in Character Studio.

Slider ranges match real size charts so every setting is a real body:
- Men's waist 28-46 in (71-117 cm, XS-4XL); inseam about 28-38 in and tied to height
  (under 5'7": 28-32, 5'7"-5'11": 30-34, 6'-6'3": 32-36, taller: 34-38+).
- Men's chest S 36-38, M 39-40, L 41-43, XL 44-46, XXL 47-49 in, with waist about 5-6 in
  smaller in every size (the "drop"). Build sliders use the drop: average ~5-6 in, athletic /
  muscular larger (V-shape), fuller builds shrink it toward zero.
- Women's waist about 23-42 in with hips about 33-52 in (sizes 0-24, XXS-4XL); inseam petite
  ~28, regular ~30, tall 32-34 in.

Fit styles map to the fitter's ease: slim (minimal ease), regular, relaxed (generous ease);
rise low (2-3 in below the natural waist), mid (at the waist), high (above it). A garment's
waist opening runs about 1 in larger than its labeled size.

Garment vs. body: garment measurements are larger than body measurements by the ease (room,
stretch, movement). The fitter reports ease in real units at chest/bust, waist, hip and thigh
for every garment on every body, and flags a garment that is too tight for a body.
- Flat-lay garment measurements x 2 = circumference (20 in flat bust = ~40 in around).
- Grading: a size run steps each garment measurement about 1/2-1 in per size, so one garment
  can be generated XS-4XL instead of modeled per size.
- Fabric type per garment changes fit with the same measurements:
  - **Knit** (tees, leggings): stretches and follows body shape closely; low ease.
  - **Rigid** (denim, blazers): keeps its own shape and stands off the body; minimum ease kept.
  - **Flowy woven** (blouses, open shirts): hangs from shoulders and moves with secondary motion.

## 5d. Feet and shoes

- Foot length defaults from height (about 15% of stature, a general anthropometric proportion)
  and can be adjusted; width defaults to medium (D).
- Each character gets a real shoe size from foot length. Reference, U.S. men by height
  (estimated, no official data): 5'5" and under 7-9, 5'6"-5'9" 9.5-10.5, 5'10"-6'2" 11-12.5,
  6'3"+ 13-20+; average about 10.5.
- Shoes moved to another body scale to that foot's real length and width (not the source
  character's), keep the sole flat on the stage, and never let the foot poke through.

## 5c. Prints and logos on clothing

Performers can wear printed graphics (Red Velvet merch, artist logos, tour art). Print zones sit
at garment landmarks and are sized in real inches (width x height), so a design covers the same
real area on any body:
- Adult front: standard 11 x 11, max 11.25 x 14, jumbo 12.5 x 17
- Youth front: toddler 5.5 x 5.5, small 8.5 x 8.5, med/large 10.5 x 10.5
- Left chest: standard 4.5 x 4.5, max 5 x 5, pocket 3.5 x 3.5
- Sleeve: 2 x 11.25 (max 2.5 x 14); pant leg 2.5 x 14 (large 5 x 24)
- Cap front 4 x 2.25; visor 4 x 1.25
Designs scale proportionally to the zone width. Default placement (common screen-print practice,
not from the size source): front print starts about 3 in below the collar, back print about
4 in below. Prints are painted into the garment texture so they stretch over the chest or bust
and fold with poses; users can upload PNG art and choose zone and size tier.

## 5. Body proportions

Segment lengths scale roughly with height (Drillis & Contini proportions, widely used). These
are averages: lengths like shoulder height track height well, but widths such as shoulder
breadth vary a lot between people regardless of height. So height and limb-length sliders can
default to proportional scaling, while shoulder width, hips and similar widths need their own
independent sliders. Garments must stretch with bone lengths (done in the fitter) and fit
widths from the body surface.

## 6. Skin deformation at joints

Standard real-time skinning (linear blend skinning) loses volume at bending joints and
collapses into a twisted "candy wrapper" when a bone twists (forearm, wrist, shoulder).
Dual quaternion skinning keeps volume and removes the candy wrapper but can bulge outward on
deep bends. Production rigs combine them and add corrective shapes at problem joints.

For our characters:
- Knees and elbows: keep the joint's volume on deep bends (kneecap and elbow stay round in
  crouches and mic holds), using corrective shapes driven by the bend angle.
- Forearm and wrist twist: spread the twist along the forearm (twist sharing) so the wrist
  doesn't pinch.
- Shoulders and hips: volume-preserving correction for raised arms and wide stances.
- Clothing is skinned to the same skeleton, so the same rules apply to sleeves and trouser
  knees.

## 7. Physics and gravity

Principle: imitate physics, don't simulate it. Be exact where viewers notice errors (gravity,
balance over the feet, planted feet, jump arcs); approximate cheaply elsewhere (hair and loose
cloth as a few spring-driven bones, not full cloth or strand simulation); skip what nobody can
see. Whatever is chosen behaves the same in every pose, song and export. This keeps the whole
performer system within the 2016 Intel MacBook Pro budget.

Performers live on a stage under normal gravity (g = 9.81 m/s², ~1 g). Real-world units
(metres, kilograms, seconds) are used everywhere so motion has believable weight: a smaller g
looks floaty, a larger one looks like collapsing.

**Balance (center of mass over base of support).**
- A standing person stays balanced by keeping the vertical line through the center of mass
  inside the base of support (the area under and between the feet). Every pose and gesture is
  checked for this: arms thrown out, a lean to the mic or a crouch must be offset by the hips
  and torso so the weight stays over the feet, otherwise the performer looks like falling.
- A wide stance or low crouch has a bigger base and a lower center of mass, so it is more
  stable and can lean further (why the wide bass stance and the crouch look grounded).
- Even standing still people sway slightly; the idle animation includes this gentle sway.

**Weight on one leg (contrapposto).** The natural relaxed stance: most weight on one straight
"engaged" leg, the other "free" leg relaxed and slightly bent. The hip over the engaged leg rises
and swings out, the shoulders tilt the opposite way, and the spine forms a gentle S-curve, with
the head finishing the curve. Performers default to this rather than standing square, and shift
weight between legs during idles.

**Ground contact.** Feet never float above or sink into the stage. Foot IK keeps planted feet
locked to the floor while the hips and knees move (crouches, swaying, stepping), and the
character is grounded by its lowest foot, not by its bounding box.

**Secondary motion (things that follow the body).** Hair (ponytails, long hair), loose clothing
(open shirts, hems), jewelry and mic cables move after the body moves: they lag, swing, overshoot
and settle under gravity. Real-time engines do this with spring-damper chains or position-based
dynamics (moving points directly to satisfy length and collision constraints, which stays stable
at game frame rates). For us:
- Ponytail and long hair: a short bone chain driven by springs + gravity, colliding with the
  head, neck and shoulders.
- Loose garment areas (shirt hems, sleeves ends): light spring offsets on top of skinning,
  never passing through the body (same clearance rules as the fitter).
- Tight garments stay purely skinned.

**Jumps and spins (airborne moves: a jump on the drop, a spin, a leap off a riser).**
- Once the feet leave the stage the center of mass follows a fixed arc (a parabola under g) set
  by the takeoff speed and direction. Arms and legs can move around it, but nothing done in the
  air changes that path. Hang time for a jump of height h is 2*sqrt(2h/g) (a 30 cm jump is
  ~0.5 s in the air).
- The body rotates about its center of mass. With no torque from gravity, angular momentum is
  conserved: pulling arms and legs in spins faster, spreading them slows the spin, and an arm
  swung one way turns the body the other way. A spin can't start or speed up mid-air without
  such a counter-movement.
- Takeoff: a crouch (hips, knees and ankles bend) before the push, arms swing up with it.
- Landing: toes first, then ankles, knees and hips bend together over a short moment to absorb
  the impact, followed by a small settle and recovery. Never land with locked straight legs.
  Hair and loose clothing keep falling briefly after the feet land, then settle (secondary motion).

**Locomotion (walking or jogging across the stage).**
- Each foot lands under the center of mass, not reaching far in front of it.
- The body bobs only about 3-5 cm per step and never rises above standing height.
- Walk vs run bob: walking vaults over a straight support leg, so the body is highest as it
  passes over the planted foot; running compresses like a spring, so the body is lowest there.
- Less bob comes from shorter strides at a higher step rate.
- Lean comes from the ankles with head, shoulders, hips and ankles stacked, not a bend at the waist.
- Arms swing forward and back with the opposite leg (a saw motion), not up and down.
- Propulsion pushes the ground backward; faster movement means quicker steps with shorter
  ground contact, not only longer strides.
- Stride length and step rate match the distance actually covered, so planted feet never slide
  on the stage (no foot skating); foot IK keeps each planted foot locked until it lifts.

**Fixed physics time step.** All physics (hair, cloth, sway) steps at a fixed rate, e.g. 60 Hz,
independent of the display frame rate; rendering interpolates between the last two physics
states. This keeps motion identical at 30 fps (Light mode on the 2016 MacBook Pro) and 60 fps,
and identical in exported videos. Frame time is capped so a slow frame can't make the
simulation spiral.

**Collision.** Performers and props collide with the stage floor, mic stands and instruments so
hands rest on the mic and guitar instead of passing through them.

## 8. Performer idle and gesture system

A performer standing perfectly still reads as unnatural. Idles are layered:

1. **Base layer (always on):** breathing (chest and shoulders rise/fall), slight postural sway,
   contrapposto weight on one leg with periodic weight shifts between legs.
2. **Music layer:** nod or foot tap on the detected beat; sway amplitude follows song energy
   (subtle in verses, bigger in choruses, still in silences).
3. **Fidgets (occasional, randomized, never repeating back-to-back):** adjust the mic or stand,
   hand through hair, tug clothing, look out across the crowd, glance at bandmates, point to the
   audience; instrumentalists touch up tuning or adjust the strap.
4. **Interaction:** bandmates turn toward each other during solos; the singer looks back to the
   drummer before a drop.
5. **Section gestures:** song structure triggers gestures (arms up on a chorus, fist up on the
   final hit, mic-stand lean through a verse), the same way it triggers lights.
6. **Between songs / long waits:** escalating rest idles (weight shift, then a water sip, then
   talking to the band or tuning).
7. **Role and personality:** singer, bassist, guitarist, drummer and keys each get their own
   idle set; later a style per character (energetic, chill, brooding) picks among them.

8. **Reacting to the light show:** squint or raise a hand when the followspot snaps on, turn
   toward a sweeping beam, wave through fog when the fog machine fires, more energy as the lights
   build. The performer and the DMX show read as one show.

Building each idle loop:
- Loop length comes from a real calm breath (resting breathing is roughly 12-20 breaths a
  minute, so about 3-5 s per breath); inhale lifts the chest and raises the shoulders slightly.
  Breath timing varies a little from cycle to cycle instead of repeating exactly.
- First and last poses match exactly, and the duplicate end frame never plays twice (no hitch).
- Eased curves, never linear motion.
- Weight shift: pelvis slides over the supporting foot while both feet stay planted; animate
  hips and spine first, then arms and head.
- Overlap: shoulders and head trail the chest by a few frames; hair and loose clothing trail
  further (secondary motion).
- Break left-right symmetry and offset keys between sides; mirrored motion looks robotic.
- Small pauses inside repeated actions.
- Mocap clips are simplified or exaggerated to suit each character's style.
- The next idle is picked at random (never the same one twice in a row) and blended in and out
  over a fixed number of frames, never snapped.
- Judge idles from the real stage cameras (Overview, Audience), not only close-ups.

Restraint: idles stay subtle because shows loop performers through whole sets; big gestures
are saved for real song moments so they don't turn repetitive or irritating.

All layers obey the joint table, balance and ground-contact rules, and blend smoothly into each
other rather than snapping.

## 9. How this is used

1. **Joint table** (`packaging/joint-limits.json`, shared by the review renderer and the app):
   for each bone, its joint type, allowed axes and the ranges above. Any pose, gesture or
   animation clip is clamped to these before it is shown.
2. **Coordination rules** (section 3) are applied when building poses so raised arms bring the
   shoulder blade, bends are spread over the spine, and so on.
3. **Natural movement** comes from real motion-capture/animator clips on our Mixamo skeleton;
   the table only stops impossible bends.
4. **Body sliders** follow the muscle groups in section 4.
5. **Deformation fixes** in section 6 for joints that pinch.
6. **Physics** in section 7: balance check on every pose, foot contact, spring-driven hair and
   loose clothing at a fixed time step.

## Sources

- Joint types: Teach Me Anatomy, "Classification of Joints"; Cleveland Clinic, "Joints"; Johns
  Hopkins Medicine, "Anatomy of a Joint"; Cleveland Clinic, "Elbow Joint".
- Knee structure: Prof Adrian Wilson, "Knee Anatomy".
- Ranges of motion: WikEM "Range of motion by joint" (Luttgens & Hamilton); CDC Normal Joint
  Range of Motion Study; Eaton Hand "Typical Range of Motion"; Physiotutors wrist/hand AROM;
  PMC finger flexion review (PMC4372184); ACE trunk flexibility assessment form; Radiopaedia
  "Movements of the spine"; Enlyte normal ROM summary.
- Range types and flexibility: Hinge Health "Range of Motion"; Minser Chiropractic "Range of
  Motion in Exercise"; Ehlers-Danlos Society "Assessing Joint Hypermobility" (Beighton score).
- Neck: Physiopedia "Cervical Spine Range of Motion" (AAOS norms).
- Shoulder rhythm: Physiopedia "Scapulohumeral Rhythm"; OUHSC kinesiology notes; Braman et al.
  (PMC2841046).
- Lumbopelvic rhythm: Takahashi & Yamaji (PMC7064356); Vazirian et al. reviews (CDC stacks);
  BMC Musculoskeletal Disorders movement criteria.
- Muscles: Teach Me Anatomy upper limb, lower limb and abdominal wall pages; OpenStax Anatomy
  & Physiology 11.6; Wikipedia "Abdominal muscles"; Osmosis anterolateral abdominal wall.
- Shoulders: Wikipedia "Shoulder joint"; StatPearls "Glenohumeral Joint"; Arthritis
  Foundation "Shoulder Anatomy"; University of Utah shoulder anatomy; Body Type Calculator "Average Shoulder Width"
  (ANSUR II, NHANES III); Healthline "Average Shoulder Width".
- Feet: Healthline "Average Shoe Size for Men".
- Hips and glutes: Goodwin Living, "Anatomy Lesson: The Hips and Glutes".
- Hands: LibreTexts / InformedHealth hand bones; Eaton Hand resting cascade; clinical resting
  posture (position of function); tenodesis effect (hand rehab notes); Cornell ergonomics
  "Grasping Hands" (power vs pinch grip); Wikipedia "Hand" (arches); Physiopedia "Functional
  Anatomy of the Hand" (thumb, finger spread, arches).
- Sizing: MFG Merch "Pants Size Chart" (men's and women's charts, how to measure, rise and fit);
  Creative Muse "Sizing & Fit" (garment vs body ease, flat-lay, grading, fabric behavior);
  National Breast Cancer Foundation "Bra Fit Guide"; Saucony men's size chart; Men's Wearhouse "Complete Guide to Men's Suit Sizing and Fit"; Selvane "Sleeve Length Guide"; MasterClass "How to Properly Measure Sleeve Length"; Transfer Express "Design Sizes" (print zones); Holy Clothing women's sleeve length guide; Pillar Athletics "Joggers vs Sweatpants"; No Fugazi "How to Measure Joggers for Manufacturing"; Steady Clothing "Vintage Sizing Guide"; Naiz Fit "Oversized Fit Guide"; Lane Bryant / Cacique "Bra Fit Guide".
- Proportions: Penn State OpenLab "Proportionality Constants" (Drillis & Contini 1966).
- Skinning: Kavan et al. (dual quaternion skinning); Walt Disney Animation Studios, "Enhanced
  Dual Quaternion Skinning for Production Use"; Disney Research, "Skinning with Optimized
  Centers of Rotation"; Autodesk Maya documentation on smooth skinning methods.
- Physics: Stickman Physics, "Physics of Video Games"; Cal State "Postural Stability in Motor
  Control"; Wikipedia "Balance (ability)"; contrapposto (Wikipedia, Art in Context, Robert
  Oosti); Müller et al., "Position Based Dynamics" (2006); Wikipedia "Soft-body dynamics";
  Real World Physics Problems, "Physics of Gymnastics"; GameDesigning.org, "Game Physics"; Join the Movement Movement, "The Physics of Proper Running"; UW-Madison Physics, "Physics of Running"; Glenn Fiedler, "Fix Your Timestep!"; Godot physics interpolation docs.
- Idles: TV Tropes, "Idle Animation"; Antidote, "How Idle Animations Secretly Give Video Game
  Characters Life"; GarageFarm idle animation tips; Urna "Idle animation in Blender"; IMVU Creator
  "Idle animations".
- Reference only, not used for assets: Innerbody Anatomy Explorer; Anatomy 3D Atlas.
