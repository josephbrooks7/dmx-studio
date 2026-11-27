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
| Neck + head | Nod down / look up | 45-60 / 60-75 |
|  | Tilt ear to shoulder | 45 |
|  | Turn left or right | 70-80 |
| Upper back (thoracic) | Bend forward / back | 30-40 / 20-30 (stiffest region: ribs) |
|  | Twist | ~35 |
|  | Side bend | 20-25 |
| Lower back (lumbar) | Bend forward / back | 40-60 / 25-35 |
|  | Twist | 10-15 (very little) |
|  | Side bend | 20 |

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

**Fixed physics time step.** All physics (hair, cloth, sway) steps at a fixed rate, e.g. 60 Hz,
independent of the display frame rate; rendering interpolates between the last two physics
states. This keeps motion identical at 30 fps (Light mode on the 2016 MacBook Pro) and 60 fps,
and identical in exported videos. Frame time is capped so a slow frame can't make the
simulation spiral.

**Collision.** Performers and props collide with the stage floor, mic stands and instruments so
hands rest on the mic and guitar instead of passing through them.

## 8. How this is used

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
- Shoulder rhythm: Physiopedia "Scapulohumeral Rhythm"; OUHSC kinesiology notes; Braman et al.
  (PMC2841046).
- Lumbopelvic rhythm: Takahashi & Yamaji (PMC7064356); Vazirian et al. reviews (CDC stacks);
  BMC Musculoskeletal Disorders movement criteria.
- Muscles: Teach Me Anatomy upper limb, lower limb and abdominal wall pages; OpenStax Anatomy
  & Physiology 11.6; Wikipedia "Abdominal muscles"; Osmosis anterolateral abdominal wall.
- Proportions: Penn State OpenLab "Proportionality Constants" (Drillis & Contini 1966).
- Skinning: Kavan et al. (dual quaternion skinning); Walt Disney Animation Studios, "Enhanced
  Dual Quaternion Skinning for Production Use"; Disney Research, "Skinning with Optimized
  Centers of Rotation"; Autodesk Maya documentation on smooth skinning methods.
- Physics: Stickman Physics, "Physics of Video Games"; Cal State "Postural Stability in Motor
  Control"; Wikipedia "Balance (ability)"; contrapposto (Wikipedia, Art in Context, Robert
  Oosti); Müller et al., "Position Based Dynamics" (2006); Wikipedia "Soft-body dynamics";
  Glenn Fiedler, "Fix Your Timestep!"; Godot physics interpolation docs.
- Reference only, not used for assets: Innerbody Anatomy Explorer; Anatomy 3D Atlas.
