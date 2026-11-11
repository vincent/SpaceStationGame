extends GutTest


func test_warmth_day_night() -> void:
	assert_eq(DayCycle.warmth(12.0), 0.0, "noon is cool work light")
	assert_eq(DayCycle.warmth(23.0), 1.0, "night is warm")
	assert_eq(DayCycle.warmth(3.0), 1.0)
	assert_between(DayCycle.warmth(7.0), 0.01, 0.99, "dawn ramps")
	assert_between(DayCycle.warmth(21.0), 0.01, 0.99, "dusk ramps")
	assert_lt(DayCycle.light_scale(23.0), DayCycle.light_scale(12.0), "night dims the rooms")


func test_routine_choice() -> void:
	assert_eq(PlayerRoutine.choose(23.0, 80, 60, 80, true), &"sleep", "night and a bit tired")
	assert_eq(PlayerRoutine.choose(14.0, 80, 20, 80, true), &"sleep", "exhausted")
	assert_eq(PlayerRoutine.choose(12.5, 60, 90, 80, true), &"eat", "lunch time")
	assert_eq(PlayerRoutine.choose(16.0, 60, 90, 80, true), &"work", "not meal time")
	assert_eq(PlayerRoutine.choose(16.0, 20, 90, 80, true), &"eat", "starving")
	assert_eq(PlayerRoutine.choose(16.0, 20, 90, 80, false), &"work", "nothing to cook")
	assert_eq(PlayerRoutine.choose(16.0, 90, 90, 30, true), &"stargaze", "low morale")


func test_sfx_synth() -> void:
	var wav := SfxSynth.tone(440, 440, 0.5)
	assert_eq(wav.data.size(), int(0.5 * SfxSynth.MIX_RATE) * 2, "16-bit mono")
	assert_eq(SfxSynth.room_tone(2.0).loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(AudioDirector.build_sounds().size(), 7)


func test_exploded_origin() -> void:
	var p := ExplodedView.exploded_origin(Vector3(2, 3, 0), Vector3.UP, Vector3.ZERO, 3.0)
	assert_almost_eq(p, Vector3(2, 6, 0), Vector3.ONE * 0.001)
	var away := ExplodedView.exploded_origin(Vector3(4, 0, 0), Vector3.ZERO, Vector3.ZERO, 2.0)
	assert_gt(away.x, 4.0, "default: away from the centre")
	assert_gt(away.y, 0.0, "and a bit up")
