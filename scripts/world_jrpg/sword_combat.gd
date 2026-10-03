extends RefCounted
## Hand equipment and authored full-body clips for the Tripo rigs (Rigify or Mixamo names).
## The imported character and equipment resources are never modified.
const SWORD = preload("res://assets/weapons/onehand_sword/001/model.glb")
const SHIELD = preload("res://assets/weapons/shield/001/model.glb")
const STAFF = preload("res://assets/weapons/staff/001/model.glb")
const GREATSWORD = preload("res://assets/weapons/gread_sword/001/model.glb")
const GREATAXE = preload("res://assets/weapons/gread_sword/002/model.glb")
const DAGGER = preload("res://assets/weapons/short_sword/001/model.glb")
const BOW = preload("res://assets/weapons/bow/001/bow.glb")
const ARROW = preload("res://assets/weapons/allow/001/model.glb")
const KATANA = preload("res://assets/weapons/katana/001/model.glb")
const KATANA_SHEATHED = preload("res://assets/weapons/katana/001/saya.model.glb")
const KATANA_SCABBARD = preload("res://assets/weapons/katana/001/scabbard.glb")
const SlashPlayer = preload("res://scripts/world_jrpg/sword_slash_player.gd")
const BowShotFx = preload("res://scripts/world_jrpg/bow_shot_fx.gd")
const TwoHandGrip = preload("res://scripts/world_jrpg/greatsword_grip.gd")
const CHARACTER_TOON = preload("res://assets/characters/_shared/materials/character_toon.gdshader")
const SLASH := "sword/slash"
const OVERHEAD := "sword/overhead"
const GUARD := "sword/guard"
const GS_SWEEP := "greatsword/sweep"
const GS_SMASH := "greatsword/smash"
const GS_GUARD := "greatsword/guard"
const DG_SLASH := "dagger/slash"
const DG_SLASH_L := "dagger/slash_l"
const DG_OVERHEAD := "dagger/overhead"
const DG_GUARD := "dagger/guard"
const BW_SHOT := "bow/shot"
const BW_ARC := "bow/arc_shot"
const BW_GUARD := "bow/guard"
const KT_IAI := "katana/iai"
const KT_KESA := "katana/kesa"
const KT_GUARD := "katana/guard"
# Equipment per character; anyone not listed carries the one-handed sword and shield.
const LOADOUTS := {"charcter001": "greatsword", "charcter002": "dual_daggers", "charcter003": "staff", "charcter005": "greataxe",
	"charcter006": "bow", "character007": "katana"}
# The sword stands tip-down along +Y; its handle is just above the guard.
const GRIP := Vector3(0.0, 0.9, 0.0)
const SWORD_SCALE := 0.9
const STAFF_SCALE := 1.65
const STAFF_GRIP := Vector3(0, 0.22, 0)
const SHIELD_SCALE := 0.62 * 1.3 * 1.2 * 0.78
const SHIELD_GRIP := Vector3(0.0, 0.56, 0.0)
const SHIELD_WRIST_CLEARANCE := 0.08
# Idle shield face: out to the left side and turned a little forward, standing nearly upright.
const SHIELD_FACE := Vector3(1.0, 0.0, 0.55)
const READY_BLADE := Vector3(-0.55, 0.24, 1.0)
# Rig-neutral roles mapped to each supported skeleton's bone names.
const RIGS := [
	{"spine": "spine", "head": "head", "upper_arm.R": "upper_arm.R", "forearm.R": "forearm.R", "hand.R": "hand.R",
		"upper_arm.L": "upper_arm.L", "forearm.L": "forearm.L", "hand.L": "hand.L", "palm": 0.02},
	{"spine": "mixamorig_Spine", "head": "head", "upper_arm.R": "mixamorig_RightArm", "forearm.R": "mixamorig_RightForeArm",
		"hand.R": "mixamorig_RightHand", "upper_arm.L": "mixamorig_LeftArm", "forearm.L": "mixamorig_LeftForeArm",
		"hand.L": "mixamorig_LeftHand", "palm": 0.04},
]
# Optional lower body; without it the clips still play as upper-body swings.
const LEGS := [
	{"hips": "spine", "thigh.R": "thigh.R", "shin.R": "shin.R", "foot.R": "foot.R",
		"thigh.L": "thigh.L", "shin.L": "shin.L", "foot.L": "foot.L"},
	{"hips": "mixamorig_Hips", "thigh.R": "mixamorig_RightUpLeg", "shin.R": "mixamorig_RightLeg", "foot.R": "mixamorig_RightFoot",
		"thigh.L": "mixamorig_LeftUpLeg", "shin.L": "mixamorig_LeftLeg", "foot.L": "mixamorig_LeftFoot"},
]
# Character space: +Z forward, -X is the sword (right) side. Angles in degrees, offsets in leg lengths.
# yaw/pitch: torso twist and lean. hip_yaw/hip: pelvis turn and shift. step/back: right/left foot plant.
# arm/off: right/left upper-arm and forearm directions. blade: sword direction. Keys without blade are idle.
const SLASH_KEYS := [
	{"t": 0.0},
	{"t": 0.04, "yaw": -38.0, "pitch": -5.0, "hip_yaw": -22.0, "hip": Vector3(.02,-.12,-.04), "back": Vector3(0,0,-.06),
		"arm": [Vector3(-.85,.45,-.25), Vector3(-.4,.8,-.45)], "blade": Vector3(-.6,.7,-.7),
		"off": [Vector3(.35,-.35,.9), Vector3(.1,.1,1)]},
	{"t": 0.07, "yaw": -50.0, "pitch": -3.0, "hip_yaw": -28.0, "hip": Vector3(.03,-.16,-.05), "back": Vector3(0,0,-.08),
		"arm": [Vector3(-.8,.55,-.35), Vector3(-.3,.85,-.6)], "blade": Vector3(-.45,.75,-.85),
		"off": [Vector3(.3,-.3,1), Vector3(.05,.15,1)]},
	{"t": 0.10, "yaw": -18.0, "pitch": 5.0, "hip_yaw": -8.0, "hip": Vector3(-.02,-.2,.12), "step": Vector3(-.08,0,.32), "back": Vector3(0,0,-.16),
		"arm": [Vector3(-.75,.25,.6), Vector3(-.4,.25,1)], "blade": Vector3(-.8,.4,.6),
		"off": [Vector3(.6,-.4,.4), Vector3(.3,-.2,.7)]},
	{"t": 0.13, "yaw": 30.0, "pitch": 12.0, "hip_yaw": 12.0, "hip": Vector3(-.03,-.26,.24), "step": Vector3(-.1,0,.52), "back": Vector3(0,0,-.22),
		"arm": [Vector3(-.1,-.15,1), Vector3(.6,-.1,.8)], "blade": Vector3(.9,-.25,.5),
		"off": [Vector3(.9,-.35,-.3), Vector3(.5,-.4,-.6)]},
	{"t": 0.18, "yaw": 55.0, "pitch": 14.0, "hip_yaw": 20.0, "hip": Vector3(-.03,-.28,.26), "step": Vector3(-.1,0,.55), "back": Vector3(0,0,-.22),
		"arm": [Vector3(.35,-.3,.85), Vector3(1,-.25,.05)], "blade": Vector3(.75,-.5,-.45),
		"off": [Vector3(.8,-.45,-.45), Vector3(.35,-.6,-.7)]},
	{"t": 0.30, "yaw": 48.0, "pitch": 11.0, "hip_yaw": 18.0, "hip": Vector3(-.03,-.26,.25), "step": Vector3(-.1,0,.55), "back": Vector3(0,0,-.22),
		"arm": [Vector3(.2,-.5,.75), Vector3(.8,-.45,.2)], "blade": Vector3(.6,-.6,-.3),
		"off": [Vector3(.8,-.5,-.35), Vector3(.35,-.65,-.6)]},
	{"t": 0.42, "yaw": 22.0, "pitch": 5.0, "hip_yaw": 8.0, "hip": Vector3(-.02,-.12,.12), "step": Vector3(-.05,0,.27), "back": Vector3(0,0,-.11),
		"arm": [Vector3(-.25,-.6,.65), Vector3(.3,-.4,.8)], "blade": Vector3(.35,.05,1)},
	{"t": 0.60},
]
# The overhead cut is one-handed: the off hand lifts partway with the windup, then drops back to the side.
const OVERHEAD_OFF := [Vector3(.3,-.95,.05), Vector3(.2,-.85,.35)]
const OVERHEAD_KEYS := [
	{"t": 0.0},
	{"t": 0.03, "yaw": -12.0, "pitch": 8.0, "hip_yaw": -6.0, "hip": Vector3(0,-.14,-.02),
		"arm": [Vector3(-.5,-.3,.5), Vector3(-.1,-.2,.9)], "blade": Vector3(-.3,-.2,1), "off": OVERHEAD_OFF},
	{"t": 0.08, "yaw": -14.0, "pitch": -16.0, "hip_yaw": -8.0, "hip": Vector3(0,.02,-.04), "back": Vector3(0,0,-.04),
		"arm": [Vector3(-.3,.95,-.05), Vector3(.1,.8,-.55)], "blade": Vector3(0,.15,-1),
		"off": [Vector3(.5,.1,.3), Vector3(.25,.6,.45)]},
	{"t": 0.11, "yaw": -10.0, "pitch": -22.0, "hip_yaw": -6.0, "hip": Vector3(0,.05,-.02), "back": Vector3(0,.04,-.06), "step": Vector3(0,.06,.04),
		"arm": [Vector3(-.3,.95,-.15), Vector3(.12,.7,-.7)], "blade": Vector3(0,-.25,-1),
		"off": [Vector3(.5,.25,.2), Vector3(.2,.75,.35)]},
	{"t": 0.13, "yaw": -6.0, "pitch": -8.0, "hip_yaw": -3.0, "hip": Vector3(-.01,-.02,.06), "step": Vector3(-.02,.04,.18), "back": Vector3(0,0,-.08),
		"arm": [Vector3(-.3,.95,.2), Vector3(.12,.85,.3)], "blade": Vector3(0,.95,-.3),
		"off": [Vector3(.5,.05,.4), Vector3(.25,.4,.6)]},
	{"t": 0.15, "yaw": -2.0, "pitch": 4.0, "hip_yaw": 0.0, "hip": Vector3(-.02,-.08,.14), "step": Vector3(-.04,.02,.32), "back": Vector3(0,0,-.12),
		"arm": [Vector3(-.3,.55,.8), Vector3(.12,.45,1)], "blade": Vector3(0,1,.35),
		"off": [Vector3(.45,-.35,.45), Vector3(.25,-.15,.8)]},
	{"t": 0.18, "yaw": 6.0, "pitch": 24.0, "hip_yaw": 4.0, "hip": Vector3(-.03,-.26,.24), "step": Vector3(-.06,0,.46), "back": Vector3(0,0,-.2),
		"arm": [Vector3(-.25,-.35,1), Vector3(.1,-.45,1)], "blade": Vector3(0,-.9,.55),
		"off": [Vector3(.35,-.9,-.15), Vector3(.25,-.85,-.05)]},
	{"t": 0.31, "yaw": 8.0, "pitch": 22.0, "hip_yaw": 5.0, "hip": Vector3(-.03,-.25,.23), "step": Vector3(-.06,0,.46), "back": Vector3(0,0,-.2),
		"arm": [Vector3(-.25,-.4,1), Vector3(.1,-.5,1)], "blade": Vector3(.05,-.95,.5),
		"off": [Vector3(.35,-.9,-.15), Vector3(.25,-.85,-.05)]},
	{"t": 0.45, "yaw": 5.0, "pitch": 8.0, "hip_yaw": 3.0, "hip": Vector3(-.02,-.11,.11), "step": Vector3(-.03,0,.22), "back": Vector3(0,0,-.1),
		"arm": [Vector3(-.55,-.6,.3), Vector3(-.1,-.6,.55)], "blade": Vector3(.12,-.1,1), "off": OVERHEAD_OFF},
	{"t": 0.63},
]
# Guard: left side forward, knees bent, shield raised square in front of the chest, sword held back low.
const GUARD_KEYS := [
	{"t": 0.0},
	{"t": 0.12, "yaw": -22.0, "pitch": 8.0, "hip_yaw": -12.0, "hip": Vector3(0,-.1,-.02), "step": Vector3(0,0,-.1), "back": Vector3(0,0,.12),
		"arm": [Vector3(-.55,-.75,-.25), Vector3(-.35,-.3,.9)], "blade": Vector3(-.35,.45,1),
		"off": [Vector3(.45,-.6,.65), Vector3(-.6,.2,.8)], "shield": Vector3(.15,.05,1)},
]
# Impact moment (seconds) for each clip: the hit-stop lands here, and the slash profiles' full swing is lined up with it.
const FX := {SLASH: {"impact": 0.13}, OVERHEAD: {"impact": 0.18}}
# Slash effects per clip (one profile per blade), tuned in the inspector; see scripts/world_jrpg/sword_slash_profile.gd.
const SLASH_FX := {
	SLASH: [preload("res://assets/fx/sword_slash/sword_slash.tres")],
	OVERHEAD: [preload("res://assets/fx/sword_slash/sword_overhead.tres")],
}

# Greatsword, held in both hands. The source stands tip-down along +Y with the handle between the guard and pommel.
const GS_SCALE := 1.5
const GS_GRIP := Vector3(0.0, 0.825, 0.0) # Right hand, just below the guard.
const GS_HAND_SPACING := 0.065 # Left hand sits this far toward the pommel; hands keep this gap whatever the weapon scale.
# Two-handed axe, swung with the greatsword clips. The source stands head-up along +Y with the haft below,
# its bit spreading along X like the greatsword's edges, so it needs no flip.
const GA_SCALE := 2.1
# Right hand low on the haft; the left hand (GS_HAND_SPACING below) stays clear of the pommel.
const GA_GRIP := Vector3(0.0, 0.25, 0.0)
# Elbow bend directions for the two-handed arm IK (character space).
const GS_POLES := {"R": Vector3(-.7,-1,-.3), "L": Vector3(.7,-1,-.3)}
# Greatsword keys use the shared body keys, plus "grip": the right hand's handle point, offset from the
# shoulder midpoint in arm lengths (character space), and "blade": the sword direction. Both hands follow by IK,
# except in "one_hand" keys, where only the right hand holds the sword and the left arm hangs free.
# "elbow" overrides the right elbow's bend direction; "ready" keys take the ready stance.
# Ready stance: half-turned with the sword shoulder back, the right hand raised beside the head with the elbow out,
# and the blade laid on the shoulder, slanting inward behind the head. Clips start and end here.
# "off_bend": degrees the free left forearm swings forward at the elbow.
# Standing (idle) only, not over the walk cycle: "hip" drops into a half crouch, "hip_yaw" turns the pelvis and legs
# to the right with "feet_turn" pivoting the feet along, and "stance" sets each foot that far further out (leg lengths).
# "yaw" counter-turns the upper body, so its total turn (yaw + hip_yaw) is the same standing or walking.
const GS_READY := {"yaw": 5.0, "hip_yaw": -30.0, "feet_turn": -30.0, "stance": .08, "hip": Vector3(0,-.12,0),
	"grip": Vector3(-.8,.26,.26), "blade": Vector3(.55,.25,-.8), "elbow": Vector3(-1,-.3,.1), "off_bend": 30.0, "one_hand": true}
# Horizontal sweep: wind back to the right, swing across the front and follow through to the left.
const GS_SWEEP_KEYS := [
	{"t": 0.0, "ready": true},
	{"t": 0.18, "yaw": -42.0, "pitch": -4.0, "hip_yaw": -20.0, "hip": Vector3(.02,-.14,-.04), "back": Vector3(0,0,-.06),
		"grip": Vector3(-.4,-.5,.12), "blade": Vector3(-.75,.3,-.6)},
	{"t": 0.25, "yaw": -48.0, "pitch": -2.0, "hip_yaw": -24.0, "hip": Vector3(.03,-.17,-.05), "back": Vector3(0,0,-.08),
		"grip": Vector3(-.42,-.52,.08), "blade": Vector3(-.65,.25,-.72)},
	{"t": 0.30, "yaw": -12.0, "pitch": 6.0, "hip_yaw": -5.0, "hip": Vector3(-.02,-.2,.12), "step": Vector3(-.08,0,.3), "back": Vector3(0,0,-.16),
		"grip": Vector3(-.12,-.5,.6), "blade": Vector3(-.85,.05,.55)},
	{"t": 0.34, "yaw": 25.0, "pitch": 12.0, "hip_yaw": 12.0, "hip": Vector3(-.03,-.26,.22), "step": Vector3(-.1,0,.5), "back": Vector3(0,0,-.22),
		"grip": Vector3(.16,-.38,.48), "blade": Vector3(.45,-.05,.9)},
	{"t": 0.39, "yaw": 50.0, "pitch": 14.0, "hip_yaw": 20.0, "hip": Vector3(-.03,-.28,.24), "step": Vector3(-.1,0,.52), "back": Vector3(0,0,-.22),
		"grip": Vector3(.35,-.44,.08), "blade": Vector3(.85,-.1,-.5)},
	{"t": 0.54, "yaw": 45.0, "pitch": 11.0, "hip_yaw": 18.0, "hip": Vector3(-.03,-.26,.23), "step": Vector3(-.1,0,.52), "back": Vector3(0,0,-.22),
		"grip": Vector3(.32,-.49,.1), "blade": Vector3(.8,-.25,-.45)},
	# Let go with the left hand and bring the blade up in front and back onto the shoulder.
	{"t": 0.68, "pitch": 6.0, "hip": Vector3(-.01,-.1,.1), "step": Vector3(-.05,0,.24), "back": Vector3(0,0,-.1),
		"grip": Vector3(-.2,-.32,.45), "blade": Vector3(-.2,.8,.55), "one_hand": true},
	{"t": 0.80, "ready": true},
]
# Heavy downward cut: from the shoulder, heave the blade up beside the head and cock it far back behind the shoulders
# (the big head leaves no room overhead), then whip it over and drive it down with a lunge.
const GS_SMASH_KEYS := [
	{"t": 0.0, "ready": true},
	# Dip under the weight with the blade still shouldered; the left hand joins on the heave up.
	{"t": 0.10, "yaw": 0.0, "pitch": 6.0, "hip_yaw": -30.0, "feet_turn": GS_READY.feet_turn, "stance": GS_READY.stance, "hip": Vector3(0,-.16,-.02),
		"grip": Vector3(-.64,.18,.32), "blade": Vector3(.42,.3,-.86), "elbow": GS_READY.elbow, "off_bend": GS_READY.off_bend, "one_hand": true},
	{"t": 0.22, "yaw": -26.0, "pitch": -16.0, "hip_yaw": -13.0, "hip": Vector3(0,-.02,-.04), "back": Vector3(0,.02,-.05),
		"grip": Vector3(-.33,.12,.18), "blade": Vector3(-.3,.2,-.93)},
	{"t": 0.30, "yaw": -28.0, "pitch": -19.0, "hip_yaw": -14.0, "hip": Vector3(0,0,-.05), "back": Vector3(0,.04,-.07), "step": Vector3(0,.06,.04),
		"grip": Vector3(-.33,.16,.14), "blade": Vector3(-.25,-.25,-.93)},
	{"t": 0.35, "yaw": -8.0, "pitch": 2.0, "hip_yaw": -4.0, "hip": Vector3(-.02,-.1,.14), "step": Vector3(-.04,.02,.3), "back": Vector3(0,0,-.12),
		"grip": Vector3(-.1,-.05,.75), "blade": Vector3(-.1,.6,.8)},
	{"t": 0.39, "yaw": 4.0, "pitch": 24.0, "hip_yaw": 3.0, "hip": Vector3(-.03,-.28,.24), "step": Vector3(-.06,0,.48), "back": Vector3(0,0,-.22),
		"grip": Vector3(.01,-.43,.58), "blade": Vector3(-.05,-.6,.8)},
	{"t": 0.56, "yaw": 5.0, "pitch": 22.0, "hip_yaw": 4.0, "hip": Vector3(-.03,-.26,.23), "step": Vector3(-.06,0,.48), "back": Vector3(0,0,-.22),
		"grip": Vector3(.01,-.46,.56), "blade": Vector3(-.03,-.65,.76)},
	# Let go with the left hand and lift the blade up in front and back onto the shoulder.
	{"t": 0.72, "pitch": 6.0, "hip": Vector3(-.01,-.1,.1), "step": Vector3(-.03,0,.24), "back": Vector3(0,0,-.1),
		"grip": Vector3(-.2,-.32,.45), "blade": Vector3(-.2,.8,.55), "one_hand": true},
	{"t": 0.85, "ready": true},
]
# Guard: turn the left shoulder back, crouch and hold the blade across the front, tip up to the right.
const GS_GUARD_KEYS := [
	{"t": 0.0, "ready": true},
	{"t": 0.14, "yaw": 15.0, "pitch": 6.0, "hip_yaw": 8.0, "hip": Vector3(0,-.12,-.02), "step": Vector3(0,0,.06), "back": Vector3(0,0,-.1),
		"grip": Vector3(.21,-.24,.54), "blade": Vector3(-.6,.75,.2)},
]
const GS_FX := {GS_SWEEP: {"impact": 0.34}, GS_SMASH: {"impact": 0.39}}
const GS_SLASH_FX := {
	GS_SWEEP: [preload("res://assets/fx/sword_slash/greatsword_sweep.tres")],
	GS_SMASH: [preload("res://assets/fx/sword_slash/greatsword_smash.tres")],
}
# The axe reaches further along the same clips.
const GA_SLASH_FX := {
	GS_SWEEP: [preload("res://assets/fx/sword_slash/greataxe_sweep.tres")],
	GS_SMASH: [preload("res://assets/fx/sword_slash/greataxe_smash.tres")],
}
const GS_CLIPS := {GS_SWEEP: GS_SWEEP_KEYS, GS_SMASH: GS_SMASH_KEYS, GS_GUARD: GS_GUARD_KEYS}

# Dual daggers, one in each hand. The source stands tip-down along +Y like the one-handed sword.
const DG_SCALE := 0.63
const DG_GRIP := Vector3(0.0, 0.84, 0.0)
# Both blades land together in the double cut, each with its own arc (the hit-stop still lands once).
const DG_SLASH_FX := {
	DG_SLASH: [preload("res://assets/fx/sword_slash/dagger_slash.tres")],
	DG_SLASH_L: [preload("res://assets/fx/sword_slash/dagger_slash_l.tres")],
	DG_OVERHEAD: [preload("res://assets/fx/sword_slash/dagger_overhead_r.tres"), preload("res://assets/fx/sword_slash/dagger_overhead_l.tres")],
}
# Ready stance: the greatsword's, with the right hand carried a little lower and its tip pointing forward,
# and the left arm held as in the crossed guard, swung about 15 degrees lower at the shoulder
# ("off"/"blade_l" as in the dagger keys, replacing "off_bend").
const DG_READY := {"yaw": 5.0, "hip_yaw": -30.0, "feet_turn": -30.0, "stance": .08, "hip": Vector3(0,-.12,0),
	"grip": Vector3(-.8,0,.26), "blade": Vector3(0,.3,1), "elbow": Vector3(-1,-.3,.1), "one_hand": true,
	"off": [Vector3(.3,-.64,.66), Vector3(-.3,.47,.95)], "blade_l": Vector3(-.9,.65,.48)}
# The right-hand slash reuses SLASH_KEYS; the left-hand slash is its mirror image (see _mirror_keys).
# Double downward cut: both daggers raised behind the head together, then driven down in front at once.
# Keys give the right arm and blade; _both() mirrors them onto the left arm.
const DG_OVERHEAD_KEYS := [
	{"t": 0.0},
	{"t": 0.03, "pitch": 8.0, "hip": Vector3(0,-.14,-.02),
		"arm": [Vector3(-.6,-.3,.5), Vector3(-.25,-.2,.9)], "blade": Vector3(-.35,-.2,1)},
	{"t": 0.09, "pitch": -16.0, "hip": Vector3(0,.02,-.04), "back": Vector3(0,0,-.04),
		"arm": [Vector3(-.45,.9,-.05), Vector3(-.1,.8,-.55)], "blade": Vector3(-.15,.15,-1)},
	{"t": 0.13, "pitch": -22.0, "hip": Vector3(0,.05,-.02), "back": Vector3(0,.04,-.06), "step": Vector3(0,.06,.04),
		"arm": [Vector3(-.45,.9,-.15), Vector3(-.1,.7,-.7)], "blade": Vector3(-.1,-.25,-1)},
	{"t": 0.15, "pitch": -8.0, "hip": Vector3(-.01,-.02,.06), "step": Vector3(-.02,.04,.18), "back": Vector3(0,0,-.08),
		"arm": [Vector3(-.45,.9,.2), Vector3(-.1,.85,.3)], "blade": Vector3(-.1,.95,-.3)},
	{"t": 0.17, "pitch": 4.0, "hip": Vector3(-.02,-.08,.14), "step": Vector3(-.04,.02,.32), "back": Vector3(0,0,-.12),
		"arm": [Vector3(-.45,.55,.75), Vector3(-.1,.45,1)], "blade": Vector3(-.1,1,.35)},
	{"t": 0.20, "pitch": 24.0, "hip": Vector3(-.03,-.26,.24), "step": Vector3(-.06,0,.46), "back": Vector3(0,0,-.2),
		"arm": [Vector3(-.35,-.35,1), Vector3(-.05,-.45,1)], "blade": Vector3(-.1,-.9,.55)},
	{"t": 0.33, "pitch": 22.0, "hip": Vector3(-.03,-.25,.23), "step": Vector3(-.06,0,.46), "back": Vector3(0,0,-.2),
		"arm": [Vector3(-.35,-.4,1), Vector3(-.05,-.5,1)], "blade": Vector3(-.05,-.95,.5)},
	{"t": 0.47, "pitch": 8.0, "hip": Vector3(-.02,-.11,.11), "step": Vector3(-.03,0,.22), "back": Vector3(0,0,-.1),
		"arm": [Vector3(-.6,-.6,.3), Vector3(-.25,-.6,.55)], "blade": Vector3(-.2,-.1,1)},
	{"t": 0.65},
]
# Guard: crouch with both forearms raised in front of the chest, the daggers crossed in an X before the face.
# Not a mirror pair: the rig's left forearm is shorter, so the left blade leans further forward to meet the right one mid-blade.
const DG_GUARD_KEYS := [
	{"t": 0.0},
	{"t": 0.12, "pitch": 6.0, "hip": Vector3(0,-.12,-.02), "step": Vector3(0,0,.06), "back": Vector3(0,0,-.1),
		"arm": [Vector3(-.3,-.45,.85), Vector3(.3,.7,.85)], "blade": Vector3(.9,.75,.1),
		"off": [Vector3(.3,-.45,.8), Vector3(-.3,.7,.8)], "blade_l": Vector3(-.9,.75,.3)},
]

# Bow in the left hand, arrows drawn with the right. The bow source stands along +Y with its string side toward +X
# and no modelled string; the arrow source points its head along +Y with the nock at the origin.
const BOW_SCALE := 1.2
const BOW_GRIP := Vector3(-0.026, 0.5, 0.0)
# Bow-local string ends (inside the tip hooks) and the arrow rest just above the fist.
const BOW_STRING_TOP := Vector3(0.064, 0.94, 0.0)
const BOW_STRING_BOTTOM := Vector3(0.064, 0.04, 0.0)
const BOW_ARROW_REST := Vector3(-0.02, 0.54, 0.0)
const ARROW_SCALE := 0.75
# Bow keys use the shared body keys, plus "bow": the left palm on the grip, offset from the shoulder midpoint
# in arm lengths (character space), and "bow_up": the upper limb's direction. The string faces back along the arm.
# "draw": the right palm (the arrow's nock), in the same offsets, with "elbow" as its bend direction;
# "hold": the right hand on the upper limb, this many arm lengths above the grip; otherwise the right arm hangs.
# "look": how far the head turns back toward the front against the body's turn (default .7).
# Clips start and end in the ready stance ("ready" keys), held outside them by the grip modifier.
const BW_DRAW_ELBOW := Vector3(-.4, .35, -1)
# Ready stance: bow held low at the left side, upper limb forward, the body barely turned.
const BW_READY := {"yaw": 0.0, "hip_yaw": -10.0, "feet_turn": -10.0, "stance": .05, "hip": Vector3(0,-.05,0),
	"bow": Vector3(.55,-.8,.35), "bow_up": Vector3(-.1,.5,1)}
# Side-on stance for aiming: feet across the line of fire, the left shoulder toward the target (+Z).
const BW_AIM := {"yaw": -40.0, "hip_yaw": -45.0, "feet_turn": -60.0, "stance": .1, "hip": Vector3(0,-.08,0), "look": .95}
# Straight shot: raise the bow and nock, draw to the cheek, a short aim, loose, follow through, and lower the bow.
const BW_SHOT_KEYS := [
	{"t": 0.0, "ready": true},
	{"t": 0.10, "yaw": -30.0, "hip_yaw": -40.0, "feet_turn": -55.0, "stance": .1, "hip": Vector3(0,-.07,0), "look": .9,
		"bow": Vector3(.2,-.2,.8), "bow_up": Vector3(.25,1,.1), "draw": Vector3(.05,-.2,.45)},
	{"t": 0.24, "yaw": -40.0, "hip_yaw": -45.0, "feet_turn": -60.0, "stance": .1, "hip": Vector3(0,-.08,0), "look": .95,
		"bow": Vector3(-.1,.05,1.15), "bow_up": Vector3(.08,1,0), "draw": Vector3(-.25,.1,.05)},
	{"t": 0.34, "yaw": -40.0, "hip_yaw": -45.0, "feet_turn": -60.0, "stance": .1, "hip": Vector3(0,-.08,0), "look": .95,
		"bow": Vector3(-.1,.05,1.15), "bow_up": Vector3(.08,1,0), "draw": Vector3(-.27,.1,-.02)},
	# Loosed: the drawing hand springs back past the ear and the bow tips forward.
	{"t": 0.39, "yaw": -44.0, "pitch": -3.0, "hip_yaw": -45.0, "feet_turn": -60.0, "stance": .1, "hip": Vector3(0,-.08,0), "look": .95,
		"bow": Vector3(-.1,.03,1.18), "bow_up": Vector3(.08,1,.18), "draw": Vector3(-.35,.14,-.35)},
	{"t": 0.52, "yaw": -42.0, "pitch": -2.0, "hip_yaw": -45.0, "feet_turn": -60.0, "stance": .1, "hip": Vector3(0,-.08,0), "look": .95,
		"bow": Vector3(-.1,0,1.15), "bow_up": Vector3(.08,1,.15), "draw": Vector3(-.4,.08,-.4)},
	{"t": 0.75, "ready": true},
]
# Charged high shot: lean back and aim steeply up, hold the full draw while it charges, then loose into a long arc.
const BW_ARC_KEYS := [
	{"t": 0.0, "ready": true},
	{"t": 0.12, "yaw": -30.0, "hip_yaw": -40.0, "feet_turn": -55.0, "stance": .12, "hip": Vector3(0,-.1,0), "look": .9,
		"bow": Vector3(.2,-.1,.8), "bow_up": Vector3(.25,1,-.1), "draw": Vector3(.05,-.1,.45)},
	{"t": 0.32, "yaw": -40.0, "pitch": -14.0, "hip_yaw": -45.0, "feet_turn": -60.0, "stance": .12, "hip": Vector3(0,-.1,-.02), "look": .95,
		"bow": Vector3(-.1,.7,.95), "bow_up": Vector3(.08,.8,-.6), "draw": Vector3(-.25,.15,.05)},
	{"t": 0.55, "yaw": -40.0, "pitch": -16.0, "hip_yaw": -45.0, "feet_turn": -60.0, "stance": .12, "hip": Vector3(0,-.12,-.02), "look": .95,
		"bow": Vector3(-.1,.72,.95), "bow_up": Vector3(.08,.8,-.6), "draw": Vector3(-.27,.13,0)},
	{"t": 0.60, "yaw": -44.0, "pitch": -18.0, "hip_yaw": -45.0, "feet_turn": -60.0, "stance": .12, "hip": Vector3(0,-.12,-.02), "look": .95,
		"bow": Vector3(-.1,.75,.98), "bow_up": Vector3(.08,.8,-.45), "draw": Vector3(-.35,.2,-.35)},
	{"t": 0.75, "yaw": -42.0, "pitch": -12.0, "hip_yaw": -45.0, "feet_turn": -60.0, "stance": .12, "hip": Vector3(0,-.1,-.02), "look": .95,
		"bow": Vector3(-.1,.65,.98), "bow_up": Vector3(.08,.8,-.4), "draw": Vector3(-.4,.1,-.4)},
	{"t": 1.0, "ready": true},
]
# Guard: crouch and hold the bow across the front of the body, the right hand bracing the upper limb.
const BW_GUARD_KEYS := [
	{"t": 0.0, "ready": true},
	{"t": 0.12, "yaw": -10.0, "pitch": 6.0, "hip_yaw": -10.0, "hip": Vector3(0,-.12,-.02), "step": Vector3(0,0,.06), "back": Vector3(0,0,-.1),
		"bow": Vector3(.35,-.1,.75), "bow_up": Vector3(-1,.7,.1), "hold": .45},
]
# Arrow nocked from "nock" until loosed at "release" (seconds), then flying at "speed" (m/s) dropping by "gravity";
# "flash" sizes the release star, "trail" colours the arrow's wake.
const BW_FX := {
	BW_SHOT: {"nock": 0.10, "release": 0.35, "speed": 28.0, "gravity": 2.0, "flash": 0.45, "trail": Color(1, 1, 1, 0.8)},
	BW_ARC: {"nock": 0.12, "release": 0.56, "speed": 18.0, "gravity": 14.0, "flash": 0.9, "trail": Color(1, 0.86, 0.45, 0.9)},
}

# Katana, worn sheathed at the left hip and drawn only inside its clips. All three sources stand tip-down along +Y
# with the blade edges along Z; saya.model.glb (sheathed) and scabbard.glb (cut from it) sit KT_SHEATH_DROP lower.
const KT_SCALE := 1.235 # 0.95 * 1.3
const KT_GRIP := Vector3(0.0, 0.84, 0.0) # Right hand, just above the guard.
const KT_SHEATH_DROP := Vector3(0.0, 0.02, 0.0)
# The right hand on the hilt at the left hip. The sheathed katana is placed exactly where this key holds the drawn one,
# so the swap between the two models at the draw and the sheathing is invisible. "hilt" keys take this pose.
const KT_HILT := {"yaw": 14.0, "pitch": 8.0, "hip": Vector3(0,-.06,0), "grip": Vector3(.1,-.62,.4), "blade": Vector3(.5,-.3,-1),
	"elbow": Vector3(-1,-.2,.6), "one_hand": true}
# Keys use the greatsword keys' "grip"/"blade"; "one_hand" keys leave the left hand off the handle.
# Draw-cut: hand to the hilt, draw straight into a horizontal cut from left to right, hold, then sheathe.
const KT_IAI_KEYS := [
	{"t": 0.0, "one_hand": true},
	{"t": 0.14, "hilt": true},
	{"t": 0.24, "yaw": 22.0, "pitch": 10.0, "hip": Vector3(0,-.14,.06), "step": Vector3(-.04,0,.18), "back": Vector3(0,0,-.06),
		"grip": Vector3(0,-.55,.7), "blade": Vector3(.75,-.15,.65), "elbow": Vector3(-1,-.3,.3), "one_hand": true, "off_bend": 20.0},
	{"t": 0.30, "yaw": -18.0, "pitch": 12.0, "hip_yaw": -8.0, "hip": Vector3(-.02,-.24,.18), "step": Vector3(-.08,0,.46), "back": Vector3(0,0,-.18),
		"grip": Vector3(-.4,-.35,.6), "blade": Vector3(-.3,.05,1), "elbow": Vector3(-1,-.4,0), "one_hand": true, "off_bend": 20.0},
	{"t": 0.36, "yaw": -46.0, "pitch": 12.0, "hip_yaw": -18.0, "hip": Vector3(-.03,-.27,.22), "step": Vector3(-.1,0,.52), "back": Vector3(0,0,-.2),
		"grip": Vector3(-.85,-.25,.3), "blade": Vector3(-.95,.05,-.3), "elbow": Vector3(-.5,-1,0), "one_hand": true, "off_bend": 15.0},
	{"t": 0.56, "yaw": -42.0, "pitch": 10.0, "hip_yaw": -16.0, "hip": Vector3(-.03,-.25,.2), "step": Vector3(-.1,0,.52), "back": Vector3(0,0,-.2),
		"grip": Vector3(-.85,-.3,.3), "blade": Vector3(-.9,-.15,-.35), "elbow": Vector3(-.5,-1,0), "one_hand": true, "off_bend": 15.0},
	# Shake the blade off and bring the tip back to the scabbard mouth.
	{"t": 0.70, "yaw": 0.0, "pitch": 8.0, "hip": Vector3(0,-.12,.06), "step": Vector3(-.04,0,.2),
		"grip": Vector3(-.2,-.5,.6), "blade": Vector3(.45,-.35,.8), "elbow": Vector3(-1,-.3,.3), "one_hand": true},
	{"t": 0.84, "hilt": true},
	{"t": 1.02, "one_hand": true},
]
# Kesa cut: draw, take the blade up two-handed behind the right shoulder, cut diagonally down to the left, then sheathe.
const KT_KESA_KEYS := [
	{"t": 0.0, "one_hand": true},
	{"t": 0.14, "hilt": true},
	{"t": 0.30, "yaw": -24.0, "pitch": -14.0, "hip_yaw": -12.0, "hip": Vector3(0,-.04,-.04), "back": Vector3(0,.02,-.05),
		"grip": Vector3(-.36,.14,.2), "blade": Vector3(-.35,.3,-.88)},
	{"t": 0.40, "yaw": -28.0, "pitch": -18.0, "hip_yaw": -14.0, "hip": Vector3(0,-.02,-.05), "back": Vector3(0,.04,-.07), "step": Vector3(0,.05,.04),
		"grip": Vector3(-.38,.18,.15), "blade": Vector3(-.3,-.15,-.94)},
	{"t": 0.45, "yaw": -6.0, "pitch": 4.0, "hip_yaw": -3.0, "hip": Vector3(-.02,-.12,.14), "step": Vector3(-.04,.02,.3), "back": Vector3(0,0,-.12),
		"grip": Vector3(-.2,-.02,.75), "blade": Vector3(-.45,.6,.65)},
	{"t": 0.50, "yaw": 22.0, "pitch": 22.0, "hip_yaw": 10.0, "hip": Vector3(-.03,-.28,.24), "step": Vector3(-.06,0,.5), "back": Vector3(0,0,-.22),
		"grip": Vector3(.1,-.4,.45), "blade": Vector3(.6,-.55,.55)},
	{"t": 0.66, "yaw": 20.0, "pitch": 20.0, "hip_yaw": 9.0, "hip": Vector3(-.03,-.26,.23), "step": Vector3(-.06,0,.5), "back": Vector3(0,0,-.22),
		"grip": Vector3(.1,-.42,.43), "blade": Vector3(.62,-.6,.5)},
	{"t": 0.80, "yaw": 4.0, "pitch": 8.0, "hip": Vector3(0,-.12,.06), "step": Vector3(-.04,0,.2),
		"grip": Vector3(-.2,-.5,.6), "blade": Vector3(.45,-.35,.8), "elbow": Vector3(-1,-.3,.3), "one_hand": true},
	{"t": 0.94, "hilt": true},
	{"t": 1.12, "one_hand": true},
]
# Guard: draw into a two-handed middle stance, the tip at the opponent's throat; held until released.
const KT_GUARD_KEYS := [
	{"t": 0.0, "one_hand": true},
	{"t": 0.10, "hilt": true},
	{"t": 0.24, "yaw": -8.0, "pitch": 6.0, "hip_yaw": -6.0, "hip": Vector3(0,-.12,-.02), "step": Vector3(0,0,.12), "back": Vector3(0,0,-.1),
		"grip": Vector3(-.05,-.4,.62), "blade": Vector3(.05,.5,.86)},
]
const KT_FX := {KT_IAI: {"impact": 0.32}, KT_KESA: {"impact": 0.50}}
const KT_SLASH_FX := {
	KT_IAI: [preload("res://assets/fx/sword_slash/katana_iai.tres")],
	KT_KESA: [preload("res://assets/fx/sword_slash/katana_kesa.tres")],
}
const KT_CLIPS := {KT_IAI: KT_IAI_KEYS, KT_KESA: KT_KESA_KEYS, KT_GUARD: KT_GUARD_KEYS}
# Time span of each clip in which the blade is out of the scabbard (from the hilt key to the closing hilt key).
const KT_DRAWN := {KT_IAI: Vector2(0.14, 0.84), KT_KESA: Vector2(0.14, 0.94), KT_GUARD: Vector2(0.10, INF)}

var skeleton: Skeleton3D
var socket: BoneAttachment3D
var grip: Node3D
var rig: Dictionary
var legs: Dictionary
var leg_length := 1.0
var _idle: Dictionary = {}
var _idle_global: Dictionary = {}
var has_shield := false
var two_handed := false
# Clips for the equipped weapon; the guard clip is empty when the loadout cannot guard.
var slash_clip := SLASH
var overhead_clip := OVERHEAD
var guard_clip := ""
# Second one-handed slash for the other hand; attacks alternate between the two when set.
var alt_slash_clip := ""
var _alt_next := false
# Left-hand weapon grip for dual wielding.
var off_grip: Node3D
# Bow loadout: the bow model (authored frame) and the drawing hand's nock point.
var bow_model: Node3D
var nock: Node3D
# Skeleton-space shield orientation in the idle pose; the guard pose rotates the hand from it.
var _shield_rest := Basis.IDENTITY
# Right arm length to the palm; ready-stance and greatsword grip offsets are measured in it.
var arm_reach := 1.0
# Per hand: maps (fingers, blade) back to the hand bone's local axes for the two-handed grip.
var _hand_frame: Dictionary = {}
# Ready stance held outside the weapon's clips by the grip modifier; empty leaves those clips as animated.
var ready_stance: Dictionary = GS_READY
# Clips whose keys decide how firmly the left hand holds the handle.
var two_hand_clips: Dictionary = GS_CLIPS
# Katana: the sheathed model at the hip, and the drawn blade with the empty scabbard left behind.
var sheathed: Node3D
var drawn: Array[Node3D] = []
# One toon material per weapon texture, shared by every character carrying it.
static var _toon_materials: Dictionary = {}

func install(model: Node3D, player: AnimationPlayer) -> bool:
	if not model.get_meta("weapon_enabled", true):
		return false
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or player == null or not player.has_animation("idle"):
		return false
	rig = {}
	for candidate: Dictionary in RIGS:
		if candidate.keys().all(func(role: String) -> bool: return role == "palm" or skeleton.find_bone(candidate[role]) >= 0):
			rig = candidate
			break
	if rig.is_empty(): return false
	legs = {}
	for candidate: Dictionary in LEGS:
		if candidate.values().all(func(bone: String) -> bool: return skeleton.find_bone(bone) >= 0):
			legs = candidate
			break
	player.play("idle", 0)
	player.advance(0)
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		_idle[bone] = skeleton.get_bone_pose(index)
		_idle_global[bone] = skeleton.get_bone_global_pose(index)
	var upper: Transform3D = _idle_global[rig["upper_arm.R"]]
	var forearm: Transform3D = _idle_global[rig["forearm.R"]]
	var wrist: Transform3D = _idle_global[rig["hand.R"]]
	arm_reach = (forearm.origin - upper.origin).length() + (wrist.origin - forearm.origin).length() + rig["palm"]
	if not legs.is_empty():
		leg_length = maxf((_idle_global[legs.hips] as Transform3D).origin.y - (_idle_global[legs["foot.R"]] as Transform3D).origin.y, 0.01)
	var path := player.get_node(player.root_node).get_path_to(skeleton)
	var library := AnimationLibrary.new()
	match LOADOUTS.get(model.get("character_id"), "sword_shield"):
		"greatsword", "greataxe":
			var axe: bool = LOADOUTS.get(model.get("character_id")) == "greataxe"
			_attach_greatsword(axe)
			_add_slashes(model, player, GA_SLASH_FX if axe else GS_SLASH_FX, GS_FX)
			library.add_animation("sweep", _make_clip(path, "大剣・横薙ぎ", GS_SWEEP_KEYS))
			library.add_animation("smash", _make_clip(path, "大剣・振り下ろし", GS_SMASH_KEYS))
			library.add_animation("guard", _make_clip(path, "大剣・防御", GS_GUARD_KEYS))
			player.add_animation_library("greatsword", library)
			slash_clip = GS_SWEEP
			overhead_clip = GS_SMASH
			guard_clip = GS_GUARD
			# Keeps both hands on the handle during every clip and holds the ready stance outside the greatsword clips.
			var holder: SkeletonModifier3D = TwoHandGrip.new()
			holder.name = "GreatswordTwoHandGrip"
			holder.setup(self, player, "greatsword/")
			skeleton.add_child(holder)
			return true
		"dual_daggers":
			_attach_daggers()
			_add_slashes(model, player, DG_SLASH_FX, {DG_SLASH: FX[SLASH], DG_SLASH_L: FX[SLASH], DG_OVERHEAD: FX[OVERHEAD]})
			library.add_animation("slash", _make_clip(path, "短剣・右横薙ぎ", SLASH_KEYS))
			library.add_animation("slash_l", _make_clip(path, "短剣・左横薙ぎ", _mirror_keys(SLASH_KEYS)))
			library.add_animation("overhead", _make_clip(path, "短剣・二刀振り下ろし", _both(DG_OVERHEAD_KEYS)))
			library.add_animation("guard", _make_clip(path, "短剣・十字防御", DG_GUARD_KEYS))
			player.add_animation_library("dagger", library)
			slash_clip = DG_SLASH
			alt_slash_clip = DG_SLASH_L
			overhead_clip = DG_OVERHEAD
			guard_clip = DG_GUARD
			# Holds the greatsword-style ready stance outside the dagger clips.
			ready_stance = DG_READY
			var holder: SkeletonModifier3D = TwoHandGrip.new()
			holder.name = "DaggerReadyGrip"
			holder.setup(self, player, "dagger/")
			skeleton.add_child(holder)
			return true
		"bow":
			_attach_bow()
			var shot_fx := BowShotFx.new()
			shot_fx.name = "BowShotFx"
			shot_fx.setup(bow_model, nock, player, BW_FX, _make_arrow, BOW_STRING_TOP, BOW_STRING_BOTTOM, BOW_ARROW_REST)
			model.add_child(shot_fx)
			library.add_animation("shot", _make_clip(path, "弓・射撃", BW_SHOT_KEYS))
			library.add_animation("arc_shot", _make_clip(path, "弓・曲射", BW_ARC_KEYS))
			library.add_animation("guard", _make_clip(path, "弓・防御", BW_GUARD_KEYS))
			player.add_animation_library("bow", library)
			slash_clip = BW_SHOT
			overhead_clip = BW_ARC
			guard_clip = BW_GUARD
			# Holds the bow low at the side outside the bow clips.
			ready_stance = BW_READY
			var holder: SkeletonModifier3D = TwoHandGrip.new()
			holder.name = "BowReadyGrip"
			holder.setup(self, player, "bow/")
			skeleton.add_child(holder)
			return true
		"katana":
			_attach_katana()
			_add_slashes(model, player, KT_SLASH_FX, KT_FX)
			library.add_animation("iai", _make_clip(path, "刀・抜刀横薙ぎ", KT_IAI_KEYS))
			library.add_animation("kesa", _make_clip(path, "刀・袈裟斬り", KT_KESA_KEYS))
			library.add_animation("guard", _make_clip(path, "刀・中段構え", KT_GUARD_KEYS))
			player.add_animation_library("katana", library)
			slash_clip = KT_IAI
			overhead_clip = KT_KESA
			guard_clip = KT_GUARD
			# Sheathed outside its clips, so no ready stance; the modifier joins the left hand and swaps the models.
			ready_stance = {}
			two_hand_clips = KT_CLIPS
			var holder: SkeletonModifier3D = TwoHandGrip.new()
			holder.name = "KatanaGrip"
			holder.setup(self, player, "katana/")
			skeleton.add_child(holder)
			return true
		"staff":
			_attach_staff()
		_:
			_attach_sword()
			_attach_shield()
			has_shield = true
			guard_clip = GUARD
	_add_slashes(model, player, SLASH_FX, FX)
	library.add_animation("slash", _make_clip(path, "横薙ぎ", SLASH_KEYS))
	library.add_animation("overhead", _make_clip(path, "上段斬り", OVERHEAD_KEYS))
	if has_shield:
		library.add_animation("guard", _make_clip(path, "防御", GUARD_KEYS))
	player.add_animation_library("sword", library)
	return true

## Attack clips' slash effects, placed in skeleton space (the frame the clip keys use), with their hit-stops.
func _add_slashes(model: Node3D, player: AnimationPlayer, profiles: Dictionary, impacts: Dictionary) -> void:
	var fx := SlashPlayer.new()
	fx.name = "SwordSlashFx"
	fx.setup(player, skeleton, profiles, impacts)
	model.add_child(fx)

func _attach_sword() -> void:
	socket = BoneAttachment3D.new()
	socket.name = "SwordHandSocket"
	socket.bone_name = rig["hand.R"]
	skeleton.add_child(socket)
	grip = Node3D.new()
	grip.name = "SwordGrip"
	# The hand bone begins at the wrist; move the grip to the palm center along it.
	grip.position = Vector3(0, rig["palm"], 0)
	var hand: Transform3D = _idle_global[rig["hand.R"]]
	grip.basis = hand.basis.inverse() * Basis(Quaternion(Vector3.UP, READY_BLADE.normalized()))
	socket.add_child(grip)
	var sword := SWORD.instantiate() as Node3D
	_apply_character_toon(sword)
	sword.name = "EquippedSword"
	# Flip the tip-down source blade to +Y about X (keeps the guard along X) and put its handle at the origin.
	sword.basis = Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE * SWORD_SCALE)
	sword.position = -(sword.basis * GRIP)
	grip.add_child(sword)

## Next horizontal slash; alternates right and left hands when the loadout has two.
func next_slash_clip() -> String:
	if alt_slash_clip.is_empty(): return slash_clip
	_alt_next = not _alt_next
	return slash_clip if _alt_next else alt_slash_clip

func is_attack_clip(clip: String) -> bool:
	return not clip.is_empty() and clip in [slash_clip, alt_slash_clip, overhead_clip]

func _attach_daggers() -> void:
	for side in ["R", "L"]:
		var hand_socket := BoneAttachment3D.new()
		hand_socket.name = "DaggerHandSocket" + side
		hand_socket.bone_name = rig["hand." + side]
		skeleton.add_child(hand_socket)
		var hand_grip := Node3D.new()
		hand_grip.name = "DaggerGrip" + side
		hand_grip.position = Vector3(0, rig["palm"], 0)
		var hand: Transform3D = _idle_global[rig["hand." + side]]
		hand_grip.basis = hand.basis.inverse() * Basis(Quaternion(Vector3.UP, _ready_blade(side)))
		hand_socket.add_child(hand_grip)
		# Hand frame for the ready stance's hold: the blade exactly as gripped, fingers as close to the bone axis as allows.
		var local_blade := (hand.basis.orthonormalized().inverse() * _ready_blade(side)).normalized()
		var local_fingers := (Vector3.UP - local_blade * local_blade.dot(Vector3.UP)).normalized()
		_hand_frame[side] = Basis(local_fingers, local_blade, local_fingers.cross(local_blade)).inverse()
		var dagger := DAGGER.instantiate() as Node3D
		_apply_character_toon(dagger)
		dagger.name = "EquippedDagger" + side
		# Same flip as the one-handed sword: tip up along +Y, handle at the grip.
		dagger.basis = Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE * DG_SCALE)
		dagger.position = -(dagger.basis * DG_GRIP)
		hand_grip.add_child(dagger)
		if side == "R":
			socket = hand_socket
			grip = hand_grip
		else:
			off_grip = hand_grip

## Idle blade direction per hand; the left hand mirrors the right across the character's X axis.
func _ready_blade(side: String) -> Vector3:
	return (READY_BLADE * (Vector3(-1, 1, 1) if side == "L" else Vector3.ONE)).normalized()

## Mirror one-handed keys onto the other side: the left arm swings as the right did, and the body turns the other way.
func _mirror_keys(keys: Array) -> Array:
	var flip := Vector3(-1, 1, 1)
	var result: Array = []
	for key: Dictionary in keys:
		var mirrored := {"t": key.t}
		if key.has("blade"):
			var off: Array = key.get("off", [Vector3(.65,-.55,.25), Vector3(-.2,.3,.8)])
			mirrored["arm"] = [off[0] * flip, off[1] * flip]
			mirrored["off"] = [key.arm[0] * flip, key.arm[1] * flip]
			mirrored["blade_l"] = key.blade * flip
			mirrored["pitch"] = key.get("pitch", 0.0)
			mirrored["yaw"] = -key.get("yaw", 0.0)
			mirrored["hip_yaw"] = -key.get("hip_yaw", 0.0)
			mirrored["hip"] = key.get("hip", Vector3.ZERO) * flip
			# Feet swap too: the left foot lunges and the right one braces.
			mirrored["step"] = key.get("back", Vector3.ZERO) * flip
			mirrored["back"] = key.get("step", Vector3.ZERO) * flip
		result.append(mirrored)
	return result

## Same motion in both arms at once: the left arm and blade mirror the right.
func _both(keys: Array) -> Array:
	var flip := Vector3(-1, 1, 1)
	var result: Array = []
	for key: Dictionary in keys:
		var both := key.duplicate()
		if key.has("blade"):
			both["off"] = [key.arm[0] * flip, key.arm[1] * flip]
			both["blade_l"] = key.blade * flip
		result.append(both)
	return result

func _attach_staff() -> void:
	socket = BoneAttachment3D.new()
	socket.name = "StaffHandSocket"
	socket.bone_name = rig["hand.R"]
	skeleton.add_child(socket)
	grip = Node3D.new()
	grip.name = "StaffGrip"
	grip.position = Vector3(0, rig["palm"], 0)
	var hand: Transform3D = _idle_global[rig["hand.R"]]
	grip.basis = hand.basis.inverse()
	socket.add_child(grip)
	var staff := STAFF.instantiate() as Node3D
	_apply_character_toon(staff)
	staff.name = "EquippedStaff"
	staff.scale = Vector3.ONE * STAFF_SCALE
	staff.position = -STAFF_GRIP * STAFF_SCALE
	grip.add_child(staff)

func _attach_greatsword(axe := false) -> void:
	two_handed = true
	_set_thumb_frames()
	socket = BoneAttachment3D.new()
	socket.name = "GreatswordHandSocket"
	socket.bone_name = rig["hand.R"]
	skeleton.add_child(socket)
	grip = Node3D.new()
	grip.name = "GreatswordGrip"
	grip.position = Vector3(0, rig["palm"], 0)
	# Blade along the thumb axis, edges along the fingers.
	grip.basis = (_hand_frame["R"] as Basis).inverse()
	socket.add_child(grip)
	var sword := (GREATAXE if axe else GREATSWORD).instantiate() as Node3D
	_apply_character_toon(sword)
	sword.name = "EquippedGreataxe" if axe else "EquippedGreatsword"
	# Same flip as the one-handed sword: tip up along +Y, handle at the grip. The axe already stands head-up.
	sword.basis = (Basis.IDENTITY if axe else Basis(Vector3.RIGHT, PI)).scaled(Vector3.ONE * (GA_SCALE if axe else GS_SCALE))
	sword.position = -(sword.basis * (GA_GRIP if axe else GS_GRIP))
	grip.add_child(sword)

func _attach_katana() -> void:
	two_handed = true
	_set_thumb_frames()
	socket = BoneAttachment3D.new()
	socket.name = "KatanaHandSocket"
	socket.bone_name = rig["hand.R"]
	skeleton.add_child(socket)
	grip = Node3D.new()
	grip.name = "KatanaGrip"
	grip.position = Vector3(0, rig["palm"], 0)
	# Blade along the thumb axis, edges along the fingers.
	grip.basis = (_hand_frame["R"] as Basis).inverse()
	socket.add_child(grip)
	# Tip up along +Y with the edges turned from Z onto X (the fingers), handle at the grip.
	var blade_basis := (Basis(Vector3.RIGHT, PI) * Basis(Vector3.UP, PI / 2)).scaled(Vector3.ONE * KT_SCALE)
	var katana := _katana_part(KATANA, "EquippedKatana", blade_basis, KT_GRIP)
	grip.add_child(katana)
	# The sheath hangs from the pelvis where the hilt key holds the drawn katana.
	var hip_bone: String = legs.hips if not legs.is_empty() else rig["spine"]
	var hip_socket := BoneAttachment3D.new()
	hip_socket.name = "KatanaHipSocket"
	hip_socket.bone_name = hip_bone
	skeleton.add_child(hip_socket)
	var pose := _pose(KT_HILT)
	var hand := _global(pose, skeleton.find_bone(rig["hand.R"])) * grip.transform
	var sheath := Node3D.new()
	sheath.name = "KatanaSheath"
	sheath.transform = _global(pose, skeleton.find_bone(hip_bone)).affine_inverse() * hand
	hip_socket.add_child(sheath)
	sheathed = _katana_part(KATANA_SHEATHED, "SheathedKatana", blade_basis, KT_GRIP - KT_SHEATH_DROP)
	sheath.add_child(sheathed)
	var scabbard := _katana_part(KATANA_SCABBARD, "EmptyScabbard", blade_basis, KT_GRIP - KT_SHEATH_DROP)
	sheath.add_child(scabbard)
	drawn = [katana, scabbard]
	update_sheath("", 0.0)

func _katana_part(scene: PackedScene, part_name: String, part_basis: Basis, handle: Vector3) -> Node3D:
	var part := scene.instantiate() as Node3D
	_apply_character_toon(part)
	part.name = part_name
	part.basis = part_basis
	part.position = -(part_basis * handle)
	return part

## Katana in the scabbard except between the hilt keys of its clips; run each frame by the grip modifier.
func update_sheath(clip: String, time: float) -> void:
	if sheathed == null: return
	var window: Vector2 = KT_DRAWN.get(clip, Vector2(INF, INF))
	var out := time >= window.x and time < window.y
	sheathed.visible = not out
	for part in drawn:
		part.visible = out

## Each hand holds a handle across its palm: fingers perpendicular to the handle, thumb along it.
## The thumb side comes from the idle hand (mirrored for the left), so each rig keeps its natural roll.
func _set_thumb_frames() -> void:
	for side in ["R", "L"]:
		var hand: Basis = (_idle_global[rig["hand." + side]] as Transform3D).basis.orthonormalized()
		var thumb := READY_BLADE * (Vector3(-1, 1, 1) if side == "L" else Vector3.ONE)
		thumb = (thumb - hand.y * hand.y.dot(thumb)).normalized()
		var local_thumb := hand.inverse() * thumb
		_hand_frame[side] = Basis(Vector3.UP, local_thumb, Vector3.UP.cross(local_thumb)).inverse()

func _attach_bow() -> void:
	_set_thumb_frames()
	var bow_socket := BoneAttachment3D.new()
	bow_socket.name = "BowHandSocket"
	bow_socket.bone_name = rig["hand.L"]
	skeleton.add_child(bow_socket)
	grip = Node3D.new()
	grip.name = "BowGrip"
	grip.position = Vector3(0, rig["palm"], 0)
	# Upper limb along the thumb axis, fingers wrapped across the grip.
	grip.basis = (_hand_frame["L"] as Basis).inverse()
	bow_socket.add_child(grip)
	bow_model = BOW.instantiate() as Node3D
	_apply_character_toon(bow_model)
	bow_model.name = "EquippedBow"
	# Half-turned about the limbs so the string side faces back along the fingers, toward the archer.
	bow_model.basis = Basis(Vector3.UP, PI).scaled(Vector3.ONE * BOW_SCALE)
	bow_model.position = -(bow_model.basis * BOW_GRIP)
	grip.add_child(bow_model)
	socket = BoneAttachment3D.new()
	socket.name = "BowDrawSocket"
	socket.bone_name = rig["hand.R"]
	skeleton.add_child(socket)
	nock = Node3D.new()
	nock.name = "BowNock"
	nock.position = Vector3(0, rig["palm"], 0)
	socket.add_child(nock)

## A new arrow for the bow effect: nock at the pivot, head along +Y, at the character's scale before display scaling.
func _make_arrow() -> Node3D:
	var pivot := Node3D.new()
	var arrow := ARROW.instantiate() as Node3D
	_apply_character_toon(arrow)
	arrow.scale = Vector3.ONE * ARROW_SCALE
	pivot.add_child(arrow)
	return pivot

func _attach_shield() -> void:
	var shield_socket := BoneAttachment3D.new()
	shield_socket.name = "ShieldLeftWristSocket"
	shield_socket.bone_name = rig["hand.L"]
	skeleton.add_child(shield_socket)
	var shield_grip := Node3D.new()
	shield_grip.name = "ShieldGrip"
	var forearm: Transform3D = _idle_global[rig["forearm.L"]]
	var hand: Transform3D = _idle_global[rig["hand.L"]]
	# The hand bone starts at the wrist. Keep the shield mostly upright, leaning only slightly with the hanging forearm.
	var up := (Vector3.UP * 2.0 + (forearm.origin - hand.origin).normalized()).normalized()
	var face := (SHIELD_FACE - up * up.dot(SHIELD_FACE)).normalized()
	_shield_rest = Basis(up.cross(face), up, face)
	shield_grip.basis = hand.basis.inverse() * _shield_rest
	shield_socket.add_child(shield_grip)
	var shield := SHIELD.instantiate() as Node3D
	_apply_character_toon(shield)
	shield.name = "EquippedShield"
	shield.scale = Vector3.ONE * SHIELD_SCALE
	shield.position = Vector3(0, 0, SHIELD_WRIST_CLEARANCE) - SHIELD_GRIP * SHIELD_SCALE
	shield_grip.add_child(shield)

## Weapons use the characters' toon shading so they keep the same brightness at night instead of going black.
## Only instance-level overrides are set; the imported weapon resources are left untouched.
func _apply_character_toon(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null: continue
			if not _toon_materials.has(source.albedo_texture):
				var toon := ShaderMaterial.new()
				toon.shader = CHARACTER_TOON
				toon.set_shader_parameter("base_color_texture", source.albedo_texture)
				_toon_materials[source.albedo_texture] = toon
			mesh.set_surface_override_material(surface, _toon_materials[source.albedo_texture])

func _make_clip(path: NodePath, title: String, keys: Array) -> Animation:
	var animation := Animation.new()
	animation.resource_name = title
	animation.length = keys[-1].t
	animation.loop_mode = Animation.LOOP_NONE
	var tracks: Dictionary = {}
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation_track, NodePath(str(path) + ":" + bone))
		var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(position_track, NodePath(str(path) + ":" + bone))
		tracks[bone] = [rotation_track, position_track]
	for key: Dictionary in keys:
		var pose := _pose(key)
		for bone: String in tracks:
			var transform: Transform3D = pose[bone]
			animation.rotation_track_insert_key(tracks[bone][0], key.t, transform.basis.get_rotation_quaternion())
			animation.position_track_insert_key(tracks[bone][1], key.t, transform.origin)
	return animation

func _pose(key: Dictionary) -> Dictionary:
	# "ready" keys take the equipped loadout's ready stance (the greatsword's for the greatsword clips).
	if key.get("ready", false): key = ready_stance.merged(key)
	if key.get("hilt", false): key = KT_HILT.merged(key)
	var pose := _idle.duplicate()
	if not key.has("blade") and not key.has("blade_l") and not key.has("bow"): return pose
	var hip_yaw: float = key.get("hip_yaw", 0.0)
	if not legs.is_empty():
		# Drop and shift the pelvis (in leg lengths), then keep the feet planted with leg IK.
		var hips: Transform3D = _idle_global[legs.hips]
		hips.origin += (key.get("hip", Vector3.ZERO) as Vector3) * leg_length
		hips.basis = Basis(Vector3.UP, deg_to_rad(hip_yaw)) * hips.basis
		_set_global(pose, legs.hips, hips)
		var turn := deg_to_rad(key.get("feet_turn", 0.0))
		var feet := _stance_feet([(_idle_global[legs["foot.R"]] as Transform3D).origin, (_idle_global[legs["foot.L"]] as Transform3D).origin],
			(_idle_global[legs.hips] as Transform3D).origin, turn, key.get("stance", 0.0))
		for index in 2:
			var side: String = ["R", "L"][index]
			var step: Vector3 = key.get("step" if side == "R" else "back", Vector3.ZERO)
			_plant_leg(pose, side, feet[index] + step * leg_length, turn)
	else:
		hip_yaw = 0.0
	# Twist in character space so the result does not depend on each rig's local bone axes.
	var yaw: float = key.get("yaw", 0.0)
	var spine := _global(pose, skeleton.find_bone(rig["spine"]))
	spine.basis = Basis.from_euler(Vector3(deg_to_rad(key.get("pitch", 0.0)), deg_to_rad(yaw), 0)) * spine.basis
	_set_global(pose, rig["spine"], spine)
	# Counter-rotate the head so the eyes stay on the target while the body turns.
	var head := _global(pose, skeleton.find_bone(rig["head"]))
	head.basis = Basis(Vector3.UP, deg_to_rad(-(yaw + hip_yaw) * key.get("look", .7))) * head.basis
	_set_global(pose, rig["head"], head)
	if key.has("bow"):
		_bow_arms(pose, key)
		return pose
	if key.has("grip"):
		_grip_arms(pose, key.grip, key.blade, not key.get("one_hand", false), key.get("elbow", Vector3.ZERO))
		_bend_off_arm(pose, key.get("off_bend", 0.0))
		return pose
	_aim_arm(pose, "R", key.arm[0], key.arm[1])
	var off: Array = key.get("off", [Vector3(.65,-.55,.25), Vector3(-.2,.3,.8)])
	_aim_arm(pose, "L", off[0], off[1])
	if key.has("shield"):
		# Turn the off hand so the attached shield faces the given direction, upright.
		var shield_face: Vector3 = (key.shield as Vector3).normalized()
		var shield_up := (Vector3.UP - shield_face * shield_face.y).normalized()
		var off_hand := _global(pose, skeleton.find_bone(rig["hand.L"]))
		var idle_off_hand: Transform3D = _idle_global[rig["hand.L"]]
		off_hand.basis = Basis(shield_up.cross(shield_face), shield_up, shield_face) * _shield_rest.inverse() * idle_off_hand.basis
		_set_global(pose, rig["hand.L"], off_hand)
	# Turn each hand so its weapon points along the keyed blade direction.
	for spec in [["R", "blade"], ["L", "blade_l"]]:
		if key.has(spec[1]):
			_aim_blade(pose, spec[0], key[spec[1]])
	return pose

## Turn one hand so its one-handed weapon points along the given character-space direction.
func _aim_blade(pose: Dictionary, side: String, blade: Vector3) -> void:
	var bone: String = rig["hand." + side]
	var hand := _global(pose, skeleton.find_bone(bone))
	var idle_hand: Transform3D = _idle_global[bone]
	hand.basis = Basis(Quaternion(_ready_blade(side), blade.normalized())) * idle_hand.basis
	_set_global(pose, bone, hand)

## Feet [R, L] set "stance" leg lengths further apart, then pivoted by turn (radians) about the pelvis.
func _stance_feet(feet: Array, pivot: Vector3, turn: float, stance: float) -> Array:
	var spin := Basis(Vector3.UP, turn)
	var result: Array = []
	for index in 2:
		var foot: Vector3 = feet[index] + Vector3(-stance if index == 0 else stance, 0, 0) * leg_length
		var offset := foot - pivot
		offset.y = 0.0
		result.append(foot - offset + spin * offset)
	return result

## Two-bone IK with the knee bending toward character forward, turned by turn (radians) along with the foot.
func _plant_leg(pose: Dictionary, side: String, target: Vector3, turn := 0.0) -> void:
	var names: Array = [legs["thigh." + side], legs["shin." + side], legs["foot." + side]]
	var rest: Array = names.map(func(bone: String) -> Transform3D: return _idle_global[bone])
	var thigh := _global(pose, skeleton.find_bone(names[0]))
	var a: float = (rest[1].origin - rest[0].origin).length()
	var b: float = (rest[2].origin - rest[1].origin).length()
	var reach := target - thigh.origin
	var d := clampf(reach.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var direction := reach.normalized()
	var forward := Basis(Vector3.UP, turn) * Vector3.BACK
	var pole := (forward - direction * direction.dot(forward)).normalized()
	var bend := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var knee := thigh.origin + (direction * bend + pole * sqrt(1.0 - bend * bend)) * a
	var foot := thigh.origin + direction * d
	for index in 2:
		var joint := _global(pose, skeleton.find_bone(names[index]))
		var from: Vector3 = (rest[index + 1].origin - rest[index].origin).normalized()
		var to := (knee - joint.origin) if index == 0 else (foot - joint.origin)
		joint.basis = Basis(Quaternion(from, to.normalized())) * rest[index].basis
		_set_global(pose, names[index], joint)
	# Feet stay flat on the ground regardless of how the legs bend.
	var planted := _global(pose, skeleton.find_bone(names[2]))
	planted.basis = Basis(Vector3.UP, turn) * rest[2].basis
	_set_global(pose, names[2], planted)

## A two-handed clip key with the ready stance or the katana hilt pose filled in when it is marked so.
static func gs_key(key: Dictionary) -> Dictionary:
	if key.get("hilt", false): return KT_HILT.merged(key)
	return GS_READY.merged(key) if key.get("ready", false) else key

## How firmly the left hand holds the handle at this point of a greatsword clip:
## 0 in "one_hand" keys, 1 in two-handed keys, blended linearly between them.
func two_hand_weight(clip: String, time: float) -> float:
	var keys: Array = (two_hand_clips.get(clip, []) as Array).map(gs_key)
	if keys.is_empty(): return 0.0
	var previous: Dictionary = keys[0]
	for key: Dictionary in keys:
		var weight := 0.0 if key.get("one_hand", false) else 1.0
		if key.t >= time:
			if key.t <= previous.t: return weight
			return lerpf(0.0 if previous.get("one_hand", false) else 1.0, weight, inverse_lerp(previous.t, key.t, time))
		previous = key
	return 0.0 if previous.get("one_hand", false) else 1.0

## Live weapon hold, run by the skeleton modifier after the animation each frame.
## ready_weight blends the torso turn and the right arm into the loadout's ready stance;
## crouch blends in the stance's half crouch; two_hand blends the left hand onto the handle.
func apply_grip(target: Skeleton3D, ready_weight: float, two_hand: float, crouch := 0.0) -> void:
	var pose: Dictionary = {}
	for index in target.get_bone_count():
		pose[target.get_bone_name(index)] = target.get_bone_pose(index)
	var right: Array = ["upper_arm.R", "forearm.R", "hand.R"].map(func(role: String) -> String: return rig[role])
	var left: Array = ["upper_arm.L", "forearm.L", "hand.L"].map(func(role: String) -> String: return rig[role])
	var torso: Array = [rig["spine"], rig["head"]]
	if crouch > 0.0 and not legs.is_empty():
		# Lower and turn the pelvis, and set the animated feet wider and turned along with it by leg IK.
		var hips := _global(pose, skeleton.find_bone(legs.hips))
		var turn := deg_to_rad(ready_stance.feet_turn) * crouch
		var feet := _stance_feet(["R", "L"].map(func(side: String) -> Vector3: return _global(pose, skeleton.find_bone(legs["foot." + side])).origin),
			hips.origin, turn, ready_stance.stance * crouch)
		hips.origin += (ready_stance.hip as Vector3) * leg_length * crouch
		hips.basis = Basis(Vector3.UP, deg_to_rad(ready_stance.hip_yaw) * crouch) * hips.basis
		_set_global(pose, legs.hips, hips)
		_plant_leg(pose, "R", feet[0], turn)
		_plant_leg(pose, "L", feet[1], turn)
		torso += [legs.hips, legs["thigh.R"], legs["shin.R"], legs["foot.R"], legs["thigh.L"], legs["shin.L"], legs["foot.L"]]
	if ready_weight > 0.0:
		# Half-turn the torso as _pose does, the head counter-turned to keep facing forward. Without the crouch the
		# pelvis stays square, so the spine takes the pelvis turn as well.
		var crouch_turn := deg_to_rad(ready_stance.hip_yaw) * (0.0 if legs.is_empty() else crouch)
		var yaw := deg_to_rad(ready_stance.yaw + ready_stance.hip_yaw) * ready_weight - crouch_turn
		for spec in [[rig["spine"], yaw], [rig["head"], -(yaw + crouch_turn) * .7]]:
			var bone := _global(pose, skeleton.find_bone(spec[0]))
			bone.basis = Basis(Vector3.UP, spec[1]) * bone.basis
			_set_global(pose, spec[0], bone)
		if ready_stance.has("bow"):
			# Hold the bow as keyed, blended from the animated left arm; the right arm keeps its own swing.
			var animated_left: Array = left.map(func(bone: String) -> Transform3D: return pose[bone])
			_bow_arms(pose, ready_stance)
			for index in left.size():
				pose[left[index]] = (animated_left[index] as Transform3D).interpolate_with(pose[left[index]], ready_weight)
			for bone: String in torso + left:
				target.set_bone_pose(target.find_bone(bone), pose[bone])
			return
		if ready_stance.has("off"):
			# Hold the left arm and its weapon as keyed, blended from the animated arm.
			var animated_left: Array = left.map(func(bone: String) -> Transform3D: return pose[bone])
			_aim_arm(pose, "L", ready_stance.off[0], ready_stance.off[1])
			_aim_blade(pose, "L", ready_stance.blade_l)
			for index in left.size():
				pose[left[index]] = (animated_left[index] as Transform3D).interpolate_with(pose[left[index]], ready_weight)
		else:
			_bend_off_arm(pose, ready_stance.off_bend * ready_weight)
		var animated: Array = right.map(func(bone: String) -> Transform3D: return pose[bone])
		_grip_arms(pose, ready_stance.grip, ready_stance.blade, false, ready_stance.elbow)
		for index in right.size():
			pose[right[index]] = (animated[index] as Transform3D).interpolate_with(pose[right[index]], ready_weight)
	if two_hand > 0.0:
		var animated: Array = left.map(func(bone: String) -> Transform3D: return pose[bone])
		var hand := _global(pose, skeleton.find_bone(rig["hand.R"]))
		var blade := (hand.basis * (_hand_frame["R"] as Basis).inverse().y).normalized()
		_hold(pose, "L", hand * Vector3(0, rig["palm"], 0) - blade * GS_HAND_SPACING, blade)
		for index in left.size():
			pose[left[index]] = (animated[index] as Transform3D).interpolate_with(pose[left[index]], two_hand)
	for bone: String in torso + right + left:
		target.set_bone_pose(target.find_bone(bone), pose[bone])

## Left hand on the bow grip; the right hand draws the string, braces the upper limb, or is left as it is.
func _bow_arms(pose: Dictionary, key: Dictionary) -> void:
	var shoulders := _shoulders(pose)
	var up: Vector3 = (key.bow_up as Vector3).normalized()
	var bow_point: Vector3 = shoulders + (key.bow as Vector3) * arm_reach
	_hold(pose, "L", bow_point, up)
	if key.has("draw"):
		var hand_point: Vector3 = shoulders + (key.draw as Vector3) * arm_reach
		var aim := (bow_point - hand_point).normalized()
		_reach(pose, "R", hand_point - aim * rig["palm"], key.get("elbow", BW_DRAW_ELBOW))
		# The hand carries on from the wrist toward the bow, fingers hooked on the string.
		var hand := _global(pose, skeleton.find_bone(rig["hand.R"]))
		hand.basis = Basis(Quaternion(hand.basis.y.normalized(), aim)) * hand.basis
		_set_global(pose, rig["hand.R"], hand)
	elif key.has("hold"):
		_hold(pose, "R", bow_point + up * (key.hold as float) * arm_reach, up)

func _shoulders(pose: Dictionary) -> Vector3:
	return (_global(pose, skeleton.find_bone(rig["upper_arm.R"])).origin + _global(pose, skeleton.find_bone(rig["upper_arm.L"])).origin) * 0.5

## Swing the left forearm forward at the elbow (about the character's side axis), keeping whatever the upper arm does.
func _bend_off_arm(pose: Dictionary, degrees: float) -> void:
	if is_zero_approx(degrees): return
	var forearm := _global(pose, skeleton.find_bone(rig["forearm.L"]))
	forearm.basis = Basis(Vector3.RIGHT, deg_to_rad(-degrees)) * forearm.basis
	_set_global(pose, rig["forearm.L"], forearm)

## The right hand at the grip point (offset from the shoulders in arm lengths); with both, the left hand just below it.
func _grip_arms(pose: Dictionary, offset: Vector3, blade: Vector3, both := true, elbow := Vector3.ZERO) -> void:
	var point := _shoulders(pose) + offset * arm_reach
	blade = blade.normalized()
	_hold(pose, "R", point, blade, elbow)
	if both:
		_hold(pose, "L", point - blade * GS_HAND_SPACING, blade)

## Put the palm center of one hand on a handle point, fingers wrapping across the blade axis.
func _hold(pose: Dictionary, side: String, point: Vector3, blade: Vector3, elbow := Vector3.ZERO) -> void:
	var shoulder := _global(pose, skeleton.find_bone(rig["upper_arm." + side])).origin
	# The fingers continue the arm's line toward the handle, turned square to the blade.
	var fingers := point - shoulder
	fingers = (fingers - blade * blade.dot(fingers)).normalized()
	var hand_basis := Basis(fingers, blade, fingers.cross(blade)) * (_hand_frame[side] as Basis)
	_reach(pose, side, point - fingers * rig["palm"], elbow)
	var hand := _global(pose, skeleton.find_bone(rig["hand." + side]))
	hand.basis = hand_basis
	_set_global(pose, rig["hand." + side], hand)

## Two-bone arm IK to a wrist position, the elbow bending toward the given direction or else the side's pole.
func _reach(pose: Dictionary, side: String, wrist: Vector3, bend_toward := Vector3.ZERO) -> void:
	var names: Array = [rig["upper_arm." + side], rig["forearm." + side], rig["hand." + side]]
	var rest: Array = names.map(func(bone: String) -> Transform3D: return _idle_global[bone])
	var upper := _global(pose, skeleton.find_bone(names[0]))
	var a: float = (rest[1].origin - rest[0].origin).length()
	var b: float = (rest[2].origin - rest[1].origin).length()
	var reach := wrist - upper.origin
	var d := clampf(reach.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var direction := reach.normalized()
	var hint: Vector3 = GS_POLES[side] if bend_toward == Vector3.ZERO else bend_toward
	var pole := (hint - direction * direction.dot(hint)).normalized()
	var bend := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow := upper.origin + (direction * bend + pole * sqrt(1.0 - bend * bend)) * a
	var joints := [elbow, upper.origin + direction * d]
	for index in 2:
		var joint := _global(pose, skeleton.find_bone(names[index]))
		var from: Vector3 = (rest[index + 1].origin - rest[index].origin).normalized()
		joint.basis = Basis(Quaternion(from, (joints[index] - joint.origin).normalized())) * rest[index].basis
		_set_global(pose, names[index], joint)

func _aim_arm(pose: Dictionary, side: String, upper: Vector3, fore: Vector3) -> void:
	for spec in [["upper_arm." + side, upper], ["forearm." + side, fore], ["hand." + side, fore]]:
		var bone: String = rig[spec[0]]
		var transform := _global(pose, skeleton.find_bone(bone))
		var reference: Transform3D = _idle_global[bone]
		transform.basis = Basis(Quaternion(reference.basis.y.normalized(), (spec[1] as Vector3).normalized())) * reference.basis
		_set_global(pose, bone, transform)

func _set_global(pose: Dictionary, bone: String, transform: Transform3D) -> void:
	var parent := skeleton.get_bone_parent(skeleton.find_bone(bone))
	pose[bone] = _global(pose, parent).affine_inverse() * transform

func _global(pose: Dictionary, index: int) -> Transform3D:
	if index < 0: return Transform3D.IDENTITY
	return _global(pose, skeleton.get_bone_parent(index)) * (pose[skeleton.get_bone_name(index)] as Transform3D)
