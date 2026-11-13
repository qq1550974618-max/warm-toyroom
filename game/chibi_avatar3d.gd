extends "res://ball_controller.gd"

var chibi_meshes: Array[MeshInstance3D] = []
var material_rows: Array[Dictionary] = []
var chibi_config: Dictionary
var projectile_height := 0.35
var chibi_walk_speed := 1.35
var chibi_run_speed := 2.80
var fit_modifier: SkeletonModifier3D
var head_collision_shape: CollisionShape3D
var blink_driver:Node
var ground_fold:Node
var pose_recovery_count:=0

func restore_action_pose() -> void:
	# Re-sample an authored neutral pose at action boundaries, including bones
	# with no track in the next clip. Do not change the rig or the player's head offset.
	if skeleton==null or player==null:return
	player.stop();skeleton.clear_bones_global_pose_override();skeleton.reset_bone_poses()
	player.play("anime/wait",0);player.speed_scale=1;player.advance(0)
	locomotion.release_feet()
	if springs!=null:springs.reset()
	for modifier in skeleton.get_children():
		if modifier.has_method("reset_transient_pose"):modifier.reset_transient_pose()
	pose_recovery_count+=1

var appearance_settings := {"character_brightness": 1.0, "hair_layers": 0.79, "hair_shine": 0.50, "head_drop_mm": 16.0, "head_back_mm": 12.0}
const HAIR_PARTS := [2, 5, 8, 9, 12, 13, 15, 19, 22, 23, 24, 31, 34, 55]
static var repaired_hair_meshes:Dictionary={}

func setup(view_camera: Camera3D) -> void:
	_configure_controller()
	camera = view_camera
	name = "Player"
	collision_layer = 2
	collision_mask = 71
	platform_floor_layers = 0xFFFFFFFF & ~64
	floor_snap_length = 0.12
	floor_max_angle = deg_to_rad(46)
	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	# One continuous rounded silhouette has no neck ledge to hang on block edges.
	capsule.radius = 0.245
	capsule.height = 0.94
	body.shape = capsule
	body.position = Vector3(0, 0.47, 0)
	add_child(body)
	var head_collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.20
	head_collision.shape = sphere
	head_collision.position = Vector3(0.055, 0.68, 0)
	head_collision.free()
	floor_block_on_wall = true
	wall_min_slide_angle = 0.0
	max_slides = 8
	visual = (load("res://assets/character.glb") as PackedScene).instantiate()
	add_child(visual)
	_find_chibi_nodes(visual)
	assert(player != null and skeleton != null and chibi_meshes.size() == 62)
	assert(skeleton.get_bone_count() == 93)
	_repair_hair_seam()
	chibi_config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/chibi_rig_config.json"))
	_prepare_chibi_animations()
	_prepare_chibi_materials()
	locomotion = load("res://toy_locomotion.gd").new()
	locomotion.name = "ChibiFootContacts"
	skeleton.add_child(locomotion)
	locomotion.initialize(self, camera)
	fit_modifier = load("res://chibi_fit_modifier.gd").new()
	fit_modifier.name = "AdjustableNeckFit"
	skeleton.add_child(fit_modifier)
	apply_appearance_settings(appearance_settings)
	_build_hair()
	blink_driver=load("res://blink_driver.gd").new();add_child(blink_driver);blink_driver.setup(self)
	if ResourceLoader.exists("res://assets/character_ground_fold.glb") and not OS.get_cmdline_user_args().has("--build-fold"):
		ground_fold=load("res://ground_fold_visual.gd").new();add_child(ground_fold);ground_fold.setup(self)
	visual.rotation.y = 0
	_play("wait", 0)
	player.advance(0)
	process_priority = 0
	print("CHIBI_READY ", JSON.stringify({"bones": skeleton.get_bone_count(), "meshes": chibi_meshes.size(), "clips": animation_names.keys(), "new_binding": true}))

func _find_chibi_nodes(node: Node) -> void:
	if node is AnimationPlayer: player = node
	if node is Skeleton3D: skeleton = node
	if node is MeshInstance3D:
		chibi_meshes.append(node)
		if str(node.name).begins_with("QPart_56"): body_mesh = node
		if str(node.name).begins_with("QPart_01"): skirt = node
	for child in node.get_children(): _find_chibi_nodes(child)

func _repair_hair_seam() -> void:
	# Two hair triangles and the adjacent headpiece triangle have corrupted
	# first-vertex heights (near 1e-38), creating a vertical sliver over the hair.
	# Their exact duplicate vertices retain the authored point and skin weights.
	# Restore only these three points in a shared runtime copy; never edit the GLB,
	# remesh the hair, change UVs, or add a per-frame repair operation.
	for mi in chibi_meshes:
		var part=int(str(mi.name).split("_")[1])
		if part not in [2,8,35]:continue
		if repaired_hair_meshes.has(part):mi.mesh=repaired_hair_meshes[part];continue
		var source=mi.mesh
		var a=source.surface_get_arrays(0);var v:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
		if absf(v[0].y)>.000001:continue
		var donor=-1
		for i in range(1,v.size()):
			if v[i].y>.4 and v[i].y<.9 and Vector2(v[i].x-v[0].x,v[i].z-v[0].z).length_squared()<.000000000001:
				donor=i;break
		# The adjacent lace corner has no welded duplicate. Its nearest original
		# surface point is only 1.24 mm away; use its height while retaining X/Z.
		var exact=donor>=0
		if donor<0 and part==35:
			var best=.003*.003
			for i in range(1,v.size()):
				var d=Vector2(v[i].x-v[0].x,v[i].z-v[0].z).length_squared()
				if v[i].y>.65 and v[i].y<.75 and d<best:best=d;donor=i
		if donor<0:continue
		v[0]=v[donor] if exact else Vector3(v[0].x,v[donor].y,v[0].z);a[Mesh.ARRAY_VERTEX]=v
		for channel in [Mesh.ARRAY_NORMAL]:
			var values=a[channel]
			if values!=null:values[0]=values[donor];a[channel]=values
		for channel in [Mesh.ARRAY_TANGENT,Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS]:
			var values=a[channel]
			if values==null:continue
			var stride=values.size()/v.size()
			for k in stride:values[k]=values[donor*stride+k]
			a[channel]=values
		var patched=ArrayMesh.new()
		for si in source.get_surface_count():
			patched.add_surface_from_arrays(source.surface_get_primitive_type(si),a if si==0 else source.surface_get_arrays(si))
			patched.surface_set_material(si,source.surface_get_material(si))
		patched.set_meta("hair_seam_repaired_vertex_count",1)
		patched.set_meta("hair_seam_donor",donor)
		repaired_hair_meshes[part]=patched;mi.mesh=patched

func _prepare_chibi_animations() -> void:
	var clips := {}
	for source_name in player.get_animation_list():
		var key := str(source_name).get_file().get_slice("|", 1) if str(source_name).contains("|") else str(source_name).get_file()
		if key.to_upper() == "RESET": continue
		var clip := player.get_animation(source_name).duplicate(true) as Animation
		clip.loop_mode = Animation.LOOP_LINEAR if key in ["wait", "walk", "run", "run_neutral", "fall_air", "pistol_idle"] else Animation.LOOP_NONE
		if key=="wait":
			for track in range(clip.get_track_count()-1,-1,-1):
				if "Skirt_" in str(clip.track_get_path(track)):clip.remove_track(track)
		clips[key] = clip
	for library_name in player.get_animation_library_list(): player.remove_animation_library(library_name)
	var game_library := AnimationLibrary.new()
	for key in clips:
		game_library.add_animation(key, clips[key])
		animation_names[key] = "game/" + key
	player.add_animation_library("game", game_library)
	var anime := AnimationLibrary.new()
	for key in ["wait", "walk", "run", "jump", "land", "fall_air"]: anime.add_animation(key, clips[key])
	var motion_info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/chibi_motion_info.json"))
	source_root_speed = float(motion_info.run_reference_speed)
	anime_root_speed = source_root_speed
	generic_root_speed = source_root_speed
	anime.set_meta("walk_reference_speed", float(motion_info.walk_reference_speed))
	anime.set_meta("run_reference_speed", source_root_speed)
	player.add_animation_library("anime", anime)
	var free := AnimationLibrary.new()
	for key in ["cast", "hurt", "victory"]: free.add_animation(key, clips[key])
	player.add_animation_library("free", free)
	var extra := AnimationLibrary.new()
	extra.add_animation("run_styled", clips.run)
	extra.add_animation("run_neutral", clips.run_neutral)
	for key in ["jump", "land", "fall_air", "pistol_idle", "pistol_shoot", "pistol_reload"]: extra.add_animation(key, clips[key])
	extra.set_meta("run_reference_speed", source_root_speed)
	extra.set_meta("neutral_reference_speed", source_root_speed * 0.64 / 0.70)
	player.add_animation_library("extra", extra)
	extra_motion_set = true
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS

func _prepare_chibi_materials() -> void:
	for mesh in chibi_meshes:
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_active_material(surface).duplicate() as BaseMaterial3D
			original.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var toon := original.duplicate() as BaseMaterial3D
			toon.albedo_color = Color(0.45, 0.45, 0.45, 1)
			toon.metallic = 0
			toon.roughness = 0.90
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
			if original.albedo_texture == null:
				toon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				toon.albedo_color = original.albedo_color
				toon.emission_enabled = false
			var part := int(str(mesh.name).split("_")[1]) if str(mesh.name).begins_with("QPart_") else -1
			material_rows.append({"mesh": mesh, "surface": surface, "pbr": original, "toon": toon, "hair": part in HAIR_PARTS,
				"base_pbr_color": original.albedo_color, "base_pbr_emission": original.emission_energy_multiplier,
				"base_pbr_roughness": original.roughness, "base_pbr_normal": original.normal_scale, "base_pbr_specular": original.metallic_specular})
			mesh.set_surface_override_material(surface, toon)

func toggle_material_style() -> void:
	cartoon_materials = not cartoon_materials
	for row in material_rows:
		row.mesh.set_surface_override_material(row.surface, row.toon if cartoon_materials else row.pbr)

func apply_appearance_settings(settings: Dictionary) -> void:
	var previous_drop := float(appearance_settings.head_drop_mm)
	var previous_back := float(appearance_settings.head_back_mm)
	appearance_settings.merge(settings, true)
	var brightness := float(appearance_settings.character_brightness)
	var layers := float(appearance_settings.hair_layers)
	var shine := float(appearance_settings.hair_shine)
	for row in material_rows:
		var toon: BaseMaterial3D = row.toon
		var pbr: BaseMaterial3D = row.pbr
		pbr.albedo_color = row.base_pbr_color * Color(brightness, brightness, brightness, 1)
		if toon.albedo_texture == null:
			toon.albedo_color = row.base_pbr_color * Color(brightness, brightness, brightness, 1)
			continue
		var lit_amount := lerpf(0.45, 0.66, layers) if row.hair else 0.45
		toon.albedo_color = Color(lit_amount * brightness, lit_amount * brightness, lit_amount * brightness, 1)
		toon.emission_energy_multiplier = (lerpf(0.65, 0.44, layers) if row.hair else 0.65) * brightness
		if row.hair:
			pbr.roughness = lerpf(float(row.base_pbr_roughness), 0.78, layers)
			pbr.normal_scale = lerpf(float(row.base_pbr_normal), 0.55, layers)
			pbr.metallic_specular = lerpf(float(row.base_pbr_specular), shine * 0.40, layers)
			toon.normal_scale = lerpf(0.15, 0.36, layers)
			toon.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX if shine > 0 else BaseMaterial3D.SPECULAR_DISABLED
			toon.metallic_specular = shine * 0.40
			toon.roughness = lerpf(0.88, 0.58, shine)
			toon.rim_enabled = layers > 0
			toon.rim = layers * 0.20
			toon.rim_tint = 0.3
			toon.disable_receive_shadows = layers < 0.20
	if fit_modifier != null: fit_modifier.head_drop_m = float(appearance_settings.head_drop_mm) / 1000.0
	if fit_modifier != null: fit_modifier.head_back_m = float(appearance_settings.head_back_mm) / 1000.0
	if head_collision_shape != null: head_collision_shape.position.y = 0.68 - float(appearance_settings.head_drop_mm) / 1000.0
	if head_collision_shape != null: head_collision_shape.position.x = 0.055 - float(appearance_settings.head_back_mm) / 1000.0
	if springs != null and (not is_equal_approx(previous_drop, float(appearance_settings.head_drop_mm)) or not is_equal_approx(previous_back, float(appearance_settings.head_back_mm))): springs.reset()

func _build_hair() -> void:
	springs = SpringBoneSimulator3D.new()
	springs.name = "ChibiHairSecondaryMotion"
	skeleton.add_child(springs)
	var chains: Array = chibi_config.hair_chains.slice(0, 6)
	springs.setting_count = chains.size()
	for i in range(chains.size()):
		var chain: Array = chains[i].bones
		springs.set_root_bone_name(i, chain[0])
		springs.set_end_bone_name(i, chain[-1])
		springs.set_center_from(i, SpringBoneSimulator3D.CENTER_FROM_BONE)
		springs.set_center_bone_name(i, "Root")
		springs.set_stiffness(i, 0.92)
		springs.set_drag(i, 0.82)
		springs.set_gravity(i, 0)
		springs.set_radius(i, 0.008)
		springs.set_enable_all_child_collisions(i, true)
	var body_guard := SpringBoneCollisionCapsule3D.new()
	springs.add_child(body_guard)
	body_guard.bone_name = "Waist"
	body_guard.radius = 0.072
	body_guard.height = 0.20
	body_guard.position_offset = Vector3(0, 0.018, 0)

func _update_skirt() -> void:
	# The new skirt keeps its own skin and eight bone chains. No adult-body
	# shader reparenting or former weights are applied to this rig.
	pass
