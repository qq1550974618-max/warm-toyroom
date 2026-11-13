extends CharacterBody3D

signal projectile_requested(direction: int)

const RUN_SPEED := 2.62
const GRAVITY := 11.5
const JUMP_SPEED := 3.9
var visual: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var skirt: MeshInstance3D
var skirt_material: ShaderMaterial
var springs: SpringBoneSimulator3D
var locomotion: SkeletonModifier3D
var facing := 1
var ground_motion := true
var turning_amount := 0.0
var state := "idle"
var jump_timer := 0.0
var air_time := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var jump_count := 0
var land_count := 0
var camera: Camera3D
var animation_names := {}
var source_root_speed := 0.0
var max_root_horizontal_drift := 0.0
var sleeves_corrected := 0
var cloth_lag := Vector3.ZERO
var anime_style := true
var generic_root_speed := 0.0
var anime_root_speed := 0.0
var can_control := false
var extra_motion_set := false
var spawn_point := Vector3(-1.2,0.04,0)
var action_time := 0.0
var action_fired := false
var cast_count := 0
var hurt_count := 0
var cartoon_materials := true
var original_body_materials: Array[BaseMaterial3D] = []
var toon_body_materials: Array[BaseMaterial3D] = []
var skirt_pbr_shader: Shader
var skirt_toon_shader: Shader

func setup(view_camera: Camera3D) -> void:
	camera = view_camera
	name = "Player"
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.12
	floor_max_angle = deg_to_rad(46)
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.105
	shape.height = 0.91
	shape_node.shape = shape
	shape_node.position.y = 0.455
	add_child(shape_node)
	visual = (load("res://assets/character.glb") as PackedScene).instantiate()
	add_child(visual)
	_find_nodes(visual)
	assert(player != null and skeleton != null and skirt != null)
	_prepare_animations()
	var anime_library := load("res://assets/anime_motions.tres") as AnimationLibrary
	if not OS.get_cmdline_user_args().has("--original-walk"):
		# Keep the other authored actions intact; only walking comes from the
		# imported Microsoft Rocketbox female motion (MIT, notices bundled).
		var imported_walk := load("res://assets/female_walk.tres") as AnimationLibrary
		anime_library = anime_library.duplicate() as AnimationLibrary
		anime_library.remove_animation("walk")
		anime_library.add_animation("walk",imported_walk.get_animation("walk"))
		anime_library.set_meta("walk_reference_speed",imported_walk.get_meta("walk_reference_speed"))
		anime_library.set_meta("walk_source",imported_walk.get_meta("source"))
	if not OS.get_cmdline_user_args().has("--original-extra-motions"):
		var extra_library:=load("res://assets/extra_motions_candidate.tres") as AnimationLibrary
		player.add_animation_library("extra",extra_library)
		anime_library=anime_library.duplicate() as AnimationLibrary
		for pair in [["run","run_styled"],["jump","jump"],["land","land"],["fall_air","fall_air"]]:
			if anime_library.has_animation(pair[0]):anime_library.remove_animation(pair[0])
			anime_library.add_animation(pair[0],extra_library.get_animation(pair[1]))
		anime_library.set_meta("run_reference_speed",extra_library.get_meta("run_reference_speed"))
		anime_library.set_meta("run_source","Microsoft Rocketbox f_run_extremefemale")
		extra_motion_set=true
	player.add_animation_library("anime",anime_library)
	player.add_animation_library("free",load("res://assets/free_motions.tres"))
	generic_root_speed = source_root_speed
	anime_root_speed = anime_library.get_meta("run_reference_speed",source_root_speed)
	source_root_speed = anime_root_speed
	_prepare_materials()
	_setup_skirt()
	locomotion = load("res://locomotion_modifier.gd").new()
	locomotion.name = "GroundContactsAndGaze"
	skeleton.add_child(locomotion)
	locomotion.initialize(self, camera)
	_build_hair()
	springs.modification_processed.connect(_update_skirt)
	visual.rotation.y = 0.0
	_play("wait", 0.0)
	player.advance(0)
	process_priority = 0
	print("CHARACTER_READY ", JSON.stringify({"bones": skeleton.get_bone_count(), "root_speed": source_root_speed, "clips": animation_names}))

func _find_nodes(node: Node) -> void:
	if node is AnimationPlayer: player = node
	if node is Skeleton3D: skeleton = node
	if node is MeshInstance3D:
		if str(node.name).contains("Character_Body"): body_mesh = node
		if str(node.name).contains("Skirt_Cloth"): skirt = node
	for child in node.get_children(): _find_nodes(child)

func _prepare_animations() -> void:
	# Hip translations in this export use a rotated parent basis. Remove travel
	# in skeleton coordinates, preserving the vertical running bounce.
	var library := AnimationLibrary.new()
	var hip := skeleton.find_bone("Hip")
	var parent_rest := skeleton.get_bone_global_rest(skeleton.get_bone_parent(hip))
	var rest_origin := skeleton.get_bone_global_rest(hip).origin
	for source_name in player.get_animation_list():
		var clip := player.get_animation(source_name).duplicate(true) as Animation
		var key := source_name.get_slice("_001", 0)
		if key.to_upper() == "RESET": continue
		for t in range(clip.get_track_count()):
			if clip.track_get_type(t) != Animation.TYPE_POSITION_3D: continue
			if not str(clip.track_get_path(t)).ends_with(":Hip"): continue
			var keys := clip.track_get_key_count(t)
			if key == "run":
				var start: Vector3 = parent_rest * Vector3(clip.track_get_key_value(t, 0))
				var end: Vector3 = parent_rest * Vector3(clip.track_get_key_value(t, keys - 1))
				source_root_speed = absf(end.x - start.x) / (clip.track_get_key_time(t, keys - 1) - clip.track_get_key_time(t, 0))
			for k in range(keys):
				var position_in_skeleton: Vector3 = parent_rest * Vector3(clip.track_get_key_value(t, k))
				position_in_skeleton.x = rest_origin.x
				position_in_skeleton.z = rest_origin.z
				if key == "jump":
					position_in_skeleton.y = rest_origin.y + clampf(position_in_skeleton.y - rest_origin.y, -0.10, 0.015)
				clip.track_set_key_value(t, k, parent_rest.affine_inverse() * position_in_skeleton)
		clip.loop_mode = Animation.LOOP_LINEAR if key in ["wait", "run"] else Animation.LOOP_NONE
		library.add_animation(key, clip)
		animation_names[key] = "game/" + key
	player.add_animation_library("game", library)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS

func _physics_process(delta: float) -> void:
	if player == null: return
	if state in ["hurt","cast","victory"]:
		_special_action(delta)
		return
	var input := Input.get_axis("move_left", "move_right") if can_control else 0.0
	if can_control and Input.is_action_just_pressed("cast") and is_on_floor() and state not in ["prepare","air"]:
		state = "cast"
		action_time = 0.0
		action_fired = false
		velocity.x = 0
		player.play("free/cast",0.08)
		player.speed_scale = 1.0
		cast_count += 1
		locomotion.release_feet()
		return
	if can_control and Input.is_action_just_pressed("jump"): jump_buffer = 0.14
	else: jump_buffer = maxf(jump_buffer - delta, 0.0)
	if is_on_floor(): coyote = 0.10
	else: coyote = maxf(coyote - delta, 0.0)
	if input != 0.0: facing = 1 if input > 0.0 else -1
	if jump_buffer > 0.0 and coyote > 0.0 and state not in ["prepare", "land"]:
		state = "prepare"
		jump_timer = 0.10
		jump_buffer = 0.0
		_play("jump", 0.10)
		player.speed_scale = 2.8
	if state == "prepare":
		jump_timer -= delta
		if jump_timer <= 0.0:
			velocity.y = JUMP_SPEED
			state = "air"
			coyote = 0.0
			air_time = 0.0
			jump_count += 1
			locomotion.release_feet()
	if not is_on_floor(): velocity.y -= GRAVITY * delta
	var target_speed := input * RUN_SPEED
	velocity.x = move_toward(velocity.x, target_speed, (16.0 if input != 0.0 else 20.0) * delta)
	velocity.z = 0.0
	var was_grounded := is_on_floor()
	if was_grounded and state not in ["prepare", "air"] and absf(velocity.x) > 0.01:
		_try_step_up(delta)
	move_and_slide()
	if was_grounded and velocity.y <= 0.0 and state not in ["prepare", "air"] and not is_on_floor():
		apply_floor_snap()
	position.z = 0.0
	if position.x < -3.4: position.x = -3.4; velocity.x = maxf(0.0, velocity.x)
	if position.x > 34.4: position.x = 34.4; velocity.x = minf(0.0, velocity.x)
	if not is_on_floor():
		air_time += delta
		if state not in ["air", "prepare"] and air_time > 0.14:
			state = "air"
			_play("jump", 0.12)
			player.seek(0.65, true)
			player.speed_scale = 1.5
	else:
		air_time = 0.0
	if not was_grounded and is_on_floor() and state == "air":
		state = "land"
		jump_timer = 0.24 if anime_style else 0.10
		land_count += 1
		if anime_style:
			_play("land",0.035)
			player.speed_scale = 1.0
		else:
			player.seek(1.90, true)
			player.speed_scale = 2.8
	if state == "land":
		jump_timer -= delta
		if jump_timer <= 0.0: state = "idle"
	ground_motion = state not in ["air", "prepare"] and is_on_floor()
	if state not in ["air", "prepare", "land"]:
		if absf(velocity.x) > 0.06:
			state = "run"
			_play("run", 0.13)
			player.speed_scale = maxf(absf(velocity.x) / maxf(source_root_speed, 0.1), 0.1)
		else:
			state = "idle"
			_play("wait", 0.18)
			player.speed_scale = 1.0
	# Raw model forward is +X: these headings produce a genuine side profile.
	var target_yaw := 0.0 if facing > 0 else -PI
	turning_amount = absf(wrapf(target_yaw - visual.rotation.y, -PI, PI))
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, 1.0 - exp(-delta * 16.0))
	cloth_lag = cloth_lag.lerp(Vector3(-velocity.x * 0.009, 0, 0), 1.0 - exp(-delta * 5.0))
	skirt_material.set_shader_parameter("cloth_lag", cloth_lag)

func _special_action(delta: float) -> void:
	action_time += delta
	if not is_on_floor(): velocity.y -= GRAVITY*delta
	velocity.x = move_toward(velocity.x,0.0,delta*5.0)
	move_and_slide()
	position.z = 0.0
	ground_motion = is_on_floor() and state != "hurt"
	turning_amount = 0.0
	if state == "cast" and not action_fired and action_time >= 0.25:
		action_fired = true
		projectile_requested.emit(facing)
	if (state == "cast" and action_time >= 0.70) or (state == "hurt" and action_time >= 0.38):
		state = "idle"
		_play("wait",0.10)
		player.speed_scale = 1.0

func take_hit(direction: int) -> void:
	state = "hurt"
	action_time = 0.0
	hurt_count += 1
	velocity = Vector3(direction*1.6,1.5,0)
	player.play("free/hurt",0.045)
	player.speed_scale = 1.0
	locomotion.release_feet()

func celebrate() -> void:
	can_control = false
	state = "victory"
	velocity.x = 0
	action_time = 0.0
	player.play("free/victory",0.12)
	player.speed_scale = 0.70
	locomotion.release_feet()

func _play(key: String, blend: float) -> void:
	var name: String = "anime/"+key if anime_style and key in ["wait","walk","run","jump","land","fall_air"] else animation_names[key]
	if player.assigned_animation != name: player.play(name, blend)

func toggle_motion_style() -> void:
	anime_style = not anime_style
	source_root_speed = anime_root_speed if anime_style else generic_root_speed
	locomotion.release_feet()
	springs.reset()
	var clip := "run" if absf(velocity.x) > 0.1 else "wait"
	if state in ["air","prepare"]: clip = "jump"
	_play(clip,0.15)

func _try_step_up(delta: float) -> void:
	var forward := Vector3(signf(velocity.x) * (absf(velocity.x)*delta+0.025), 0, 0)
	if not test_move(global_transform, forward): return
	var raised := global_transform
	raised.origin.y += 0.085
	if not test_move(raised, forward):
		global_position.y += 0.085

func reset_position() -> void:
	position = spawn_point
	velocity = Vector3.ZERO
	facing = 1
	visual.rotation.y = 0.0
	state = "idle"
	jump_buffer = 0.0
	action_time = 0.0
	visual.show()
	locomotion.release_feet()
	springs.reset()
	_play("wait", 0.0)

func _prepare_materials() -> void:
	for surface in range(body_mesh.mesh.get_surface_count()):
		var original := body_mesh.get_active_material(surface).duplicate() as BaseMaterial3D
		original.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		original_body_materials.append(original)
		var toon := original.duplicate() as BaseMaterial3D
		# Keep texture colors visible while retaining a small lit contribution.
		# The original PBR maps remain available for an immediate A/B comparison.
		toon.albedo_color = Color(0.45,0.45,0.45,1)
		toon.metallic = 0.0
		toon.roughness = 0.9
		toon.normal_scale = 0.15
		toon.metallic_specular = 0.15
		toon.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		toon.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		toon.disable_receive_shadows = true
		toon.emission_enabled = true
		toon.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		toon.emission = Color.WHITE
		toon.emission_texture = original.albedo_texture
		toon.emission_energy_multiplier = 0.65
		toon_body_materials.append(toon)
		body_mesh.set_surface_override_material(surface,toon)

func toggle_material_style() -> void:
	cartoon_materials = not cartoon_materials
	for surface in range(body_mesh.mesh.get_surface_count()):
		body_mesh.set_surface_override_material(surface,toon_body_materials[surface] if cartoon_materials else original_body_materials[surface])
	skirt_material.shader = skirt_toon_shader if cartoon_materials else skirt_pbr_shader
	skirt_material.set_shader_parameter("rendering_style",1 if cartoon_materials else 0)
	skirt_material.set_shader_parameter("cloth_lag",cloth_lag)
	_update_skirt()

func _setup_skirt() -> void:
	var source := skirt.get_active_material(0) as BaseMaterial3D
	var mesh := ArrayMesh.new()
	for surface in range(skirt.mesh.get_surface_count()):
		var arrays := skirt.mesh.surface_get_arrays(surface)
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	skirt.mesh = mesh
	skirt.skin = null
	skirt.skeleton = NodePath("")
	var waist := BoneAttachment3D.new()
	waist.bone_name = "Pelvis"
	skeleton.add_child(waist)
	waist.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Pelvis"))
	skirt.reparent(waist, true)
	skirt_material = ShaderMaterial.new()
	skirt_pbr_shader = load("res://skirt_collision.gdshader")
	skirt_toon_shader = Shader.new()
	skirt_toon_shader.code = skirt_pbr_shader.code.replace("render_mode cull_disabled;","render_mode cull_disabled, diffuse_toon, specular_disabled, shadows_disabled;")
	skirt_material.shader = skirt_toon_shader if cartoon_materials else skirt_pbr_shader
	skirt_material.set_shader_parameter("rendering_style",1 if cartoon_materials else 0)
	skirt_material.set_shader_parameter("collision_enabled",true)
	skirt_material.set_shader_parameter("albedo_map", source.albedo_texture)
	skirt_material.set_shader_parameter("normal_map", source.normal_texture)
	skirt_material.set_shader_parameter("metal_rough_map", source.roughness_texture)
	skirt_material.set_shader_parameter("albedo_tint", source.albedo_color)
	skirt.material_override = skirt_material
	skirt.custom_aabb = AABB(Vector3(-0.7, -0.15, -0.65), Vector3(1.4, 1.5, 1.3))

func _build_hair() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/secondary_rig.json"))
	springs = SpringBoneSimulator3D.new()
	springs.name = "HairSecondaryMotion"
	skeleton.add_child(springs)
	var chains: Array = config.chains.filter(func(chain: Dictionary): return chain.kind == "hair")
	springs.setting_count = chains.size()
	for i in range(chains.size()):
		springs.set_root_bone_name(i, chains[i].root)
		springs.set_end_bone_name(i, chains[i].end)
		springs.set_center_from(i, SpringBoneSimulator3D.CENTER_FROM_BONE)
		springs.set_center_bone_name(i, "Root")
		springs.set_stiffness(i, 0.75)
		springs.set_drag(i, 0.65)
		springs.set_gravity(i, 0.0)
		springs.set_radius(i, 0.007)
		springs.set_enable_all_child_collisions(i, true)
	for collider: Dictionary in config.colliders:
		var capsule := SpringBoneCollisionCapsule3D.new()
		springs.add_child(capsule)
		capsule.bone_name = collider.bone
		var a := Vector3(collider.head[0], collider.head[2], -collider.head[1])
		var b := Vector3(collider.tail[0], collider.tail[2], -collider.tail[1])
		var rest := skeleton.get_bone_global_rest(skeleton.find_bone(collider.bone))
		capsule.radius = 0.05 if str(collider.bone).contains("Thigh") else float(collider.radius)
		capsule.height = a.distance_to(b) + capsule.radius * 2.0
		capsule.position_offset = rest.affine_inverse() * skeleton.to_local((a+b) * 0.5)
		var rotation := (skeleton.global_basis * rest.basis).get_rotation_quaternion()
		capsule.rotation_offset = rotation.inverse() * Quaternion(Vector3.UP, (b-a).normalized())

func _update_skirt() -> void:
	for side in ["L", "R"]:
		var prefix := "thigh_l_" if side == "L" else "thigh_r_"
		for item in [["Thigh", "head"], ["Calf", "tail"]]:
			var bone := skeleton.find_bone(side + "_" + item[0])
			var point := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			skirt_material.set_shader_parameter(prefix + item[1], point)
		var foot := skeleton.find_bone(side + "_Foot")
		skirt_material.set_shader_parameter("calf_l_tail" if side == "L" else "calf_r_tail", skeleton.global_transform * skeleton.get_bone_global_pose(foot).origin)
