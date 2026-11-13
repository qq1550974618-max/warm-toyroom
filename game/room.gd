extends Node3D

var actor: CharacterBody3D
var camera: Camera3D
var environment: Environment
var attributes: CameraAttributesPractical
var gi: VoxelGI
var lightmap:LightmapGI
var sun: DirectionalLight3D
var room: Node3D
var hud: CanvasLayer
var title: Label
var objective: Label
var hint: Label
var toast: Label
var diagnostics: Label
var diagnostics_interval:=0.0
var collected := 0
var stars: Array[Node3D] = []
var star_positions := [Vector3(1.05,0.48,0),Vector3(2.905,0.89,-1.75),Vector3(3.85,1.09,-2.66)]
var elapsed := 0.0
var toast_time := 0.0
var camera_yaw := 0.257
var camera_pitch := 0.20
var camera_distance := 3.94
var camera_focus := Vector3(0,0.30,1.7)
var dragging := false
var overview := false
var paused := false
var ready_to_play := false
var finished := false
var victory_time := 0.0
var sounds_enabled := true
var music_light: OmniLight3D
var audio_player: AudioStreamPlayer
var last_land_count := 0
var last_foot_events := 0
var step_cooldown := 0.0
var start_position := Vector3(0,0.04,1.7)
var music_box_point:=Vector3(3.885,1.162,-3.99)
var ambient_dust: MultiMeshInstance3D
var dust_origins: Array[Vector3] = []
var contact_shadow: Decal
var detail_review_camera := false
var physics_props:Array[RigidBody3D]=[]
var physics_cushions:Array[RigidBody3D]=[]
var mouse_look_enabled:=true
var automated:=false
var light_controls:CanvasLayer
var resolution=preload("res://render_resolution.gd").new()
var quality_surfaces=preload("res://quality_surfaces.gd").new()
var prop_interaction:Node
var companion:CharacterBody3D
var iron_ball:RigidBody3D
var playground:Node3D
var companion_controls:CanvasLayer
var train:Node3D
var paper_plane:RigidBody3D
var plane_assist:Node
var pause_menu:CanvasLayer
var head_adjustment:SkeletonModifier3D
var mouse_house:Node3D
var puzzles:Node3D
var art=preload("res://toy_art_direction.gd").new()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_title("鲸鱼女仆 · 暖光玩具房 V30")
	if not OS.has_feature("web"):Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	_bind_inputs()
	_build_room()
	_refine_collisions()
	preload("res://v17_scene_refinement.gd").new().apply(self)
	mouse_house=preload("res://mouse_house.gd").new();mouse_house.room=self;add_child(mouse_house)
	_build_lighting()
	_build_camera()
	_build_character()
	prop_interaction=preload("res://prop_interaction.gd").new();prop_interaction.room=self;add_child(prop_interaction)
	head_adjustment=preload("res://head_adjustment.gd").new();head_adjustment.name="HeadPositionAdjustment";head_adjustment.actor=actor;actor.skeleton.add_child(head_adjustment)
	actor.skeleton.move_child(head_adjustment,prop_interaction.pose.get_index()+1)
	_build_playmates()
	train=preload("res://toy_train.gd").new();train.room=self;add_child(train)
	paper_plane=preload("res://paper_plane.gd").new();paper_plane.room=self;paper_plane.position=Vector3(-2.26,.15,1.30);paper_plane.rotation.y=-.20;add_child(paper_plane);physics_props.append(paper_plane)
	plane_assist=preload("res://plane_assist.gd").new();plane_assist.room=self;add_child(plane_assist)
	star_positions.append(Vector3(3.85,5.12,-5.75));star_positions.append(Vector3(-4.04,3.24,-3.35))
	star_positions.remove_at(1) # Remove the old middle book-route star.
	star_positions.remove_at(1) # Five-star route: keep the entry, desk, glide destination, lift and paired-button reward.
	_build_route()
	_build_ui()
	light_controls=preload("res://light_controls.gd").new();light_controls.room=self;add_child(light_controls)
	_build_dust()
	audio_player=AudioStreamPlayer.new();add_child(audio_player);audio_player.volume_db=-19
	AudioServer.set_bus_volume_db(0,0)
	if AudioServer.get_bus_effect_count(0)==0:
		var gain:=AudioEffectAmplify.new();gain.volume_db=linear_to_db(3.0);AudioServer.add_bus_effect(0,gain)
		AudioServer.add_bus_effect(0,AudioEffectLimiter.new())
	playground=preload("res://rice_seesaw.gd").new();playground.room=self;add_child(playground)
	companion_controls=preload("res://companion_controls.gd").new();companion_controls.room=self;add_child(companion_controls)
	pause_menu=preload("res://pause_menu.gd").new();pause_menu.room=self;add_child(pause_menu)
	for person in [actor,companion]:
		var forelock=preload("res://forelock_contact.gd").new();forelock.name="ForelockElasticContact";forelock.actor=person;forelock.room=self;person.skeleton.add_child(forelock)
		var cloth=person.skeleton.get_node_or_null("LegClothContact")
		if cloth!=null:person.skeleton.move_child(cloth,-1)
	preload("res://v18_surface_library.gd").new().apply(self)
	quality_surfaces.bind(self)
	quality_surfaces.apply(light_controls.is_ultra())
	puzzles=preload("res://mini_puzzles.gd").new();puzzles.room=self;add_child(puzzles)
	_refresh_star_counter()
	resolution.bind(self)
	_initialize_gi.call_deferred()

func _refine_collisions() -> void:
	for pair in [["AlphabetBlocks","alphabet_blocks"],["FloorCushions","floor_cushions"],["FloorDetails","floor_details"]]:
		var root_node:Node3D=room.get_node("Props/"+pair[0])
		if root_node.has_node("V16SolidSurfaces"):continue
		for mesh in root_node.find_children("*","MeshInstance3D",true,false):
			# Keep other furnishings which share an old material-group module.
			if pair[0]=="FloorCushions" and not ("Soft cotton" in str(mesh.name) or "Walnut" in str(mesh.name)):continue
			if pair[0]=="FloorDetails" and not "Woven dusty teal_001" in str(mesh.name):continue
			for body in mesh.find_children("*","StaticBody3D",true,false):body.free()
		root_node.add_child(load("res://room_kit/scenes/solid_"+pair[1]+".tscn").instantiate())
		if pair[0]=="AlphabetBlocks":
			# Include projecting letter frames and the doll's visible hair clearance.
			# Keep exact top/bottom heights so jumping/stacking remain unchanged.
			for contact in root_node.find_children("*","CollisionShape3D",true,false):
				if contact.shape is ConvexPolygonShape3D:
					var copy=contact.shape.duplicate();var points=copy.points;var centre=Vector3.ZERO
					for point in points:centre+=point
					centre/=points.size()
					for i in points.size():
						var d=points[i]-centre;d.y=0;points[i]+=d.normalized()*.050
					copy.points=points;contact.shape=copy


func _bind_inputs() -> void:
	var bindings={"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"move_forward":[KEY_W,KEY_UP],"move_back":[KEY_S,KEY_DOWN],"jump":[KEY_SPACE],"sprint":[KEY_SHIFT],"roll":[KEY_CTRL,KEY_Q],"cast":[],"interact":[KEY_E]}
	for key in bindings:
		if not InputMap.has_action(key):InputMap.add_action(key)
		for code in bindings[key]:
			var event:=InputEventKey.new();event.physical_keycode=code;InputMap.action_add_event(key,event)

func _build_room() -> void:
	room=get_node_or_null("Room")
	if room==null:room=load("res://levels/toy_room_layout.tscn").instantiate();room.name="Room";add_child(room)
	_prepare_environment_meshes(room)
	start_position=room.get_node("Targets/PlayerSpawn").position;music_box_point=room.get_node("Targets/MusicBox").position
	for body in room.find_children("*","RigidBody3D",true,false):
		if body.get_meta("physics_cushion",false):physics_cushions.append(body);body.set_meta("spawn_transform",body.global_transform)
	for i in range(3):star_positions[i]=room.get_node("Targets/Star%d"%(i+1)).position
	var rows:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/physics_props.json"))
	for row in rows:
		var body:RigidBody3D=preload("res://toy_prop_body.gd").new();body.name=row.name;body.mass=row.mass;body.collision_layer=4;body.collision_mask=7;body.continuous_cd=true
		body.position=Vector3(row.position[0],row.position[1],row.position[2]);body.linear_damp=.35;body.angular_damp=.45
		var pm:=PhysicsMaterial.new();pm.friction=.24 if row.kind=="marble" else (.78 if row.kind=="reel" else .66)
		pm.bounce=.38 if row.kind=="marble" else (.09 if row.kind=="reel" else .12);body.physics_material_override=pm
		body.angular_damp=.18 if row.kind=="marble" else (.70 if row.kind=="reel" else .45)
		add_child(body);var model=load("res://assets/"+str(row.asset)).instantiate();body.add_child(model)
		var shape:=CollisionShape3D.new()
		if row.kind=="marble":
			var sphere:=SphereShape3D.new();sphere.radius=float(row.size[0])*.5;shape.shape=sphere
		elif row.kind=="reel":
			var cylinder:=CylinderShape3D.new();cylinder.radius=.19;cylinder.height=float(row.size[1]);shape.shape=cylinder
		else:
			var points:=PackedVector3Array();_collect_prop_vertices(model,Transform3D.IDENTITY,points)
			var hull:=ConvexPolygonShape3D.new();hull.points=points;shape.shape=hull
		body.add_child(shape);body.set_meta("kind",row.kind);body.set_meta("prop_size",Vector3(row.size[0],row.size[1],row.size[2]));body.set_meta("display_name","弹珠" if row.kind=="marble" else ("线轴" if row.kind=="reel" else "铅笔"));body.set_meta("spawn_transform",body.transform);physics_props.append(body);_prepare_prop_meshes(model)
	var chicken=preload("res://chicken_toy.gd").new();chicken.room=self;chicken.position=Vector3(3.85,4.934,-5.23);chicken.rotation.y=-.4;add_child(chicken);physics_props.append(chicken)

func _collect_prop_vertices(node:Node,transform:Transform3D,points:PackedVector3Array) -> void:
	if node is Node3D:transform=transform*node.transform
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			for point in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:points.append(transform*point)
	for child in node.get_children():_collect_prop_vertices(child,transform,points)

func _prepare_prop_meshes(node:Node) -> void:
	if node is MeshInstance3D:
		node.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
		for i in node.mesh.get_surface_count():
			var m=node.get_active_material(i)
			if m is BaseMaterial3D and not node.get_meta("v12_pencil_style",false):node.set_surface_override_material(i,art.room_material(m))
	for child in node.get_children():_prepare_prop_meshes(child)

func _prepare_environment_meshes(node: Node) -> void:
	if node.get_meta("dynamic_relocated_prop",false):_prepare_prop_meshes(node);return
	if node is MeshInstance3D:
		if str(node.name)=="Window sky":node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;return
		node.gi_mode=GeometryInstance3D.GI_MODE_STATIC
		var cloth_collision:=false
		for surface in range(node.mesh.get_surface_count()):
			var m=node.get_active_material(surface)
			if m is BaseMaterial3D:
				if m.resource_path.begins_with("res://room_kit/materials/"):continue
				m=m.duplicate();m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				m.cull_mode=BaseMaterial3D.CULL_BACK
				if "Window sky" in str(m.resource_name) or "Window sky" in str(node.name):
					node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
					m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=Color(1.0,.94,.79);m.emission_enabled=true;m.emission=Color(1.0,.91,.70);m.emission_energy_multiplier=5.0
				if "Oak" in str(m.resource_name):
					m.normal_scale=.30;m.roughness=.85;m.metallic_specular=.38
				if "lacquer" in str(m.resource_name):m.roughness=.68;m.metallic_specular=.25
				if "cloth" in str(m.resource_name) or "wool" in str(m.resource_name) or "linen" in str(m.resource_name):m.roughness=1.0;m.metallic_specular=.05;m.normal_scale=.18
				if "Woven" in str(m.resource_name) or "Soft cotton" in str(m.resource_name):cloth_collision=true
				node.set_surface_override_material(surface,art.room_material(m))
		if node.gi_mode!=GeometryInstance3D.GI_MODE_DISABLED and not node.get_meta("kit_collision_managed",false):node.create_trimesh_collision()
	for child in node.get_children():_prepare_environment_meshes(child)

func _build_lighting() -> void:
	preload("res://lighting_rig.gd").new().setup(self)

func _omni(label: String,point: Vector3,color: Color,energy: float,radius: float) -> OmniLight3D:
	var light:=OmniLight3D.new();light.name=label;light.position=point;light.light_color=color;light.light_energy=energy;light.omni_range=radius;light.omni_attenuation=1.5;light.light_volumetric_fog_energy=0;light.light_specular=0.0;light.light_bake_mode=Light3D.BAKE_DYNAMIC;light.shadow_enabled=true;light.light_size=1.0;add_child(light);return light

func _initialize_gi() -> void:
	await get_tree().process_frame
	if ResourceLoader.exists("res://assets/lightmaps/room_v8.lmbake"):
		var baked:LightmapGIData=load("res://assets/lightmaps/room_v8.lmbake")
		var missing:PackedStringArray=[]
		for user_index in baked.get_user_count():
			if lightmap.get_node_or_null(baked.get_user_path(user_index))==null:missing.append(str(baked.get_user_path(user_index)))
		if baked.get_user_count()>0 and not baked.lightmap_textures.is_empty() and missing.is_empty():
			lightmap.light_data=_probe_lit_thin_details(baked);gi.visible=false
			for lamp in get_children():
				if lamp is Light3D and lamp.name!="WindowSun" and lamp.name!="WindowFill":lamp.shadow_enabled=false
		elif not missing.is_empty():push_warning("Baked lighting unavailable; missing mesh paths: ",missing)
	if lightmap.light_data==null:
		gi.data=load("res://assets/room_gi_v4.res");lightmap.visible=false
	lightmap.specular_intensity=.55
	if light_controls!=null:light_controls.history.sync_baked_shadows();light_controls.apply_values()
	await prop_interaction.warmup_visuals()
	ready_to_play=true;actor.can_control=true
	_show_toast("寻找星光，探索墙后的小屋 · Alt 切换同伴",5)
	print("ROOM_READY visual_scale=0.405 lightmap=",lightmap.light_data!=null," gi_fallback=",gi.visible)

func _probe_lit_thin_details(source:LightmapGIData) -> LightmapGIData:
	# Sub-texel seams and two-sided paper cannot represent both sides in one texel.
	# They still cast shadows, but receive the baked probe field and live direct light.
	var result:LightmapGIData=source.duplicate()
	var users:Array=source.get("user_data")
	result.clear_users()
	var probe_count:=0
	for i in range(0,users.size(),4):
		var path:String=str(users[i]);var label:=path.to_lower();var thin:=false
		for keyword in ["cloth","cotton","paper","page","thread","linen","wool","felt","wicker","woven","mk_sage","mk_ivory","mk_brushed","mk_window","mk_linen","mk_cotton","mk_tieback"]:
			if keyword in label and not "rug" in label and not "mk_sage_painted_wood_field" in label:thin=true
		# The v8 bake resolves the reusable kit's cloth folds and mouldings.
		# Keep their own texels: probe interpolation was washing out this detail.
		if "mk_" in label:thin=false
		if "storybookstamp" in label:thin=true
		if "mk_tieback" in label:thin=true
		if thin:
			var mesh:=lightmap.get_node_or_null(users[i]) as MeshInstance3D
			if mesh!=null:mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;probe_count+=1
		else:result.add_user(users[i],users[i+1],users[i+2],users[i+3])
	print("LIGHTING_BINDINGS lightmapped=",result.get_user_count()," probe_lit_details=",probe_count)
	return result

func _build_camera() -> void:
	camera=Camera3D.new();camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;camera.name="ToyHeightCamera";camera.fov=38;camera.near=.025;camera.far=60;add_child(camera)
	attributes=CameraAttributesPractical.new();attributes.dof_blur_far_enabled=true;attributes.dof_blur_far_distance=5.4;attributes.dof_blur_far_transition=3.8;attributes.dof_blur_amount=.09
	attributes.dof_blur_near_enabled=true;attributes.dof_blur_near_distance=1.7;attributes.dof_blur_near_transition=1.0
	camera.attributes=attributes;camera.current=true
	_update_camera(1.0)

func _build_character() -> void:
	actor=load("res://playground_avatar.gd").new();add_child(actor);actor.setup(camera);actor.game=self
	actor.process_mode=Node.PROCESS_MODE_PAUSABLE
	actor.visual_scale=.405;actor.visual.scale=Vector3.ONE*actor.visual_scale
	for c in actor.get_children():
		if c is CollisionShape3D:
			c.position*=actor.visual_scale
			c.shape=c.shape.duplicate()
			if c.shape is CapsuleShape3D:c.shape.radius*=actor.visual_scale;c.shape.height*=actor.visual_scale
			if c.shape is SphereShape3D:c.shape.radius*=actor.visual_scale
	actor.floor_snap_length=.05265;actor.safe_margin=.001
	actor.spawn_point=start_position;actor.position=start_position;actor.spawn_heading=-1.02;actor.heading_yaw=-1.02;actor.visual.rotation.y=-1.02
	actor.toggle_material_style()
	art.character(actor)
	if actor.ground_fold!=null:actor.ground_fold.prepare_materials()
	actor.can_control=false
	var gradient:=Gradient.new();gradient.offsets=PackedFloat32Array([0,.25,.65,1]);gradient.colors=PackedColorArray([Color(.035,.028,.02,.50),Color(.035,.028,.02,.32),Color(.035,.028,.02,.10),Color(.035,.028,.02,0)])
	var texture:=GradientTexture2D.new();texture.gradient=gradient;texture.width=128;texture.height=128;texture.fill=GradientTexture2D.FILL_RADIAL;texture.fill_from=Vector2(.5,.5);texture.fill_to=Vector2(.5,0)
	contact_shadow=Decal.new();contact_shadow.name="Soft ground contact";contact_shadow.texture_albedo=texture;contact_shadow.cull_mask=1;contact_shadow.size=Vector3(.34,.32,.29)*.81;contact_shadow.lower_fade=.1;contact_shadow.upper_fade=.1;add_child(contact_shadow)

func _build_route() -> void:
	for i in range(star_positions.size()):
		var root:=Node3D.new();root.name="Star"+str(i+1);root.position=star_positions[i];add_child(root);stars.append(root)
		var star:=MeshInstance3D.new();star.mesh=_star_mesh();star.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;root.add_child(star)
		var m:=StandardMaterial3D.new();m.albedo_color=Color(.96,.63,.16);m.metallic=.7;m.roughness=.24;m.emission_enabled=true;m.emission=Color(1,.57,.13);m.emission_energy_multiplier=1.1;star.material_override=m
		star.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light:=OmniLight3D.new();light.light_color=Color(1,.63,.23);light.light_energy=.14;light.omni_range=.75;root.add_child(light)
	music_light=_omni("Music box glow",music_box_point+Vector3.UP*.258,Color(1,.61,.17),0,2.2);music_light.light_bake_mode=Light3D.BAKE_DISABLED

func _star_mesh() -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		for i in range(10):
			var a:=TAU*i/10.0;var b:=TAU*(i+1)/10.0;var ra:=.085 if i%2==0 else .039;var rb:=.085 if (i+1)%2==0 else .039
			var pa:=Vector3(sin(a)*ra,cos(a)*ra,side*.012);var pb:=Vector3(sin(b)*rb,cos(b)*rb,side*.012)
			st.add_vertex(Vector3(0,0,side*.012));st.add_vertex(pa if side>0 else pb);st.add_vertex(pb if side>0 else pa)
	st.generate_normals();return st.commit()

func _build_ui() -> void:
	hud=CanvasLayer.new();hud.transform=Transform2D.IDENTITY.scaled(Vector2(1.6,1.6));add_child(hud)
	var font:=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	var ui:=Control.new();ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.add_child(ui)
	title=_label(ui,Vector2(36,25),"暖光玩具房",27,font);title.modulate=Color(1,.90,.72)
	objective=_label(ui,Vector2(38,65),"",16,font)
	hint=_label(ui,Vector2(38,843),"Shift 快跑   空格 跳跃   按住 Ctrl / Q 滚动，松开滑停   F 拿起/放下   左键蓄力投掷   G 轨迹   E 扶住/松开铁球",16,font)
	var extra=_label(ui,Vector2(38,871),"Alt 换人   F2 全景   L 光线调节   F11 全屏   Tab 界面   R 复位   M 声音   Esc 暂停 / 释放鼠标",13,font);extra.modulate=Color(.82,.77,.65)
	toast=_label(ui,Vector2(460,790),"",19,font);toast.size=Vector2(700,40);toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	diagnostics=_label(ui,Vector2(1160,25),"",14,font);diagnostics.visible=false

func _label(parent: Node,point: Vector2,words: String,size: int,font: Font) -> Label:
	var label:=Label.new();label.position=point;label.text=words;label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",Color(.96,.92,.83));label.add_theme_color_override("font_shadow_color",Color(0,0,0,.85));label.add_theme_constant_override("shadow_offset_x",1);label.add_theme_constant_override("shadow_offset_y",2);label.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(label);return label

func _refresh_star_counter() -> void:
	# Count the live collectible registry, including the initially hidden button
	# reward. The first frame and all pickup updates use the same source.
	if objective!=null:objective.text="窗边的小小冒险    ·    星光  %d / %d"%[collected,stars.size()]

func _build_dust() -> void:
	ambient_dust=MultiMeshInstance3D.new();ambient_dust.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;ambient_dust.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
	var mesh:=QuadMesh.new();mesh.size=Vector2(.009,.009);mm.mesh=mesh;mm.instance_count=90;ambient_dust.multimesh=mm
	var gradient:=Gradient.new();gradient.offsets=PackedFloat32Array([0,.25,.7,1]);gradient.colors=PackedColorArray([Color(1,1,1,.65),Color(1,1,1,.48),Color(1,1,1,.10),Color(1,1,1,0)])
	var mote:=GradientTexture2D.new();mote.width=32;mote.height=32;mote.gradient=gradient;mote.fill=GradientTexture2D.FILL_RADIAL;mote.fill_from=Vector2(.5,.5);mote.fill_to=Vector2(.5,0)
	var m:=StandardMaterial3D.new();m.albedo_texture=mote;m.albedo_color=Color(.84,.77,.63,.6);m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	m.roughness=1;m.metallic_specular=0;m.cull_mode=BaseMaterial3D.CULL_DISABLED;m.backlight_enabled=true;m.backlight=Color(.15,.12,.07)
	ambient_dust.material_override=m;ambient_dust.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(ambient_dust)
	var rng:=RandomNumberGenerator.new();rng.seed=92
	for i in range(90):
		dust_origins.append(Vector3(rng.randf_range(-3.8,2.0),rng.randf_range(.3,4.8),rng.randf_range(-6,2)))
		mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,dust_origins[i]))

func _process(delta: float) -> void:
	if paused:return
	elapsed+=delta
	_update_camera(delta)
	for i in range(stars.size()):
		if not is_instance_valid(stars[i]) or not stars[i].visible:continue
		stars[i].position.y=star_positions[i].y+sin(elapsed*1.5+i)*.025;stars[i].rotation.y=elapsed*.65
		if actor!=null and ready_to_play and (actor.position+Vector3.UP*.25).distance_to(stars[i].position)<.27:
			stars[i].hide();collected+=1;_refresh_star_counter();_tone(600+collected*180,.22)
			_show_toast("找齐了！跳到音乐盒上，按 E 唤醒它" if collected==stars.size() else "星光 +1",4)
	toast_time=maxf(0,toast_time-delta);toast.modulate.a=minf(1,toast_time)
	if ambient_dust!=null:
		for i in range(dust_origins.size()):
			var p:=dust_origins[i]+Vector3(sin(elapsed*.11+i)*.12,sin(elapsed*.08+i*1.7)*.10,cos(elapsed*.1+i)*.12)
			ambient_dust.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,p))
	if actor!=null and ready_to_play:
		if actor.position.y < -2: _respawn()
		step_cooldown=maxf(0,step_cooldown-delta)
		var events:int=actor.locomotion.plant_events.L+actor.locomotion.plant_events.R
		if events>last_foot_events and actor.state in ["run","walk"] and step_cooldown<=0:_tone(130,.045,.35);step_cooldown=.11
		last_foot_events=events
		if actor.land_count>last_land_count:_tone(100,.09,.45);last_land_count=actor.land_count
		if finished and actor.state=="victory":
			victory_time+=delta
			if victory_time>2.1:actor.state="idle";actor.can_control=true
		music_light.light_energy=lerpf(music_light.light_energy,1.3 if finished else (.25 if collected==stars.size() else 0.0),delta*2)
		if diagnostics.visible:
			diagnostics_interval-=delta
			if diagnostics_interval<=0:
				diagnostics_interval=.25
				diagnostics.text="%d FPS\nFoot lock %.3f mm\n%s\nJump %d / Land %d"%[Engine.get_frames_per_second(),actor.locomotion.maximum_anchor_error*1000,actor.state,actor.jump_count,actor.land_count]

func _physics_process(delta: float) -> void:
	if actor!=null and contact_shadow!=null:
		var ray:=PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*.1,actor.position+Vector3.DOWN*1.6,1);ray.exclude=[actor.get_rid()]
		var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
		contact_shadow.visible=not hit.is_empty()
		if not hit.is_empty():
			var height:float=maxf(0,actor.position.y-hit.position.y)
			contact_shadow.position=Vector3(actor.position.x,hit.position.y+.06,actor.position.z);contact_shadow.rotation.y=actor.heading_yaw;contact_shadow.modulate.a=clampf(1-height*1.3,0,1)

func _update_camera(delta: float) -> void:
	if detail_review_camera:return
	if camera==null:return
	if train!=null and train.camera_active:
		var cab=train.carriage.get_global_transform_interpolated().origin
		var focus=cab+Vector3(-.05,.43,0)
		camera_focus=camera_focus.lerp(focus,1-exp(-delta*5.0))
		camera.position=camera.position.lerp(focus+Vector3(1.35,3.7,2.65),1-exp(-delta*3.8))
		var look=Transform3D.IDENTITY.looking_at(camera_focus-camera.position).basis.get_rotation_quaternion()
		camera.quaternion=camera.quaternion.slerp(look,1-exp(-delta*5.0))
		camera.fov=lerpf(camera.fov,48,1-exp(-delta*5))
		attributes.dof_blur_far_enabled=false;attributes.dof_blur_near_enabled=false
		return
	if puzzles!=null and puzzles.update_camera(delta):return
	if actor!=null:
		camera_focus=camera_focus.lerp(actor.get_global_transform_interpolated().origin+Vector3.UP*.30,1-exp(-delta*5.5))
	var desired: Vector3
	if overview:
		desired=Vector3(6.5,6.8,6.8);camera.position=camera.position.lerp(desired,1-exp(-delta*3.5));camera.look_at(Vector3(.25,1.0,-1.2));camera.fov=52;attributes.dof_blur_far_enabled=false;attributes.dof_blur_near_enabled=false
	else:
		var offset:=Vector3(sin(camera_yaw)*cos(camera_pitch),sin(camera_pitch),cos(camera_yaw)*cos(camera_pitch))*camera_distance
		desired=camera_focus+offset
		# Real room geometry prevents orbiting through furniture and walls.
		if actor!=null and ready_to_play:
			var ray:=PhysicsRayQueryParameters3D.create(camera_focus,desired,1);ray.exclude=[actor.get_rid()]
			var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty():desired=hit.position+(camera_focus-hit.position).normalized()*.14
		camera.position=camera.position.lerp(desired,1-exp(-delta*10));camera.look_at(camera_focus)
		camera.fov=38;attributes.dof_blur_far_enabled=true;attributes.dof_blur_near_enabled=true
		var distance:=camera.position.distance_to(camera_focus)
		attributes.dof_blur_far_distance=distance+1.15;attributes.dof_blur_near_distance=maxf(.2,distance-1.6)

	if playground!=null:playground.update_camera(delta)
	if light_controls!=null:
		attributes.dof_blur_amount=light_controls.effective_dof()
		if overview:
			var focus_distance:=camera.position.distance_to(Vector3(.25,1,-1.2))
			attributes.dof_blur_far_enabled=true;attributes.dof_blur_near_enabled=true
			attributes.dof_blur_far_distance=focus_distance+1.5;attributes.dof_blur_far_transition=5.0
			attributes.dof_blur_near_distance=focus_distance-3.0;attributes.dof_blur_near_transition=2.0

func _unhandled_input(event: InputEvent) -> void:
	if puzzles!=null and puzzles.book_open:
		puzzles.handle_input(event);return
	if paused and pause_menu!=null and pause_menu.overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_ESCAPE:pause_menu.resume();get_viewport().set_input_as_handled()
		return
	if companion_controls!=null and companion_controls.handle_key(event):return
	if light_controls!=null and light_controls.handle_key(event):return
	if paused:return
	if puzzles!=null and puzzles.handle_input(event):return
	if train!=null and train.handle_input(event):return
	if mouse_house!=null and mouse_house.door.handle_input(event):return
	if playground!=null and playground.handle_input(event):return
	if iron_ball!=null and iron_ball.handle_input(event):return
	if prop_interaction!=null and prop_interaction.handle_input(event):return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT and event.pressed and not paused:
			mouse_look_enabled=true
			if not automated:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:camera_distance=maxf(1.5,camera_distance-.25)
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:camera_distance=minf(7,camera_distance+.25)
	if event is InputEventMouseMotion and mouse_look_enabled and not overview and not paused:
		var motion:Vector2=resolution.logical_point(event.relative)
		camera_yaw-=motion.x*.0034;camera_pitch=clampf(camera_pitch+motion.y*.0028,.05,1.1)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				if not paused:_interact()
			KEY_TAB:
				hud.visible=not hud.visible
				light_controls.visible=hud.visible
				companion_controls.visible=hud.visible
			KEY_F2:overview=not overview
			KEY_F3:diagnostics.visible=not diagnostics.visible
			KEY_F11:get_window().mode=Window.MODE_WINDOWED if get_window().mode==Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
			KEY_R:_respawn()
			KEY_M:sounds_enabled=not sounds_enabled;_show_toast("声音开启" if sounds_enabled else "声音关闭",2)
			KEY_ESCAPE:
				if prop_interaction!=null:prop_interaction.cancel_charge()
				if paused:pause_menu.resume()
				else:pause_menu.show_pause()

func _interact() -> void:
	if iron_ball!=null and actor.position.distance_to(iron_ball.position)<1:return
	if actor.position.distance_to(music_box_point)>.85:return
	if collected<stars.size():_show_toast("音乐盒还在等待剩下的星光",3);return
	if finished:return
	finished=true;actor.celebrate();_show_toast("音乐盒醒来了 · 可以继续在房间里探索",7);objective.text="窗边的小小冒险    ·    已完成";_victory_song()

func _victory_song() -> void:
	for f in [523.25,659.25,783.99,1046.5]:
		_tone(f,.35);await get_tree().create_timer(.22).timeout

func _respawn() -> void:
	if actor==null:return
	if puzzles!=null:puzzles.reset_actions()
	if train!=null:train.reset_train()
	if plane_assist!=null:plane_assist.cancel()
	if paper_plane!=null:paper_plane.reset_plane()
	if companion_controls!=null:companion_controls.release_hold(false)
	if iron_ball!=null:
		iron_ball.stop_push();_teleport_prop(iron_ball,Transform3D(Basis.IDENTITY,Vector3(-.6,.27,2.9)))
	if prop_interaction!=null:prop_interaction.drop()
	actor.reset_position();actor.can_control=true;camera_focus=start_position+Vector3.UP*.30;_show_toast("回到地毯旁",2)
	if playground!=null:playground.reset_puzzle()
	for prop in physics_props:
		if prop.has_method("reset_plane"):prop.reset_plane()
		else:_teleport_prop(prop,prop.get_meta("spawn_transform"))
	for cushion in physics_cushions:
		var at:Transform3D=cushion.get_meta("reset_transform",cushion.get_meta("spawn_transform"));cushion.global_transform=at
		PhysicsServer3D.body_set_state(cushion.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,at)
		cushion.linear_velocity=Vector3.ZERO;cushion.angular_velocity=Vector3.ZERO;cushion.sleeping=cushion.has_meta("reset_transform");cushion.reset_physics_interpolation()

func _teleport_prop(prop:RigidBody3D,value:Transform3D) -> void:
	prop.global_transform=value
	PhysicsServer3D.body_set_state(prop.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,value)
	prop.linear_velocity=Vector3.ZERO;prop.angular_velocity=Vector3.ZERO;prop.sleeping=false;prop.reset_physics_interpolation()
	if prop.has_method("reset_contact_history"):prop.reset_contact_history()
	if prop.has_method("reset_overrun_tracking"):prop.reset_overrun_tracking()
	if prop.get_meta("heavy_push_only",false):prop.previous_position=value.origin;prop.previous_velocity=Vector3.ZERO

func _show_toast(message: String,seconds: float) -> void:
	if toast!=null:toast.text=message;toast_time=seconds

func aim_direction(fallback: Vector3) -> Vector3:return fallback

func _build_playmates() -> void:
	companion=load("res://playground_avatar.gd").new();add_child(companion);companion.setup(camera);companion.name="WhaleCompanion";companion.game=self;companion.process_mode=Node.PROCESS_MODE_PAUSABLE
	companion.visual_scale=actor.visual_scale;companion.visual.scale=Vector3.ONE*companion.visual_scale
	for c in companion.get_children():
		if c is CollisionShape3D:
			c.position*=companion.visual_scale;c.shape=c.shape.duplicate()
			if c.shape is CapsuleShape3D:c.shape.radius*=companion.visual_scale;c.shape.height*=companion.visual_scale
			if c.shape is SphereShape3D:c.shape.radius*=companion.visual_scale
	companion.floor_snap_length=actor.floor_snap_length;companion.safe_margin=.001;companion.position=Vector3(1.3,.05,3.7);companion.spawn_point=companion.position;companion.toggle_material_style();art.character(companion)
	if companion.ground_fold!=null:companion.ground_fold.prepare_materials()
	var mind=load("res://wander_companion.gd").new();mind.name="WanderMind";mind.actor=companion;mind.room=self;companion.add_child(mind)
	var cloth=load("res://skirt_contact.gd").new();cloth.name="LegClothContact";cloth.actor=companion;companion.skeleton.add_child(cloth)
	iron_ball=load("res://iron_ball.gd").new();iron_ball.room=self;iron_ball.position=Vector3(-.6,.27,2.9);iron_ball.process_mode=Node.PROCESS_MODE_PAUSABLE;add_child(iron_ball)

func _tone(frequency: float,duration: float,amount: float=1.0) -> void:
	if not sounds_enabled or audio_player==null:return
	var rate:=22050;var count:=int(rate*duration);var bytes:=PackedByteArray();bytes.resize(count*2)
	for i in range(count):
		var t:=float(i)/rate;var envelope:=pow(1.0-float(i)/count,2.3)*minf(1,t*180)
		var value:=sin(TAU*frequency*t)+.25*sin(TAU*frequency*2.01*t)
		bytes.encode_s16(i*2,int(clampf(value*envelope*amount,-1,1)*12000))
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=rate;stream.data=bytes;audio_player.stream=stream;audio_player.play()

