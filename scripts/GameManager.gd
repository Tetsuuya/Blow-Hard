extends Node3D

# =================================================================
# Balloon Air Escape - Godot 4 Port
# Full conversion of the Three.js/Vite web game to GDScript
# All 3D objects are created procedurally, mirroring game.js logic
# =================================================================

# -------------------------------------------------------
# Game State
# -------------------------------------------------------
enum Mode { MENU, PLAYING, GAME_OVER }
var game_mode: Mode = Mode.MENU

var air_pressure: float = 100.0 # Active Fuel Level bar (0% to 100%)
var balloon_heat: float = 50.0  # Internal envelope heat (buoyancy)
var drain_rate: float = 2.5
var score: float = 0.0
var survival_time: float = 0.0
var pumps_collected: int = 0

var pos_x: float = 0.0
var pos_y: float = 0.5
var vel_x: float = 0.0
var vel_y: float = 0.0

# Keyboard/touch input state
var key_left: bool = false
var key_right: bool = false

# Spring simulation variables for squash and stretch animations
var spring_scale_y: float = 1.0
var spring_vel_y: float = 0.0
const SPRING_K: float = 14.0
const SPRING_D: float = 3.2

# -------------------------------------------------------
# 3D Scene Objects
# -------------------------------------------------------
var camera: Camera3D = null
var camera_shake_intensity: float = 0.0
var balloon_root: Node3D = null
var envelope_node: Node3D = null
var envelope_original_scale: Vector3 = Vector3.ONE
var base_balloon_scale: float = 1.0

var terrains: Array = []
var trees: Array = []
var houses: Array = []
var clouds: Array = []
var air_pumps: Array = []
var spikes: Array = []

# -------------------------------------------------------
# UI Nodes
# -------------------------------------------------------
var menu_screen: Control = null
var gameover_screen: Control = null
var game_hud: Control = null
var air_fill_bar: ProgressBar = null
var air_fill_style: StyleBoxFlat = null
var air_percent_label: Label = null
var score_label: Label = null
var time_label: Label = null
var pumps_label: Label = null
var gameover_reason_label: Label = null
var res_score_label: Label = null
var res_time_label: Label = null
var res_pumps_label: Label = null
var hit_flash: ColorRect = null
var popups_container: Control = null

# -------------------------------------------------------
# Timing
# -------------------------------------------------------
var elapsed: float = 0.0
var last_deform_pressure: float = -999.0

# FBX node reference for deferred auto-scaling
var _fbx_node: Node3D = null


# =================================================================
# _ready - Build the entire scene programmatically
# =================================================================
func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_camera()
	_setup_terrain()
	_setup_scenery()
	_setup_clouds()
	_setup_wind_particles()
	_setup_collectibles()
	_setup_balloon()
	_setup_ui()


# =================================================================
# Environment & Sky
# =================================================================
func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color      = Color(0.06, 0.09, 0.16)
	sky_mat.sky_horizon_color  = Color(0.22, 0.74, 0.97)
	sky_mat.ground_bottom_color   = Color(0.73, 0.90, 0.99)
	sky_mat.ground_horizon_color  = Color(0.22, 0.74, 0.97)
	sky_mat.sky_energy_multiplier = 1.2

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_enabled   = true
	env.fog_density   = 0.005
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(1.0, 0.94, 0.96)
	env.ambient_light_energy = 1.4
	env.tonemap_mode     = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	
	# Disable glow for a clean, natural look
	env.glow_enabled = false

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# =================================================================
# Lighting
# =================================================================
func _setup_lighting() -> void:
	# Main sun light
	var sun := DirectionalLight3D.new()
	sun.light_color   = Color(1.0, 0.93, 0.83)
	sun.light_energy  = 2.2
	sun.shadow_enabled = true
	sun.look_at_from_position(Vector3(15, 30, 20), Vector3.ZERO)
	add_child(sun)

	# Pink fill light
	var fill := DirectionalLight3D.new()
	fill.light_color  = Color(0.96, 0.44, 0.71)
	fill.light_energy = 1.0
	fill.look_at_from_position(Vector3(-10, 8, -8), Vector3.ZERO)
	add_child(fill)


# =================================================================
# Camera
# =================================================================
func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov  = 50.0
	camera.near = 0.1
	camera.far  = 1000.0
	camera.position = Vector3(0, 1.8, 7.5)
	add_child(camera)


# =================================================================
# Terrain (procedural hills, mirroring PlaneGeometry + vertex math)
# =================================================================
func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n); st.add_vertex(a)
	st.set_normal(n); st.add_vertex(b)
	st.set_normal(n); st.add_vertex(c)

func _create_terrain(offset_z: float) -> MeshInstance3D:
	const SX := 24; const SZ := 24
	const W  := 160.0; const D := 120.0

	var verts: Array[Vector3] = []
	for iz in range(SZ + 1):
		for ix in range(SX + 1):
			var x := (float(ix) / SX - 0.5) * W
			var z := (float(iz) / SZ - 0.5) * D
			var y := sin(x * 0.08) * cos(z * 0.06) * 3.5 + sin(z * 0.12) * 2.0 - 14.0
			verts.append(Vector3(x, y, z))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for iz in range(SZ):
		for ix in range(SX):
			var i0 := iz * (SX + 1) + ix
			_add_tri(st, verts[i0],     verts[i0+1],      verts[i0+SX+1])
			_add_tri(st, verts[i0+1],   verts[i0+SX+2],   verts[i0+SX+1])

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.086, 0.639, 0.290)
	mat.roughness    = 0.88
	st.set_material(mat)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position.z = offset_z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _setup_terrain() -> void:
	for offset in [0.0, -120.0]:
		var t := _create_terrain(offset)
		add_child(t)
		terrains.append(t)


# =================================================================
# Scenery - Trees & Houses (procedural meshes)
# =================================================================
func _reset_ground_item(item: Node3D, initial: bool) -> void:
	var sx := (1.0 if randf() > 0.5 else -1.0) * (4.0 + randf() * 25.0)
	var sz := (randf() - 0.5) * 120.0 if initial else -80.0 - randf() * 40.0
	item.position = Vector3(sx, -14.0, sz)
	item.scale    = Vector3.ONE * (0.7 + randf() * 0.5)

func _create_tree() -> Node3D:
	var g := Node3D.new()

	# Trunk
	var tm := CylinderMesh.new()
	tm.top_radius = 0.15; tm.bottom_radius = 0.22; tm.height = 1.0; tm.radial_segments = 6
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.47, 0.21, 0.06); tmat.roughness = 0.9
	tm.material = tmat
	var trunk := MeshInstance3D.new(); trunk.mesh = tm; trunk.position.y = 0.5
	g.add_child(trunk)

	# Foliage (cone)
	var lm := CylinderMesh.new()
	lm.top_radius = 0.0; lm.bottom_radius = 1.0; lm.height = 2.2; lm.radial_segments = 6
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.082, 0.502, 0.239); lmat.roughness = 0.8
	lm.material = lmat
	var leaf := MeshInstance3D.new(); leaf.mesh = lm; leaf.position.y = 2.0
	g.add_child(leaf)

	return g

func _create_house() -> Node3D:
	var g := Node3D.new()

	# Walls
	var wm := BoxMesh.new(); wm.size = Vector3(1.0, 0.8, 1.0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.996, 0.953, 0.780); wmat.roughness = 0.8
	wm.material = wmat
	var wall := MeshInstance3D.new(); wall.mesh = wm; wall.position.y = 0.4
	g.add_child(wall)

	# Roof (4-sided cone)
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0; rm.bottom_radius = 0.9; rm.height = 0.7; rm.radial_segments = 4
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.851, 0.467, 0.024); rmat.roughness = 0.7
	rm.material = rmat
	var roof := MeshInstance3D.new(); roof.mesh = rm; roof.position.y = 1.15; roof.rotate_y(PI / 4.0)
	g.add_child(roof)

	return g

func _setup_scenery() -> void:
	for i in 50:
		var t := _create_tree(); _reset_ground_item(t, true); add_child(t); trees.append(t)
	for i in 20:
		var h := _create_house(); _reset_ground_item(h, true); add_child(h); houses.append(h)


# =================================================================
# Clouds (groups of dodecahedron-like spheres)
# =================================================================
func _reset_cloud(cloud: Node3D, initial: bool) -> void:
	var sx := (1.0 if randf() > 0.5 else -1.0) * (10.0 + randf() * 20.0)
	var sz := (randf() - 0.5) * 70.0 if initial else -50.0 - randf() * 25.0
	cloud.position = Vector3(sx, 8.0 + randf() * 12.0, sz)
	cloud.scale    = Vector3.ONE * (1.0 + randf() * 1.6)

func _create_cloud() -> Node3D:
	var g := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.94, 0.96, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness    = 0.9

	for i in (6 + randi() % 4):
		var r  := 1.0 + randf() * 1.5
		var sm := SphereMesh.new()
		sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 8; sm.rings = 6
		sm.material = mat
		var puff := MeshInstance3D.new(); puff.mesh = sm
		puff.position = Vector3((randf()-0.5)*2.5, (randf()-0.5)*1.0, (randf()-0.5)*2.0)
		g.add_child(puff)
	return g

func _setup_clouds() -> void:
	for i in 30:
		var c := _create_cloud(); _reset_cloud(c, true); add_child(c); clouds.append(c)


# =================================================================
# Wind Particles (replaces THREE.Points wind streaks)
# =================================================================
func _setup_wind_particles() -> void:
	var wp := CPUParticles3D.new()
	wp.emitting            = true
	wp.amount              = 150
	wp.lifetime            = 8.0
	wp.emission_shape      = CPUParticles3D.EMISSION_SHAPE_BOX
	wp.emission_box_extents = Vector3(10, 5, 20)
	wp.direction           = Vector3(0, 0, 1)
	wp.spread              = 15.0
	wp.initial_velocity_min = 3.0
	wp.initial_velocity_max = 7.0
	wp.scale_amount_min    = 0.05
	wp.scale_amount_max    = 0.10
	wp.color               = Color(0.984, 0.812, 0.910, 0.55)
	wp.gravity             = Vector3.ZERO
	add_child(wp)


# =================================================================
# Collectibles - Air Pumps (green glowing canisters)
# =================================================================
func _create_pump() -> Node3D:
	var g := Node3D.new()

	# Body cylinder
	var bm := CylinderMesh.new()
	bm.top_radius = 0.25; bm.bottom_radius = 0.25; bm.height = 0.7; bm.radial_segments = 12
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color            = Color(0.063, 0.722, 0.506)
	bmat.metallic                = 0.2; bmat.roughness = 0.45
	bmat.emission_enabled        = false
	bm.material = bmat
	var body := MeshInstance3D.new(); body.mesh = bm
	g.add_child(body)

	# Cap
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15; cm.bottom_radius = 0.27; cm.height = 0.18; cm.radial_segments = 12
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1, 1, 1); cmat.metallic = 0.9
	cm.material = cmat
	var cap := MeshInstance3D.new(); cap.mesh = cm; cap.position.y = 0.4
	g.add_child(cap)

	return g

func _reset_pump(pump: Node3D) -> void:
	pump.position = Vector3((randf()-0.5)*10.0, randf()*3.8 - 0.5, -15.0 - randf()*20.0)


# =================================================================
# Hazards - Spikes (red sphere + 10 outward cones)
# =================================================================
func _create_spike() -> Node3D:
	var g := Node3D.new()

	# Core sphere
	var sm := SphereMesh.new(); sm.radius = 0.35; sm.height = 0.7
	var smat := StandardMaterial3D.new()
	smat.albedo_color            = Color(0.937, 0.267, 0.267)
	smat.metallic                = 0.1; smat.roughness = 0.8
	smat.emission_enabled        = false
	sm.material = smat
	var core := MeshInstance3D.new(); core.mesh = sm
	g.add_child(core)

	# Spike cones
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.118, 0.161, 0.239); cmat.metallic = 0.9; cmat.roughness = 0.1

	var dirs := [
		Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,-1,0),
		Vector3(0,0,1), Vector3(0,0,-1),
		Vector3(0.7,0.7,0).normalized(), Vector3(-0.7,0.7,0).normalized(),
		Vector3(0.7,-0.7,0).normalized(), Vector3(-0.7,-0.7,0).normalized()
	]

	for dir: Vector3 in dirs:
		var pm := CylinderMesh.new()
		pm.top_radius = 0.0; pm.bottom_radius = 0.09; pm.height = 0.45; pm.radial_segments = 6
		pm.material = cmat
		var spike := MeshInstance3D.new(); spike.mesh = pm
		spike.position = dir * 0.35
		# Rotate so the cone tip points outward from center
		if dir.dot(Vector3.UP) < -0.999:
			spike.rotate_z(PI)
		elif dir.dot(Vector3.UP) < 0.999:
			var axis := Vector3.UP.cross(dir)
			if axis.length_squared() > 0.0001:
				spike.rotate(axis.normalized(), Vector3.UP.angle_to(dir))
		g.add_child(spike)

	return g

func _reset_spike(spike: Node3D) -> void:
	spike.position = Vector3((randf()-0.5)*11.0, randf()*4.0 - 0.5, -20.0 - randf()*25.0)

func _setup_collectibles() -> void:
	for i in 4:
		var p := _create_pump(); _reset_pump(p); add_child(p); air_pumps.append(p)
	for i in 5:
		var s := _create_spike(); _reset_spike(s); add_child(s); spikes.append(s)


# =================================================================
# Balloon Setup (FBX model or procedural fallback)
# =================================================================

# Recursively gather world-space AABB.
# Uses global_transform * get_aabb() — the correct Godot 4 pattern.
# MUST be called after the node is in the scene tree.
func _world_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var has_result := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var local_aabb: AABB = mi.get_aabb()
			if local_aabb.size.length_squared() > 0.0:
				var world_aabb: AABB = mi.global_transform * local_aabb
				result = world_aabb
				has_result = true
	for child in node.get_children():
		if child is Node3D:
			var child_aabb := _world_aabb(child as Node3D)
			if child_aabb.size.length_squared() > 0.0:
				result = result.merge(child_aabb) if has_result else child_aabb
				has_result = true
	return result


func _setup_balloon() -> void:
	balloon_root = Node3D.new()
	balloon_root.position = Vector3(0, 0.5, 0)
	# Add to scene tree FIRST — scale is computed deferred after one frame
	add_child(balloon_root)

	var fbx_loaded := false
	if ResourceLoader.exists("res://assets/baloon.fbx"):
		var packed := load("res://assets/baloon.fbx") as PackedScene
		if packed:
			var fbx := packed.instantiate() as Node3D
			# Godot 4's ufbx importer already converts FBX → Y-up automatically.
			# Only flip 180° on Y so the balloon faces toward the camera.
			fbx.rotate_y(PI)
			balloon_root.add_child(fbx)
			_fbx_node = fbx
			fbx_loaded = true
			# Defer scale: wait one frame so scene tree computes correct transforms
			call_deferred("_auto_scale_fbx")

	if not fbx_loaded:
		_build_procedural_balloon()
		balloon_root.scale = Vector3.ONE * base_balloon_scale

# Called one frame after FBX is added — now get_transformed_aabb() works correctly
func _identify_envelope_mesh() -> void:
	if not _fbx_node or not is_instance_valid(_fbx_node): return
	var meshes := _fbx_node.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() == 0: return
	
	var largest_mesh: MeshInstance3D = null
	var max_volume: float = -1.0
	
	for m: MeshInstance3D in meshes:
		if m.mesh:
			var aabb := m.get_aabb()
			var volume := aabb.size.x * aabb.size.y * aabb.size.z
			if volume > max_volume:
				max_volume = volume
				largest_mesh = m
				
	if largest_mesh:
		envelope_node = largest_mesh
		envelope_original_scale = largest_mesh.scale
		print("BalloonGodot: Identified envelope mesh dynamically: ", largest_mesh.name, " with original scale: ", envelope_original_scale)

func _auto_scale_fbx() -> void:
	if not _fbx_node or not is_instance_valid(_fbx_node):
		base_balloon_scale = 1.0
		return

	_identify_envelope_mesh()

	var world_aabb := _world_aabb(_fbx_node)
	var max_dim := maxf(world_aabb.size.x, maxf(world_aabb.size.y, world_aabb.size.z))

	if max_dim > 0.01:
		base_balloon_scale = 2.6 / max_dim
		# Center the FBX within balloon_root local space
		var world_center := world_aabb.get_center()
		var local_center := balloon_root.to_local(world_center)
		_fbx_node.position = -local_center
	else:
		# Fallback: could not measure — use safe default
		base_balloon_scale = 0.015
		push_warning("BalloonGodot: FBX AABB measurement failed, using fallback scale.")

	balloon_root.scale = Vector3.ONE * base_balloon_scale

func _build_procedural_balloon() -> void:
	# Envelope (elongated sphere)
	var em := SphereMesh.new()
	em.radius = 0.9; em.height = 1.5; em.radial_segments = 16; em.rings = 12
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.96, 0.27, 0.27); emat.roughness = 0.4; emat.metallic = 0.1
	em.material = emat
	var envelope := MeshInstance3D.new(); envelope.mesh = em; envelope.position.y = 0.5
	balloon_root.add_child(envelope)
	envelope_node = envelope
	envelope_original_scale = envelope.scale

	# Ropes
	for i in 4:
		var angle := (PI / 2.0) * i
		var rrm := CylinderMesh.new()
		rrm.top_radius = 0.02; rrm.bottom_radius = 0.02; rrm.height = 0.6; rrm.radial_segments = 4
		var rmat := StandardMaterial3D.new(); rmat.albedo_color = Color(0.6, 0.5, 0.3)
		rrm.material = rmat
		var rope := MeshInstance3D.new(); rope.mesh = rrm
		rope.position = Vector3(cos(angle) * 0.2, 0.05, sin(angle) * 0.2)
		rope.rotate_z(0.22 * cos(angle)); rope.rotate_x(0.22 * sin(angle))
		balloon_root.add_child(rope)

	# Basket
	var bm := CylinderMesh.new()
	bm.top_radius = 0.28; bm.bottom_radius = 0.24; bm.height = 0.38; bm.radial_segments = 8
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.47, 0.31, 0.12); bmat.roughness = 0.9
	bm.material = bmat
	var basket := MeshInstance3D.new(); basket.mesh = bm; basket.position.y = -0.5
	balloon_root.add_child(basket)

	base_balloon_scale = 1.0


# =================================================================
# UI Construction
# =================================================================
func _glass_panel(radius: float = 14.0, alpha: float = 0.72) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.08, 0.18, alpha)
	s.set_corner_radius_all(int(radius))
	s.set_border_width_all(1)
	s.border_color = Color(1, 1, 1, 0.18)
	# NOTE: set_content_margin_all() does NOT exist in Godot 4 — set individually
	s.content_margin_left  = 14
	s.content_margin_right = 14
	s.content_margin_top   = 10
	s.content_margin_bottom = 10
	return s

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10  # Guarantee render on top of 3D viewport
	add_child(canvas)

	# Red hit flash overlay
	hit_flash = ColorRect.new()
	hit_flash.color = Color(1, 0, 0, 0.38)
	hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_flash.visible = false
	canvas.add_child(hit_flash)

	# Floating popups
	popups_container = Control.new()
	popups_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popups_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(popups_container)

	_build_hud(canvas)
	_build_main_menu(canvas)
	_build_gameover(canvas)

# --- HUD ---
func _build_hud(canvas: CanvasLayer) -> void:
	game_hud = Control.new()
	game_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_hud.visible = false
	canvas.add_child(game_hud)

	# Top stats bar
	var top := HBoxContainer.new()
	top.set_anchor(SIDE_LEFT, 0.0); top.set_anchor(SIDE_RIGHT, 1.0)
	top.set_anchor(SIDE_TOP, 0.0);  top.set_anchor(SIDE_BOTTOM, 0.0)
	top.offset_bottom = 78
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	game_hud.add_child(top)

	var sc := _hud_card("SCORE", "0")
	score_label = sc.get_child(0).get_child(1) as Label
	top.add_child(sc)

	var tc := _hud_card("TIME", "00:00")
	time_label = tc.get_child(0).get_child(1) as Label
	top.add_child(tc)



	# Air gauge
	var air_panel := PanelContainer.new()
	air_panel.add_theme_stylebox_override("panel", _glass_panel())
	air_panel.set_anchor(SIDE_LEFT, 0.5);  air_panel.set_anchor(SIDE_RIGHT, 0.5)
	air_panel.set_anchor(SIDE_TOP, 0.0);   air_panel.set_anchor(SIDE_BOTTOM, 0.0)
	air_panel.offset_left = -210; air_panel.offset_right  = 210
	air_panel.offset_top  = 82;   air_panel.offset_bottom = 138
	game_hud.add_child(air_panel)

	var av := VBoxContainer.new(); av.add_theme_constant_override("separation", 6); air_panel.add_child(av)
	var ah := HBoxContainer.new(); ah.add_theme_constant_override("separation", 8); av.add_child(ah)

	var air_lbl := Label.new(); air_lbl.text = "⛽ FUEL LEVEL"
	air_lbl.add_theme_font_size_override("font_size", 13)
	air_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	ah.add_child(air_lbl)

	air_percent_label = Label.new(); air_percent_label.text = "100%"
	air_percent_label.add_theme_font_size_override("font_size", 15)
	air_percent_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.75))
	ah.add_child(air_percent_label)

	air_fill_bar = ProgressBar.new()
	air_fill_bar.min_value = 0; air_fill_bar.max_value = 100; air_fill_bar.value = 100
	air_fill_bar.show_percentage = false
	air_fill_bar.custom_minimum_size = Vector2(0, 14)
	air_fill_style = StyleBoxFlat.new()
	air_fill_style.bg_color = Color(0.18, 0.85, 0.65)
	air_fill_style.set_corner_radius_all(8)
	air_fill_bar.add_theme_stylebox_override("fill", air_fill_style)
	var air_bg := StyleBoxFlat.new()
	air_bg.bg_color = Color(0.08, 0.10, 0.18, 0.85)
	air_bg.set_corner_radius_all(8)
	air_fill_bar.add_theme_stylebox_override("background", air_bg)
	av.add_child(air_fill_bar)

	# Touch controls (mobile / mouse)
	var tc_row := HBoxContainer.new()
	tc_row.set_anchor(SIDE_LEFT, 0.0); tc_row.set_anchor(SIDE_RIGHT, 1.0)
	tc_row.set_anchor(SIDE_TOP, 1.0);  tc_row.set_anchor(SIDE_BOTTOM, 1.0)
	tc_row.offset_top = -100; tc_row.offset_bottom = -8
	tc_row.add_theme_constant_override("separation", 18)
	tc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	game_hud.add_child(tc_row)

	var bl := _touch_btn("◀", false)
	bl.button_down.connect(func(): key_left = true)
	bl.button_up.connect(func(): key_left = false)
	tc_row.add_child(bl)

	var bu := _touch_btn("▲ BURNER", true)
	bu.pressed.connect(func(): if game_mode == Mode.PLAYING: _pump_up())
	tc_row.add_child(bu)

	var bd := _touch_btn("▼ VENT", true)
	bd.pressed.connect(func(): if game_mode == Mode.PLAYING: _vent_down())
	tc_row.add_child(bd)

	var brr := _touch_btn("▶", false)
	brr.button_down.connect(func(): key_right = true)
	brr.button_up.connect(func(): key_right = false)
	tc_row.add_child(brr)

func _hud_card(lbl_txt: String, val_txt: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _glass_panel())
	card.custom_minimum_size = Vector2(130, 60)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)
	var l := Label.new(); l.text = lbl_txt
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.65, 0.78, 1.0, 0.85))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var v := Label.new(); v.text = val_txt
	v.add_theme_font_size_override("font_size", 22)
	v.add_theme_color_override("font_color", Color.WHITE)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(v)
	return card

func _touch_btn(txt: String, big: bool) -> Button:
	var b := Button.new(); b.text = txt
	b.custom_minimum_size = Vector2(140 if big else 88, 72)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.96, 0.44, 0.05, 0.45) if big else Color(0.12, 0.45, 1.0, 0.38)
	s.set_corner_radius_all(16); s.set_border_width_all(2)
	s.border_color = Color(1, 1, 1, 0.28)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover",   s)
	b.add_theme_stylebox_override("pressed", s)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color.WHITE)
	return b

# --- Main Menu ---
func _build_main_menu(canvas: CanvasLayer) -> void:
	menu_screen = Control.new()
	menu_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(menu_screen)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0.02, 0.12, 0.72)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_screen.add_child(overlay)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _glass_panel(18.0, 0.88))
	card.set_anchor(SIDE_LEFT, 0.5);  card.set_anchor(SIDE_RIGHT, 0.5)
	card.set_anchor(SIDE_TOP, 0.5);   card.set_anchor(SIDE_BOTTOM, 0.5)
	card.offset_left = -290; card.offset_right  = 290
	card.offset_top  = -275; card.offset_bottom = 275
	menu_screen.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	var badge := Label.new(); badge.text = "🎈  3D AIR SURVIVAL"
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(0.4, 0.82, 1.0))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(badge)

	var title := Label.new(); title.text = "Balloon Air Escape"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(title)

	var sub := Label.new()
	sub.text = "Keep your hot-air balloon inflated before the air leaks out!"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.72, 0.84, 1.0, 0.88))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD; vb.add_child(sub)

	vb.add_child(HSeparator.new())

	var rules := Label.new()
	rules.text = "⏳  Air cools down — balance lift to stay aloft\n⛽  Collect green gas tanks  →  +25% Fuel!\n⚠️  Avoid red spikes  →  -30% Fuel (instant!)"
	rules.add_theme_font_size_override("font_size", 14)
	rules.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD; vb.add_child(rules)

	var ctrl_lbl := Label.new()
	ctrl_lbl.text = "A/D (steer)   •   W/SPACE (burner - rise)   •   S/DOWN (vent - sink)"
	ctrl_lbl.add_theme_font_size_override("font_size", 13)
	ctrl_lbl.add_theme_color_override("font_color", Color(0.6, 0.72, 1.0, 0.82))
	ctrl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(ctrl_lbl)

	var start_btn := _menu_btn("▶   START GAME", Color(0.12, 0.47, 1.0))
	start_btn.pressed.connect(_start_game); vb.add_child(start_btn)

# --- Game Over ---
func _build_gameover(canvas: CanvasLayer) -> void:
	gameover_screen = Control.new()
	gameover_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gameover_screen.visible = false
	canvas.add_child(gameover_screen)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0.05, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gameover_screen.add_child(overlay)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _glass_panel(18.0, 0.88))
	card.set_anchor(SIDE_LEFT, 0.5);  card.set_anchor(SIDE_RIGHT, 0.5)
	card.set_anchor(SIDE_TOP, 0.5);   card.set_anchor(SIDE_BOTTOM, 0.5)
	card.offset_left = -260; card.offset_right  = 260
	card.offset_top  = -235; card.offset_bottom = 235
	gameover_screen.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	var go_badge := Label.new(); go_badge.text = "💥  GAME OVER"
	go_badge.add_theme_font_size_override("font_size", 14)
	go_badge.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	go_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(go_badge)

	var go_title := Label.new(); go_title.text = "Balloon Deflated!"
	go_title.add_theme_font_size_override("font_size", 30)
	go_title.add_theme_color_override("font_color", Color.WHITE)
	go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(go_title)

	gameover_reason_label = Label.new()
	gameover_reason_label.add_theme_font_size_override("font_size", 14)
	gameover_reason_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.6))
	gameover_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameover_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD; vb.add_child(gameover_reason_label)

	# Results row
	var rh := HBoxContainer.new(); rh.add_theme_constant_override("separation", 14)
	rh.alignment = BoxContainer.ALIGNMENT_CENTER; vb.add_child(rh)

	var sb := _result_box("Final Score", "0"); res_score_label = sb.get_child(0).get_child(1) as Label; rh.add_child(sb)
	var tb := _result_box("Time", "0s");       res_time_label  = tb.get_child(0).get_child(1) as Label; rh.add_child(tb)
	var pb := _result_box("Gas Tanks", "0");       res_pumps_label = pb.get_child(0).get_child(1) as Label; rh.add_child(pb)

	var restart_btn := _menu_btn("↺   PLAY AGAIN", Color(0.12, 0.47, 1.0))
	restart_btn.pressed.connect(_start_game); vb.add_child(restart_btn)

func _menu_btn(txt: String, col: Color) -> Button:
	var b := Button.new(); b.text = txt
	b.custom_minimum_size = Vector2(240, 56)
	var s := StyleBoxFlat.new(); s.bg_color = col; s.set_corner_radius_all(14)
	s.content_margin_left = 20; s.content_margin_right  = 20
	s.content_margin_top  = 12; s.content_margin_bottom = 12
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat; sh.bg_color = col.lightened(0.18)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color.WHITE)
	return b

func _result_box(lbl: String, val: String) -> PanelContainer:
	var pc := PanelContainer.new()
	var s := StyleBoxFlat.new(); s.bg_color = Color(0.10, 0.12, 0.26, 0.85); s.set_corner_radius_all(10)
	s.content_margin_left = 14; s.content_margin_right  = 14
	s.content_margin_top  = 10; s.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", s); pc.custom_minimum_size = Vector2(110, 72)
	var vb := VBoxContainer.new(); vb.alignment = BoxContainer.ALIGNMENT_CENTER; vb.add_theme_constant_override("separation", 4); pc.add_child(vb)
	var ll := Label.new(); ll.text = lbl
	ll.add_theme_font_size_override("font_size", 11)
	ll.add_theme_color_override("font_color", Color(0.60, 0.72, 1.0, 0.82))
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(ll)
	var vl := Label.new(); vl.text = val
	vl.add_theme_font_size_override("font_size", 24)
	vl.add_theme_color_override("font_color", Color.WHITE)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(vl)
	return pc


# =================================================================
# Input (keyboard)
# =================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var iek := event as InputEventKey
		var pressed := iek.pressed
		match iek.physical_keycode:
			KEY_A, KEY_LEFT:
				key_left = pressed
			KEY_D, KEY_RIGHT:
				key_right = pressed
			KEY_SPACE, KEY_W, KEY_UP:
				if pressed and not iek.is_echo():
					_pump_up()
			KEY_S, KEY_DOWN:
				if pressed and not iek.is_echo():
					_vent_down()


# =================================================================
# Game Logic
# =================================================================
func _start_game() -> void:
	game_mode      = Mode.PLAYING
	air_pressure   = 100.0 # Active fuel starts at 100%
	balloon_heat   = 50.0  # Heat starts at 50%
	drain_rate     = 2.5
	score          = 0.0
	survival_time  = 0.0
	pumps_collected = 0
	pos_x = 0.0; pos_y = 0.5
	vel_x = 0.0; vel_y = 0.0
	elapsed = 0.0
	last_deform_pressure = -999.0

	if balloon_root:
		balloon_root.position = Vector3(0, 0.5, 0)
		balloon_root.rotation = Vector3.ZERO
		balloon_root.scale    = Vector3.ONE * base_balloon_scale

	for p in air_pumps:   _reset_pump(p)
	for s in spikes:      _reset_spike(s)
	for t in trees:       _reset_ground_item(t, true)
	for h in houses:      _reset_ground_item(h, true)

	menu_screen.visible     = false
	gameover_screen.visible = false
	game_hud.visible        = true

func _game_over(reason: String) -> void:
	game_mode               = Mode.GAME_OVER
	game_hud.visible        = false
	gameover_screen.visible = true
	gameover_reason_label.text = reason
	res_score_label.text    = str(int(score))
	res_time_label.text     = str(int(survival_time)) + "s"
	res_pumps_label.text    = str(pumps_collected)

func _pump_up() -> void:
	if game_mode != Mode.PLAYING: return
	if air_pressure <= 0.0: return # Out of active fuel!
	
	# Burner consumes fuel directly from active fuel level bar (air_pressure)
	air_pressure = maxf(0.0, air_pressure - 2.5)
	balloon_heat = minf(100.0, balloon_heat + 12.0)
	
	# Fire burner & lift
	vel_y += 0.08
	spring_vel_y += 0.18 # stretch Y on burner
	_spawn_flame()

func _vent_down() -> void:
	if game_mode != Mode.PLAYING: return
	
	# Venting releases hot air/lift velocity (free, does not affect fuel)
	vel_y -= 0.08
	spring_vel_y -= 0.18 # squish Y on vent
	_spawn_vent_puff()


# =================================================================
# _process — Main Game Loop
# =================================================================
func _process(delta: float) -> void:
	elapsed += delta
	var fly_speed := (16.0 + survival_time * 0.45) * delta

	_scroll_world(fly_speed)

	match game_mode:
		Mode.PLAYING: _update_playing(delta, fly_speed)
		Mode.MENU:    _update_menu_idle()

	_update_balloon_deflation(delta)

func _scroll_world(fly_speed: float) -> void:
	for t: Node3D in terrains:
		t.position.z += fly_speed * 1.5
		if t.position.z > 60.0: t.position.z -= 240.0

	for t: Node3D in trees:
		t.position.z += fly_speed * 1.5
		if t.position.z > 20.0: _reset_ground_item(t, false)

	for h: Node3D in houses:
		h.position.z += fly_speed * 1.5
		if h.position.z > 20.0: _reset_ground_item(h, false)

	for c: Node3D in clouds:
		c.position.z += fly_speed * 1.2
		if c.position.z > 20.0: _reset_cloud(c, false)

func _update_playing(delta: float, fly_speed: float) -> void:
	# Survival stats
	survival_time += delta
	score         += delta * 18.0
	
	# Passive fuel consumption (the progress bar drains constantly, getting faster as survival time increases)
	var fuel_drain := (6.5 + survival_time * 0.035) * delta
	air_pressure = maxf(0.0, air_pressure - fuel_drain)

	# Passive air heat cooling (decays towards ambient/cold temperature of 0%)
	balloon_heat = lerpf(balloon_heat, 0.0, 0.72 * delta)

	# Game over condition: fuel level reaches 0%
	if air_pressure <= 0.0:
		air_pressure = 0.0
		_game_over("Your fuel level ran out completely!")
		return

	# HUD updates
	score_label.text       = str(int(score))
	var mins := str(int(survival_time) / 60).pad_zeros(2)
	var secs := str(int(survival_time) % 60).pad_zeros(2)
	time_label.text        = mins + ":" + secs
	
	# Show GAS TANKS collected count only if valid
	if pumps_label:
		pumps_label.text       = str(pumps_collected) + " ⛽"
	air_percent_label.text = str(int(air_pressure)) + "%"
	air_fill_bar.value     = air_pressure

	# Fuel gauge color: green (full) → yellow (half) → red (empty)
	if air_fill_style:
		if air_pressure > 60.0:
			air_fill_style.bg_color = Color(0.18, 0.85, 0.65)
		elif air_pressure > 30.0:
			air_fill_style.bg_color = Color(0.95, 0.75, 0.10)
		else:
			air_fill_style.bg_color = Color(0.90, 0.20, 0.20)

	# Buoyancy physics & steering controls
	if key_left:  vel_x -= 0.45 * delta
	if key_right: vel_x += 0.45 * delta
	vel_x *= 0.90
	
	# Calculate passive buoyancy: neutral hover at ~51.8% balloon heat
	var lift_factor := balloon_heat / 100.0
	var buoyancy_acc := (lift_factor * 0.44 - 0.228) * delta
	vel_y += buoyancy_acc
	vel_y *= 0.96 # air resistance/damping
	
	pos_x += vel_x
	pos_y += vel_y
	pos_x = clampf(pos_x, -4.5, 4.5)
	pos_y = clampf(pos_y, -1.4, 3.5)

	if balloon_root:
		balloon_root.position.x = pos_x
		balloon_root.position.y = pos_y
		
		# Target tilts based on velocities
		var target_rx := clampf(vel_y * 0.5, -0.15, 0.15)
		var target_rz := clampf(-vel_x * 0.4, -0.3, 0.3)
		
		# Wind bobbing: subtle sine oscillations on X and Z axes
		target_rx += cos(elapsed * 1.8) * 0.016
		target_rz += sin(elapsed * 2.4) * 0.022
		
		# Smoothly sway towards target
		balloon_root.rotation.x = lerpf(balloon_root.rotation.x, target_rx, 8.0 * delta)
		balloon_root.rotation.z = lerpf(balloon_root.rotation.z, target_rz, 8.0 * delta)

	# Camera follow
	var base_cam_x := camera.position.x + (pos_x * 0.4 - camera.position.x) * 0.05
	var base_cam_y := camera.position.y + (pos_y * 0.3 + 1.8 - camera.position.y) * 0.05
	
	camera.position.x = base_cam_x
	camera.position.y = base_cam_y
	
	# Decay screen shake intensity
	camera_shake_intensity = lerpf(camera_shake_intensity, 0.0, 6.0 * delta)
	
	# Apply camera position shake offset
	if camera_shake_intensity > 0.001:
		camera.position.x += randf_range(-1.0, 1.0) * camera_shake_intensity * 0.35
		camera.position.y += randf_range(-1.0, 1.0) * camera_shake_intensity * 0.35

	var look_at_pos := Vector3(pos_x * 0.2, pos_y * 0.2 + 0.5, 0.0)
	if camera.global_position.distance_squared_to(look_at_pos) > 0.0001:
		camera.look_at(look_at_pos)
		
	# Apply camera roll/tilt shake after look_at (since look_at resets roll to 0)
	if camera_shake_intensity > 0.001:
		camera.rotation.z += randf_range(-1.0, 1.0) * camera_shake_intensity * 0.06

	# Air Pumps (collectibles)
	var bpos := balloon_root.global_position if balloon_root else Vector3.ZERO
	for pump: Node3D in air_pumps:
		pump.position.z += fly_speed
		pump.rotate_y(0.04)
		pump.position.y += sin(elapsed * 3.0 + pump.position.x) * 0.005

		if pump.position.distance_squared_to(bpos) < 1.44:   # 1.2 * 1.2
			air_pressure = minf(100.0, air_pressure + 25.0)
			score        += 150.0
			pumps_collected += 1
			_spawn_burst(pump.position, Color(0.204, 0.827, 0.6))
			_spawn_popup("+25% FUEL! ⛽", Color(0.2, 1.0, 0.6))
			_reset_pump(pump)
		elif pump.position.z > 6.0:
			_reset_pump(pump)

	# Spikes (hazards)
	for spike: Node3D in spikes:
		spike.position.z += fly_speed
		spike.rotate_x(0.03); spike.rotate_y(0.04)

		if spike.position.distance_squared_to(bpos) < 1.21:  # 1.1 * 1.1
			air_pressure = maxf(0.0, air_pressure - 30.0)   # Lose 30% active fuel
			balloon_heat = maxf(20.0, balloon_heat - 40.0)   # Envelope damage
			spring_vel_y = -0.55 # violent wobble on impact
			_spawn_burst(spike.position, Color(0.937, 0.267, 0.267))
			_spawn_popup("-30% FUEL! ⚠️", Color(1.0, 0.3, 0.3))
			_trigger_hit_flash()
			camera_shake_intensity = 0.75 # Trigger physical camera shake
			_reset_spike(spike)
			if air_pressure <= 0.0:
				_game_over("A spike popped your fuel tank!")
				return
		elif spike.position.z > 6.0:
			_reset_spike(spike)

func _update_menu_idle() -> void:
	if balloon_root:
		balloon_root.position.y = sin(elapsed * 1.5) * 0.15 + 0.5
		balloon_root.rotate_y(0.005)


# =================================================================
# Balloon Deflation Visual (scale-based, replaces vertex deform)
# As air drops the balloon squishes vertically and widens slightly
# =================================================================
func _update_balloon_deflation(delta: float) -> void:
	if not balloon_root: return

	# Solve spring physics (Hooke's Law with damping: force = -K * x - D * v)
	var displacement := spring_scale_y - 1.0
	var spring_force := -SPRING_K * displacement - SPRING_D * spring_vel_y
	spring_vel_y += spring_force * delta
	spring_scale_y += spring_vel_y * delta

	# Guard scale limits to avoid visual collapse or flipping
	spring_scale_y = clampf(spring_scale_y, 0.45, 1.8)

	var p := clampf(balloon_heat / 100.0, 0.0, 1.0)
	var d := 1.0 - p
	
	# Base scale from hot-air cooling/deflation (local scale values relative to 1.0)
	# Y scale drops by up to 22% (drapes down).
	# XZ scale collapses inward by up to 45% (collapses heavily).
	var base_sy  := 1.0 - d * 0.22
	var base_sxz := 1.0 - d * 0.45

	# Combine base scaling with spring scaling (constant volume: scale Y, divide XZ by sqrt(Y))
	var final_sy  := base_sy * spring_scale_y
	var final_sxz := base_sxz / sqrt(spring_scale_y)

	if envelope_node and is_instance_valid(envelope_node):
		# Scale ONLY the envelope mesh (fabric), relative to its original scale!
		envelope_node.scale = envelope_original_scale * Vector3(final_sxz, final_sy, final_sxz)
		# Keep the root at its constant base scale
		balloon_root.scale = Vector3.ONE * base_balloon_scale
	else:
		# Fallback: scale the entire root if envelope mesh cannot be identified
		balloon_root.scale = Vector3(final_sxz, final_sy, final_sxz) * base_balloon_scale


# =================================================================
# Visual Effects
# =================================================================
func _spawn_flame() -> void:
	if not balloon_root: return
	var p := CPUParticles3D.new()
	p.one_shot              = true
	p.explosiveness         = 0.85
	p.amount                = 5
	p.lifetime              = 0.35
	p.position              = balloon_root.position + Vector3(0, -0.3, 0)
	p.direction             = Vector3(0, -1, 0)
	p.spread                = 28.0
	p.initial_velocity_min  = 1.5; p.initial_velocity_max = 3.0
	p.scale_amount_min      = 0.06; p.scale_amount_max    = 0.12
	
	# Shaded material to blend with world lighting
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	
	var sm := SphereMesh.new()
	sm.radius = 0.5; sm.height = 1.0
	sm.material = mat
	p.mesh = sm
	
	# Natural warm fire color
	p.color = Color(0.98, 0.50, 0.05, 0.8)
	p.gravity               = Vector3(0, -2, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(func():
		if is_instance_valid(p): p.queue_free()
	)

func _spawn_vent_puff() -> void:
	if not balloon_root: return
	var p := CPUParticles3D.new()
	p.one_shot              = true
	p.explosiveness         = 0.9
	p.amount                = 4
	p.lifetime              = 0.45
	p.position              = balloon_root.position + Vector3(0, 1.25, 0)
	p.direction             = Vector3.UP
	p.spread                = 18.0
	p.initial_velocity_min  = 2.0; p.initial_velocity_max = 3.5
	p.scale_amount_min      = 0.04; p.scale_amount_max    = 0.08
	
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	
	var sm := SphereMesh.new()
	sm.radius = 0.5; sm.height = 1.0
	sm.material = mat
	p.mesh = sm
	
	p.color = Color(0.9, 0.9, 0.95, 0.45)
	p.gravity               = Vector3(0, 1.0, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(func():
		if is_instance_valid(p): p.queue_free()
	)

func _spawn_burst(pos: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot              = true
	p.explosiveness         = 1.0
	p.amount                = 22
	p.lifetime              = 1.0
	p.position              = pos
	p.direction             = Vector3.UP
	p.spread                = 180.0
	p.initial_velocity_min  = 2.5; p.initial_velocity_max = 6.0
	p.scale_amount_min      = 0.10; p.scale_amount_max    = 0.22
	
	# Shaded material to blend with world lighting
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	
	var sm := SphereMesh.new()
	sm.radius = 0.5; sm.height = 1.0
	sm.material = mat
	p.mesh = sm
	
	# Natural particle colors matching the source object
	p.color = col
	p.gravity               = Vector3(0, -4, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(p): p.queue_free()
	)

func _spawn_popup(text: String, col: Color) -> void:
	if not popups_container: return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", col)
	lbl.set_anchor(SIDE_LEFT, 0.5); lbl.set_anchor(SIDE_TOP, 0.5)
	lbl.offset_left = randf_range(-140, 140)
	lbl.offset_top  = randf_range(-60, 60)
	popups_container.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "offset_top",   lbl.offset_top - 70, 0.9)
	tw.tween_property(lbl, "modulate:a",   0.0,                 0.9)
	tw.chain().tween_callback(lbl.queue_free)

func _trigger_hit_flash() -> void:
	if not hit_flash: return
	hit_flash.visible = true
	hit_flash.color.a = 0.45
	var tw := create_tween()
	tw.tween_property(hit_flash, "color:a", 0.0, 0.45)
	tw.chain().tween_callback(func(): hit_flash.visible = false)
