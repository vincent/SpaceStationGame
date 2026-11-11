class_name AudioDirector
extends Node
## Plays the placeholder audio layer: one-shot sounds requested through
## EventBus.sfx / reward moments, and a room tone whose volume follows how
## many modules are powered.

const POOL_SIZE := 6

var sounds: Dictionary[StringName, AudioStream] = {}

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _room: AudioStreamPlayer


func _ready() -> void:
	sounds = build_sounds()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_room = AudioStreamPlayer.new()
	_room.stream = SfxSynth.room_tone()
	_room.volume_db = -40.0
	add_child(_room)
	_room.play()
	EventBus.sfx.connect(play)
	EventBus.power_on_started.connect(func(_m: Module) -> void: play(&"power_on"))
	GameState.station.module_changed.connect(func(_uid: int, _r: StringName) -> void: _update_room_tone())
	GameState.station.reset.connect(_update_room_tone)
	_update_room_tone()


static func build_sounds() -> Dictionary[StringName, AudioStream]:
	var w := SfxSynth.Wave
	return {
		&"click": SfxSynth.tone(1400, 1100, 0.04, w.SQUARE, 0.12),
		&"power_on": SfxSynth.layered([[90, 360, w.SAW, 0.18], [180, 540, w.SINE, 0.25], [440, 660, w.SINE, 0.12]], 1.6,
			0.05, 0.6),
		&"snap": SfxSynth.layered([[160, 60, w.SINE, 0.6], [2000, 900, w.NOISE, 0.15]], 0.18, 0.002, 0.12),
		&"repair": SfxSynth.layered([[300, 900, w.SAW, 0.12], [3000, 3000, w.NOISE, 0.08]], 1.2, 0.05, 0.4),
		&"spark": SfxSynth.tone(4000, 4000, 0.07, w.NOISE, 0.1, 0.001, 0.05),
		&"explode": SfxSynth.tone(500, 160, 0.35, w.SINE, 0.25),
		&"clamp": SfxSynth.layered([[120, 80, w.SQUARE, 0.2], [1500, 1500, w.NOISE, 0.1]], 0.3, 0.002, 0.2),
	}


func play(sound: StringName) -> void:
	var stream: AudioStream = sounds.get(sound)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.play()


func _update_room_tone() -> void:
	var on := 0
	for uid in GameState.station.uids():
		if GameState.station.get_record(uid).powered:
			on += 1
	_room.volume_db = -40.0 if on == 0 else -22.0 + 2.0 * mini(on, 4)
