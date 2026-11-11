class_name AmbientKit
## Drop-in ambient props so the station is never still (it's an idle game:
## it is watched more than played). Module.refresh_ambient() calls
## populate() whenever its state changes:
##   derelict  -> sparks inside, drifting debris and dangling cables outside
##   repaired  -> steam vent + fan on the roof, blinking LEDs (when powered)
##   upgraded  -> + a maintenance drone circling the hull
## Everything animates through tweens or shaders: no per-frame scripts.

const FX_SHADER := preload("res://assets/shaders/ambient_fx.gdshader")
## Set true on low-end devices: CPU particles instead of GPU ones.
static var low_end := false


static func populate(module: Module, root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = module.greeble_seed * 7919 + module.state
	var aabb := module.hull_aabb
	var roof_y := Module.WALL_HEIGHT + HullMesher.ROOF_THICKNESS
	var floor_cells := _floor_positions(module)
	if module.state == StationState.State.DERELICT:
		for i in mini(2, floor_cells.size()):
			var p := floor_cells[rng.randi_range(0, floor_cells.size() - 1)]
			var s := sparks(p + Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)), rng)
			s.add_to_group(&"interior_prop")
			s.visible = module.interior_visible
			root.add_child(s)
		for i in 3:
			root.add_child(debris(aabb, rng))
		for i in 2:
			var x := rng.randf_range(aabb.position.x + 1.0, aabb.end.x - 1.0)
			var z := aabb.end.z - 1.0 if i == 0 else aabb.position.z + 1.0
			root.add_child(cable(Vector3(x, HullMesher.KEEL_BOTTOM - 0.05, z), rng))
		return
	var top := Vector3(aabb.get_center().x + rng.randf_range(-1.0, 1.0), roof_y, aabb.get_center().z)
	root.add_child(fan(top + Vector3(aabb.size.x * 0.2, 0.0, 0.0)))
	if module.powered:
		root.add_child(steam_vent(top + Vector3(-aabb.size.x * 0.2, 0.4, 0.0)))
	for slot: Slot in module.slots.values():
		root.add_child(leds(slot.position + slot.basis.z * -0.4 + Vector3(0, HullMesher.KEEL_BOTTOM - 0.02, 0), rng))
	if module.state == StationState.State.UPGRADED:
		root.add_child(drone(aabb, rng))


# --- Props -------------------------------------------------------------------

static func steam_vent(pos: Vector3) -> Node3D:
	var p := CPUParticles3D.new()
	p.name = "SteamVent"
	p.position = pos
	p.amount = 14
	p.lifetime = 2.2
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0.15, 0.05, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _ramp(0.4, 1.6)
	p.color_ramp = _fade(Color(0.85, 0.85, 1.0, 0.35))
	p.mesh = _particle_quad(0.5, true)
	return _maybe_gpu(p)


static func sparks(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Sparks"
	root.position = pos
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3(0, -1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -6, 0)
	p.color_ramp = _fade(Color(1.0, 0.85, 0.3, 1.0))
	p.mesh = _particle_quad(0.07, false)
	var node := _maybe_gpu(p)
	root.add_child(node)
	var timer := Timer.new()
	timer.wait_time = rng.randf_range(1.8, 4.0)
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		node.call(&"restart")
		EventBus.sfx.emit(&"spark"))
	root.add_child(timer)
	return root


static func debris(aabb: AABB, rng: RandomNumberGenerator) -> Node3D:
	var kit := MeshKit.new()
	kit.box(Vector3.ZERO, Vector3(rng.randf_range(0.3, 0.8), rng.randf_range(0.1, 0.3), rng.randf_range(0.2, 0.6)),
		Color(0.8, 0.0, 0.6))
	var mesh := MeshInstance3D.new()
	mesh.name = "Debris"
	mesh.mesh = kit.commit()
	mesh.material_override = ToonMaterials.get_material(Palette.STEEL.darkened(0.3))
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	mesh.position = Vector3(
		rng.randf_range(aabb.position.x, aabb.end.x),
		rng.randf_range(aabb.position.y, aabb.end.y + 2.0),
		aabb.get_center().z + side * (aabb.size.z * 0.5 + rng.randf_range(1.0, 3.0)))
	mesh.ready.connect(func() -> void:
		var t := mesh.create_tween().set_loops()
		var spin := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * TAU
		t.tween_property(mesh, "rotation", spin, rng.randf_range(14.0, 26.0)).as_relative()
		var b := mesh.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		b.tween_property(mesh, "position:y", 0.5, 3.0).as_relative()
		b.tween_property(mesh, "position:y", -0.5, 3.0).as_relative())
	return mesh


static func cable(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var kit := MeshKit.new()
	var length := rng.randf_range(0.8, 1.6)
	kit.box_between(Vector3(-0.03, -length, -0.03), Vector3(0.03, 0.0, 0.03), Color.WHITE)
	return _fx_mesh("Cable", kit, pos, 3, Palette.ANTHRACITE, rng.randf_range(0.8, 1.4))


static func fan(pos: Vector3) -> Node3D:
	var kit := MeshKit.new()
	kit.box(Vector3(0, 0.05, 0), Vector3(1.3, 0.05, 0.22), Color.WHITE)
	kit.box(Vector3(0, 0.05, 0), Vector3(0.22, 0.05, 1.3), Color.WHITE)
	return _fx_mesh("Fan", kit, pos + Vector3(0, 0.2, 0), 2, Palette.STEEL, 1.4)


static func leds(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var kit := MeshKit.new()
	for i in 4:
		kit.box(Vector3((i - 1.5) * 0.18, 0, 0), Vector3(0.08, 0.08, 0.08), Color(rng.randf(), 0, 0))
	var node := _fx_mesh("Leds", kit, pos, 0, Palette.NEON_PINK if rng.randf() < 0.4 else Palette.NEON_CYAN, 1.0)
	node.add_to_group(&"powered_fx")
	return node


static func drone(aabb: AABB, rng: RandomNumberGenerator) -> Node3D:
	var path := Path3D.new()
	path.name = "DronePath"
	var curve := Curve3D.new()
	var g := aabb.grow(1.6)
	var y := aabb.end.y + 0.8
	for p: Vector3 in [Vector3(g.position.x, y, g.position.z), Vector3(g.end.x, y + 0.6, g.position.z),
			Vector3(g.end.x, y, g.end.z), Vector3(g.position.x, y - 0.4, g.end.z),
			Vector3(g.position.x, y, g.position.z)]:
		curve.add_point(p)
	path.curve = curve
	var follow := PathFollow3D.new()
	follow.rotation_mode = PathFollow3D.ROTATION_Y
	path.add_child(follow)
	var kit := MeshKit.new()
	kit.box(Vector3.ZERO, Vector3(0.45, 0.25, 0.45), Color(0.2, 0, 0))
	kit.box(Vector3(0, 0, 0.26), Vector3(0.14, 0.1, 0.06), Color(0, 1, 0))
	var mesh := MeshInstance3D.new()
	mesh.mesh = kit.commit()
	mesh.material_override = ToonMaterials.get_material(Palette.YELLOW)
	follow.add_child(mesh)
	var eye := OmniLight3D.new()
	eye.light_color = Palette.NEON_CYAN
	eye.light_energy = 0.6
	eye.omni_range = 2.0
	follow.add_child(eye)
	var seconds := rng.randf_range(24.0, 34.0)
	path.ready.connect(func() -> void:
		var t := path.create_tween().set_loops()
		t.tween_property(follow, "progress_ratio", 1.0, seconds).from(0.0))
	return path


# --- Helpers -----------------------------------------------------------------

static func _fx_mesh(node_name: String, kit: MeshKit, pos: Vector3, mode: int, color: Color, speed: float) -> Node3D:
	var mat := ShaderMaterial.new()
	mat.shader = FX_SHADER
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("speed", speed)
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = kit.commit()
	mesh.material_override = mat
	mesh.position = pos
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## GPU particles unless on the Compatibility renderer or a low-end device.
static func _maybe_gpu(cpu: CPUParticles3D) -> Node3D:
	if low_end or RenderingServer.get_current_rendering_method() == "gl_compatibility" \
			or DisplayServer.get_name() == "headless":
		return cpu
	var gpu := GPUParticles3D.new()
	gpu.name = cpu.name
	gpu.position = cpu.position
	gpu.convert_from_particles(cpu)
	cpu.free()
	return gpu


static func _particle_quad(size: float, soft: bool) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if soft else BaseMaterial3D.TRANSPARENCY_DISABLED
	if soft:
		var puff := GradientTexture2D.new()
		puff.fill = GradientTexture2D.FILL_RADIAL
		puff.fill_from = Vector2(0.5, 0.5)
		puff.fill_to = Vector2(1.0, 0.5)
		puff.gradient = _fade(Color.WHITE)
		puff.width = 32
		puff.height = 32
		mat.albedo_texture = puff
	else:
		mat.emission_enabled = true
		mat.emission = Palette.YELLOW
		mat.emission_energy_multiplier = 3.0
	quad.material = mat
	return quad


static func _fade(color: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color, 0.0))
	return g


static func _ramp(from: float, to: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(from, to)
	c.add_point(Vector2(0, from))
	c.add_point(Vector2(1, to))
	return c


static func _floor_positions(module: Module) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var grid := module.interior.get_grid()
	for z in grid.size():
		for x in grid[z].length():
			if grid[z][x] == ".":
				out.append(module.interior.cell_to_world(Vector2i(x, z)))
	return out
