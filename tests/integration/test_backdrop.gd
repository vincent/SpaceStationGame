extends GutTest
## The space backdrop: starfield quad on the camera with a baked nebula.

const MAIN := preload("res://src/world/main.tscn")

var main: Node3D
var backdrop: Backdrop


func before_each() -> void:
	GameClock.paused = true
	GameState.new_game()
	GameState.set_story_enabled(false)
	main = MAIN.instantiate()
	main.skip_intro = true
	add_child_autofree(main)
	backdrop = main.find_children("*", "Backdrop", true, false)[0]
	await wait_process_frames(2)


func after_all() -> void:
	GameClock.paused = false
	GameState.new_game()


func test_nebula_is_baked_once_and_bound() -> void:
	var mat := backdrop.material_override as ShaderMaterial
	assert_not_null(mat)
	var tex := mat.get_shader_parameter(&"nebula_tex") as Texture2D
	assert_not_null(tex, "nebula texture bound to the starfield")
	assert_eq(tex, backdrop.get_nebula_texture())
	assert_eq(tex.get_size(), Vector2(Backdrop.NEBULA_SIZE, Backdrop.NEBULA_SIZE))
	var bake := backdrop.get_node("NebulaBake") as SubViewport
	assert_eq(bake.render_target_update_mode, SubViewport.UPDATE_ONCE, "baked once, not every frame")


func test_colors_come_from_palette() -> void:
	var mat := backdrop.material_override as ShaderMaterial
	assert_eq(mat.get_shader_parameter(&"top_color"), Palette.SPACE_TOP)
	assert_eq(mat.get_shader_parameter(&"bottom_color"), Palette.SPACE_BOTTOM)


func test_strength_setters_reach_the_shader() -> void:
	var mat := backdrop.material_override as ShaderMaterial
	backdrop.nebula_strength = 0.0
	backdrop.halo_strength = 1.5
	assert_eq(mat.get_shader_parameter(&"nebula_strength"), 0.0)
	assert_eq(mat.get_shader_parameter(&"halo_strength"), 1.5)


func test_parallax_follows_camera_pan() -> void:
	var mat := backdrop.material_override as ShaderMaterial
	var cam := backdrop.get_parent() as Camera3D
	await wait_process_frames(1)
	var before: Vector2 = mat.get_shader_parameter(&"parallax")
	cam.global_position += cam.global_basis.x * 5.0
	await wait_process_frames(1)
	var after: Vector2 = mat.get_shader_parameter(&"parallax")
	assert_gt(after.x - before.x, 1.0, "panning right shifts the stars")
