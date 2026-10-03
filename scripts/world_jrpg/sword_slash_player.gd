extends Node3D
## Plays each attack clip's slash effects in step with the clip, and the hit-stop at its impact.
## Effects start when the clip passes their profile's start_time and run on the clip's speed scale;
## they never read the weapon, and an interrupted attack fades them out.
const SLASH_SCENE = preload("res://scenes/fx/sword_slash.tscn")
const HIT_STOP := 0.06
# Fade-out of an interrupted attack's effects.
const CANCEL_FADE := 0.06

var player: AnimationPlayer
## Character space the arcs are placed in (the skeleton: +Z forward).
var frame: Node3D
## Clip → impact settings: {"impact": seconds, "hit_stop": bool (default true)}.
var impacts: Dictionary
## Clip → its slash effect nodes, one per profile.
var _slashes: Dictionary = {}
var _clip := ""
var _last_time := -1.0

func setup(animation_player: AnimationPlayer, character_frame: Node3D, clip_profiles: Dictionary, clip_impacts: Dictionary) -> void:
	player = animation_player
	frame = character_frame
	impacts = clip_impacts
	for clip: String in clip_profiles:
		var slashes: Array = []
		for profile: SwordSlashProfile in clip_profiles[clip]:
			var slash = SLASH_SCENE.instantiate()
			slash.name = "%s_%d" % [clip.replace("/", "_"), slashes.size()]
			slash.profile = profile
			add_child(slash)
			slashes.append(slash)
		_slashes[clip] = slashes

func _process(_delta: float) -> void:
	if player == null: return
	var clip: String = player.current_animation if player.is_playing() else ""
	var time: float = player.current_animation_position if not clip.is_empty() else -1.0
	if clip != _clip or time < _last_time:
		# Another clip, or this one restarted: anything still showing from an unfinished attack fades out.
		if _clip in _slashes and _last_time < _clip_length(_clip) - 0.05:
			for slash in _slashes[_clip]: slash.stop(CANCEL_FADE)
		_clip = clip
		_last_time = -1.0
	for slashes: Array in _slashes.values():
		for slash in slashes:
			# Follow the clip's speed (and hit-stop) while it plays; finish at normal speed after it ends.
			slash.time_scale = player.speed_scale if _clip in _slashes and slash in _slashes[_clip] else 1.0
	if clip.is_empty(): return
	if is_visible_in_tree():
		for slash in _slashes.get(clip, []):
			if _crossed(slash.profile.start_time, time): slash.play(frame)
		var impact: Dictionary = impacts.get(clip, {})
		if not impact.is_empty() and _crossed(impact.impact, time) and impact.get("hit_stop", true):
			_hit_stop()
	_last_time = time

func _crossed(mark: float, time: float) -> bool:
	return _last_time < mark and time >= mark

func _clip_length(clip: String) -> float:
	if not player.has_animation(clip): return 0.0
	return player.get_animation(clip).length

## Brief hit-stop sells the weight of the contact frame; the arcs freeze with the clip.
func _hit_stop() -> void:
	var clip := player.current_animation
	var speed := player.speed_scale
	player.speed_scale = speed * 0.05
	get_tree().create_timer(HIT_STOP, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(player) and player.current_animation == clip: player.speed_scale = speed)
