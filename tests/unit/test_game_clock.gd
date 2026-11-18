extends GutTest
## GameClock is an autoload script; tests use a fresh instance, not the global.

const GameClockScript := preload("res://src/autoload/game_clock.gd")

var clock: Node


func before_each() -> void:
	clock = autofree(GameClockScript.new())


func test_starts_day_one_at_eight() -> void:
	assert_eq(clock.day(), 1)
	assert_eq(clock.hour(), 8)
	assert_eq(clock.minute(), 0)
	assert_eq(clock.format_time(), "Day 1 · 08:00")


func test_advance_moves_time() -> void:
	clock.advance(95)
	assert_eq(clock.hour(), 9)
	assert_eq(clock.minute(), 35)


func test_advance_ignores_non_positive() -> void:
	clock.advance(0)
	clock.advance(-30)
	assert_eq(clock.total_minutes, GameClockScript.START_MINUTES)


func test_crossing_midnight_changes_day() -> void:
	clock.advance(16 * 60 + 5)  # 08:00 -> 00:05 next day
	assert_eq(clock.day(), 2)
	assert_eq(clock.hour(), 0)


func test_hour_signal_fires_once_per_hour_crossed() -> void:
	watch_signals(clock)
	clock.advance(8 * 60)  # long sleep
	assert_signal_emit_count(clock, "hour_passed", 8)


func test_day_signal_reports_new_day() -> void:
	watch_signals(clock)
	clock.advance(24 * 60)
	assert_signal_emitted_with_parameters(clock, "day_passed", [2])


func test_small_advance_emits_time_but_not_minute() -> void:
	watch_signals(clock)
	clock.advance(0.25)
	assert_signal_emitted(clock, "time_advanced")
	assert_signal_not_emitted(clock, "minute_changed")


func test_process_respects_pause() -> void:
	clock.paused = true
	clock._process(10.0)
	assert_eq(clock.total_minutes, GameClockScript.START_MINUTES)
	clock.paused = false
	clock.minutes_per_second = 2.0
	clock._process(10.0)
	assert_almost_eq(clock.total_minutes, GameClockScript.START_MINUTES + 20.0, 0.001)


func test_night_hours() -> void:
	assert_false(clock.is_night())
	clock.advance(15 * 60)  # 23:00
	assert_true(clock.is_night())


func test_save_round_trip() -> void:
	clock.advance(1234)
	var other: Node = autofree(GameClockScript.new())
	other.from_dict(clock.to_dict())
	assert_eq(other.total_minutes, clock.total_minutes)


func test_format_duration() -> void:
	assert_eq(GameClockScript.format_duration(0.2), "under 1 min")
	assert_eq(GameClockScript.format_duration(23.4), "23 min")
	assert_eq(GameClockScript.format_duration(60.0), "1 h")
	assert_eq(GameClockScript.format_duration(80.0), "1 h 20")
	assert_eq(GameClockScript.format_duration(24 * 60.0), "1 d")
	assert_eq(GameClockScript.format_duration(52 * 60.0), "2 d 4 h")
	assert_eq(GameClockScript.format_duration(INF), "—")
