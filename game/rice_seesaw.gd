extends Node3D

const TABLE_Y=4.298
const PIVOT=Vector3(5.5,.34,-.40)
const BOARD_BASIS=Basis(Vector3.UP,PI*.5)
const END_X=1.05
const BALL_HOME=Vector3(5.5,TABLE_Y+.075+.252,-6.13)
const BOWL_POINT=Vector3(6.83,TABLE_Y+.012,-5.20)
const ROOF_Y=8.4
const ROOF_FLIGHT_AUDIO_SECONDS=.70
const ROOF_IMPACT_AUDIO_RATE=1.0
var room:Node3D
var beam:RigidBody3D
var support:StaticBody3D
var hinge:HingeJoint3D
var ball:RigidBody3D
var gate:StaticBody3D
var trapdoor:RigidBody3D
var trapdoor_home=Transform3D(Basis.IDENTITY,Vector3(5.5,TABLE_Y+.045,-4.58))
var button_cap:Node3D
var button_platform:AnimatableBody3D
var button_down=false
var button_latched=false
var button_point=Vector3(6.3,.18,.15)
var bowl_exit=Vector3(6.12,TABLE_Y+.04,-4.94)
var table_landing=Vector3(6.25,TABLE_Y+.03,-4.92)
var drop_point=Vector3(6.3,TABLE_Y,-4.67)
var bowl_body:StaticBody3D
var rice:MultiMeshInstance3D
var rice_mound:MeshInstance3D
var rice_collision:CollisionShape3D
var rice_fraction=1.0
var rice_grains=7200
var quest:Label
var context:Label
var ui:CanvasLayer
var phase="ready"
var button_age=-1.0
var shot_time=0.0
var shot_kind=""
var camera_return_at=-1.0
var camera_tracking=false
var camera_look_weight=0.0
var camera_look_elevation=0.0
var camera_pitch_overlay=0.0
var camera_yaw_overlay=0.0
var roof_hole_point=Vector3.ZERO
var sound_rates:Dictionary={}
var rice_collision_fraction=-1.0
var audio_cache:Dictionary={}
var prop_materials:Dictionary={}
var ai_mode="wander"
var ai_waypoint=0
var ai_stuck=0.0
var ai_hops=0
var ai_last=Vector3.ZERO
var ai_wait_announced=false
var roof_broken=false
var roof_respawn_at=-1.0
var roof_escape_announced=false
var companion_respawn_count=0
var roof_tile:Node3D
var roof_replacement:Node3D
var roof_sky:MeshInstance3D
var roof_layers:Array=[]
var roof_colliders:Array=[]
var roof_original_materials:Array=[]
var roof_cut_material:ShaderMaterial
var roof_sky_mesh:SphereMesh
var roof_sky_material:ShaderMaterial
var roof_shard_mesh:BoxMesh
var debris:Array[Node3D]=[]
var events:Array=[]
var sound_counts:Dictionary={}
var runtime=0.0
var strike_cooldown=0.0
var last_seats:Dictionary={}
var first_launch_count=0
var normal_launch_count=0
var powered_launch_count=0
var roof_break_count=0
var actor_peak_after_launch=0.0
var npc_peak_after_launch=0.0
var last_fall_impact=0.0
var last_ball_impact=0.0
var automatic_ai=true
var wait_latched=false
var wait_side=-1
var waited_partner:CharacterBody3D
var player_was_on_table=false
var table_assist_pending=false
var rng=RandomNumberGenerator.new()

func _ready() -> void:
	name="RiceSeesawPlayground";process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=-20;rng.seed=12044
	for key in ["button_click","ball_drop_reference","rocket_whistle","rice_munch","rice_ready","power_dive","roof_crash_reference","body_collision"]:
		var asset="rocket_whistle_070s_up3" if key=="rocket_whistle" else key
		audio_cache[key]=load("res://assets/playground/"+asset+".wav")
	room.actor.playground=self;room.companion.playground=self
	_build_seesaw();_build_runway();_build_button();_build_bowl();_build_ui()
	# Soft, warm reflected window light keeps the shaded toy mechanisms readable.
	var bounce=OmniLight3D.new();bounce.name="WindowBounceAtPlayground";add_child(bounce);bounce.position=Vector3(5.7,1.75,-2.65)
	bounce.light_color=Color(1.0,.85,.68);bounce.light_energy=.38;bounce.omni_range=4.3;bounce.omni_attenuation=1.6;bounce.shadow_enabled=true;bounce.light_size=.55
	roof_tile=room.room.get_node("Architecture/Ceiling/Tile_5_3")
	for c in roof_tile.find_children("*","CollisionObject3D",true,false):roof_colliders.append(c);roof_layers.append(c.collision_layer)
	var plaster=load("res://room_kit/materials/mk_eggshell_warm.tres")
	roof_cut_material=ShaderMaterial.new();roof_cut_material.shader=preload("res://roof_break.gdshader")
	roof_cut_material.set_shader_parameter("plaster_color",plaster.albedo_texture);roof_cut_material.set_shader_parameter("plaster_roughness",plaster.roughness_texture);roof_cut_material.set_shader_parameter("wall_color",plaster.albedo_color)
	roof_sky_mesh=SphereMesh.new();roof_sky_mesh.radius=45;roof_sky_mesh.height=90;roof_sky_mesh.radial_segments=24;roof_sky_mesh.rings=12
	roof_sky_material=ShaderMaterial.new();roof_sky_material.shader=preload("res://room_kit/window_sky.gdshader")
	roof_shard_mesh=BoxMesh.new();roof_shard_mesh.size=Vector3.ONE
	ai_last=room.companion.global_position

func warmup_roof_visuals(point:Vector3) -> Node3D:
	var preview=Node3D.new();add_child(preview);preview.global_position=point
	for material in [roof_cut_material,roof_sky_material,load("res://room_kit/materials/mk_eggshell_warm.tres")]:
		var mesh=MeshInstance3D.new();mesh.mesh=roof_shard_mesh;mesh.material_override=material;mesh.scale=Vector3.ONE*.1;preview.add_child(mesh)
		mesh.position.x=float(preview.get_child_count()-2)*.14;mesh.layers=2;mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	return preview

func model(asset:String,parent:Node,point:Vector3) -> Node3D:
	var instance=load("res://assets/playground/"+asset+".glb").instantiate()
	parent.add_child(instance);instance.position=point
	for mesh in instance.find_children("*","MeshInstance3D",true,false):
		mesh.layers=2;mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
		for index in mesh.mesh.get_surface_count():
			var m=mesh.get_active_material(index)
			if m is StandardMaterial3D:
				if m.resource_name.begins_with("V15_"):
					mesh.set_surface_override_material(index,_prop_finish(m));continue
				m=m.duplicate();m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				if "V12_Oak" in m.resource_name:
					var wood=load("res://room_kit/materials/legacy_walnut___open_grain.tres")
					m.albedo_texture=wood.albedo_texture;m.albedo_color=Color(1.5,1.25,.92);m.roughness=.68;m.metallic_specular=.27
					m.normal_enabled=wood.normal_enabled;m.normal_texture=wood.normal_texture;m.normal_scale=.15
				elif "Paint" in m.resource_name:m.roughness=.65;m.metallic_specular=.25
				mesh.set_surface_override_material(index,m)
	return instance

func _prop_finish(source:StandardMaterial3D) -> Material:
	var key=source.resource_name
	if prop_materials.has(key):return prop_materials[key]
	var m:StandardMaterial3D=source.duplicate()
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var finish=preload("res://toy_art_direction.gd").new()
	var result:Material=m
	if "Oak" in key:
		var wood=preload("res://room_kit/materials/legacy_walnut___open_grain.tres")
		m.albedo_texture=wood.albedo_texture;m.normal_texture=wood.normal_texture;m.roughness_texture=wood.roughness_texture
		m.albedo_color=Color(1.34,1.25,1.10)
		result=finish.finish(m,.48,.17,.30,.13,0,.055,0,0,.025)
	elif "Paint" in key or "ButtonRed" in key:
		result=finish.finish(m,.41,.13,.31,.035,0,.06,0,0,.025)
	elif "Brass" in key or "Steel" in key:
		result=finish.finish(m,.30,.14,.48,.025,.78,0,0,0,.018)
	elif "Porcelain" in key:
		m.albedo_color=Color(.85,.88,.84);m.roughness=.26;m.metallic_specular=.38
		m.clearcoat_enabled=true;m.clearcoat=.17;m.clearcoat_roughness=.23
	elif "Rubber" in key:m.roughness=.91;m.metallic_specular=.18
	prop_materials[key]=result
	return result

func material(color:Color,roughness:float=.65,metallic:float=0.0) -> StandardMaterial3D:
	var m=StandardMaterial3D.new();m.albedo_color=color;m.roughness=roughness;m.metallic=metallic;m.metallic_specular=.3;return m

func box_visual(parent:Node,point:Vector3,size:Vector3,mat:Material) -> MeshInstance3D:
	var mesh=MeshInstance3D.new();var shape=BoxMesh.new();shape.size=size;mesh.mesh=shape;mesh.material_override=mat
	mesh.layers=2;mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;parent.add_child(mesh);mesh.position=point;return mesh

func box_collision(parent:Node,point:Vector3,size:Vector3) -> CollisionShape3D:
	var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=size;cs.shape=shape;parent.add_child(cs);cs.position=point;return cs

func _build_seesaw() -> void:
	support=StaticBody3D.new();support.name="SeesawSupport";support.collision_layer=1;support.collision_mask=6;add_child(support);support.position=Vector3(PIVOT.x,0,PIVOT.z);support.basis=BOARD_BASIS
	model("seesaw_base",support,Vector3.ZERO);box_collision(support,Vector3(0,.12,0),Vector3(.48,.24,.8))
	beam=preload("res://seesaw_body.gd").new();beam.name="SeesawBeam";beam.playground=self;add_child(beam);beam.transform=Transform3D(BOARD_BASIS,PIVOT)
	model("seesaw_board",beam,Vector3.ZERO);box_collision(beam,Vector3.ZERO,Vector3(2.90,.105,.72))
	for side in [-1,1]:box_collision(beam,Vector3(side*END_X,.065,0),Vector3(.62,.04,.68))
	hinge=HingeJoint3D.new();hinge.name="PhysicalAxle";add_child(hinge);hinge.transform=Transform3D(BOARD_BASIS,PIVOT)
	hinge.node_a=hinge.get_path_to(support);hinge.node_b=hinge.get_path_to(beam)
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT,true)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER,-.19);hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER,.19)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_BIAS,.8)
	# Low stepping blocks let the little characters approach both moving seats.
	for side in [-1,1]:
		var step=StaticBody3D.new();add_child(step);step.position=Vector3(PIVOT.x,0,PIVOT.z)+BOARD_BASIS*Vector3(side*END_X,.07,.54);step.basis=BOARD_BASIS
		box_collision(step,Vector3.ZERO,Vector3(.54,.14,.32));box_visual(step,Vector3.ZERO,Vector3(.54,.14,.32),material(Color(.30,.21,.10)))

func _build_runway() -> void:
	var track=StaticBody3D.new();track.name="DeskBallRunway";track.collision_layer=1;track.collision_mask=6;add_child(track)
	track.position=Vector3(5.5,TABLE_Y+.045,-5.30)
	model("ball_runway",track,Vector3.ZERO)
	box_collision(track,Vector3(0,0,-.2725),Vector3(.65,.075,2.005))
	for x in [-.32,.32]:box_collision(track,Vector3(x,.075,0),Vector3(.035,.14,2.55))
	# The visible timed gate is the end stop. No second, invisible wall beyond it.
	trapdoor=RigidBody3D.new();trapdoor.name="HingedDropDoor";trapdoor.mass=1.2;trapdoor.collision_layer=1;trapdoor.collision_mask=7;trapdoor.freeze=true;trapdoor.angular_damp=.5;add_child(trapdoor);trapdoor.transform=trapdoor_home
	box_collision(trapdoor,Vector3(0,0,.30),Vector3(.60,.065,.60));box_visual(trapdoor,Vector3(0,0,.30),Vector3(.60,.065,.60),material(Color(.30,.21,.09)))
	var flap_joint=HingeJoint3D.new();add_child(flap_joint);flap_joint.position=trapdoor_home.origin;flap_joint.rotation.y=PI*.5
	flap_joint.node_a=flap_joint.get_path_to(track);flap_joint.node_b=flap_joint.get_path_to(trapdoor)
	flap_joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT,true);flap_joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER,-1.4);flap_joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER,1.4)
	gate=StaticBody3D.new();gate.name="TimedGate";add_child(gate);gate.position=Vector3(5.5,TABLE_Y+.26,-3.97)
	box_collision(gate,Vector3.ZERO,Vector3(.58,.42,.045));box_visual(gate,Vector3.ZERO,Vector3(.58,.42,.045),material(Color(.63,.35,.08),.42,.55))
	ball=preload("res://desk_iron_ball.gd").new();ball.room=room;ball.playground=self;ball.position=BALL_HOME;ball.process_mode=Node.PROCESS_MODE_PAUSABLE;add_child(ball)
	# A painted jump-off tab sits just inside the real tabletop edge.
	box_visual(self,drop_point+Vector3.UP*.015,Vector3(.42,.016,.28),material(Color(.66,.34,.09),.72))
	for x in [-.075,.075]:
		var foot=MeshInstance3D.new();var sphere=SphereMesh.new();sphere.radius=.055;sphere.height=.025;foot.mesh=sphere
		foot.material_override=material(Color(.90,.80,.58));add_child(foot);foot.position=drop_point+Vector3(x,.033,0);foot.scale.z=1.6;foot.layers=2;foot.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC

func _build_button() -> void:
	var body=StaticBody3D.new();body.name="ReleaseButton";add_child(body);body.position=Vector3(button_point.x,0,button_point.z)
	model("button_base",body,Vector3.ZERO);box_collision(body,Vector3(0,.07,0),Vector3(.4,.14,.34))
	button_platform=AnimatableBody3D.new();button_platform.name="PressurePedal";body.add_child(button_platform);button_platform.position.y=.183;button_platform.sync_to_physics=false
	button_cap=model("button_cap",button_platform,Vector3.ZERO)
	var collider=CollisionShape3D.new();var shape=CylinderShape3D.new();shape.radius=.108;shape.height=.065;collider.shape=shape;button_platform.add_child(collider)

func _update_pressure_button(delta:float) -> void:
	button_down=false
	for person in [room.actor,room.companion]:
		if person.stunt_mode!="" or person.state=="flattened":continue
		var d=person.global_position-button_platform.global_position
		if Vector2(d.x,d.z).length()<.18 and absf(d.y-.0325)<.075 and person.is_on_floor():button_down=true
	button_platform.position.y=move_toward(button_platform.position.y,.126 if button_down else .183,delta*.42)
	if button_down and not button_latched and button_platform.position.y<.145:
		button_latched=true;press_button()
	elif not button_down:button_latched=false

func _build_bowl() -> void:
	bowl_body=StaticBody3D.new();bowl_body.name="PorcelainRiceBowl";add_child(bowl_body);bowl_body.position=BOWL_POINT
	model("rice_bowl",bowl_body,Vector3.ZERO)
	var base=CollisionShape3D.new();var sh=CylinderShape3D.new();sh.radius=.25;sh.height=.07;base.shape=sh;bowl_body.add_child(base);base.position.y=.04
	for i in range(20):
		var a=i*TAU/20;var cs=box_collision(bowl_body,Vector3(cos(a)*.46,.22,sin(a)*.46),Vector3(.10,.24,.15));cs.rotation.y=-a
	var m=material(Color(.98,.97,.93),.38);m.subsurf_scatter_enabled=true;m.subsurf_scatter_strength=.22;m.metallic_specular=.28
	var surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(24):
		for i in range(64):
			var quad=[]
			for corner in [Vector2(ring,i),Vector2(ring+1,i),Vector2(ring+1,i+1),Vector2(ring,i+1)]:
				var radius=corner.x/24.0*.445;var angle=corner.y/64.0*TAU
				quad.append(Vector3(cos(angle)*radius,.095*sqrt(maxf(0,1-pow(radius/.445,2))),sin(angle)*radius))
			for index in [0,1,2,0,2,3]:surface.add_vertex(quad[index])
	surface.generate_normals()
	rice_mound=MeshInstance3D.new();rice_mound.mesh=surface.commit();rice_mound.material_override=m;bowl_body.add_child(rice_mound);rice_mound.position.y=.30;rice_mound.layers=2;rice_mound.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	rice_collision=CollisionShape3D.new();rice_collision.name="RiceSurfaceCollision"
	var initial_shape=ConvexPolygonShape3D.new();var initial_points=PackedVector3Array()
	for corner in 8:initial_points.append(AABB(Vector3(-.2,.08,-.2),Vector3(.4,.3,.4)).get_endpoint(corner))
	initial_shape.points=initial_points;rice_collision.shape=initial_shape
	_update_rice_collision()
	bowl_body.add_child(rice_collision)
	rice=MultiMeshInstance3D.new();var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.use_custom_data=true
	var grain_mat=ShaderMaterial.new();grain_mat.shader=preload("res://rice_surface.gdshader")
	var grain=SphereMesh.new();grain.radius=1;grain.height=2;grain.radial_segments=12;grain.rings=7;mm.mesh=grain;mm.instance_count=rice_grains;mm.visible_instance_count=rice_grains;rice.multimesh=mm;rice.material_override=grain_mat;rice.layers=2;rice.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;bowl_body.add_child(rice)
	var rows:Array=[]
	for i in range(rice_grains):
		var a=rng.randf()*TAU;var radius=sqrt(rng.randf())*.439;var y=.306+sqrt(maxf(0,1-pow(radius/.445,2)))*.095+rng.randf_range(-.001,.005)
		rows.append({"p":Vector3(cos(a)*radius,y,sin(a)*radius),"a":rng.randf()*TAU})
	rows.sort_custom(func(a,b):return a.p.y<b.p.y)
	for i in range(rows.size()):
		var grain_basis=Basis(Vector3.UP,rows[i].a)*Basis(Vector3.RIGHT,rng.randf_range(-.22,.22))*Basis(Vector3.BACK,rng.randf_range(-.20,.20))
		mm.set_instance_transform(i,Transform3D(grain_basis*Basis.from_scale(Vector3(.0052,.0038,.0125)*rng.randf_range(.84,1.13)),rows[i].p))
		var shade=rng.randf_range(.94,1.0);mm.set_instance_color(i,Color(shade,shade*.995,shade*rng.randf_range(.965,.995)))
		mm.set_instance_custom_data(i,Color(rows[i].p.x,rows[i].p.y,rows[i].p.z,rows[i].p.y-.306-sqrt(maxf(0,1-pow(Vector2(rows[i].p.x,rows[i].p.z).length()/.445,2)))*.095))

func _build_ui() -> void:
	ui=CanvasLayer.new();ui.layer=9;add_child(ui)
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	quest=Label.new();quest.position=Vector2(60,172);quest.size=Vector2(1000,105);quest.add_theme_font_override("font",font);quest.add_theme_font_size_override("font_size",25);quest.add_theme_color_override("font_color",Color(.98,.87,.64));quest.add_theme_color_override("font_shadow_color",Color(0,0,0,.9));quest.add_theme_constant_override("shadow_offset_x",2);quest.add_theme_constant_override("shadow_offset_y",2);ui.add_child(quest)
	context=Label.new();context.position=Vector2(630,1140);context.size=Vector2(1300,55);context.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;context.add_theme_font_override("font",font);context.add_theme_font_size_override("font_size",31);context.add_theme_color_override("font_shadow_color",Color(0,0,0));context.add_theme_constant_override("shadow_offset_x",2);context.add_theme_constant_override("shadow_offset_y",2);ui.add_child(context)
	quest.mouse_filter=Control.MOUSE_FILTER_IGNORE;context.mouse_filter=Control.MOUSE_FILTER_IGNORE

func _process(delta:float) -> void:
	if not room.ready_to_play:return
	if is_instance_valid(roof_sky):roof_sky.global_position=room.camera.global_position
	shot_time=maxf(0,shot_time-delta);ui.visible=room.hud.visible
	var message="踩下红色按钮 → 站上蓝色端 → 弹到桌面"
	if phase=="rolling":message="铁球滚动中 · 站在蓝色端等待"
	elif phase in ["ball_falling","launched"]:message="跷跷板正在传递冲击！"
	elif phase=="table":message="桌上有一碗米饭 · E 吃饭，或直接跳下试试"
	elif phase=="fed":message="米饭能量已就绪 · 从橙色脚印跳下踩橙色端"
	elif phase=="normal_complete":message="普通弹射：同伴刚好到桌面 · 按桌下按钮可重玩"
	elif phase=="escaping":message="大肥鱼还在往上飞！%.1f 秒后回到房间"%maxf(0,roof_respawn_at-runtime)
	elif phase=="complete":message="同伴已经重生 · 踩下红色按钮可重新开始"
	if ai_mode=="waiting":message+="\n同伴已站稳蓝色端"
	elif ai_mode in ["walking","boarding"]:message+="\n同伴正在走向蓝色端"
	quest.text="前往小屋\n探索墙角的小门" if phase in ["normal_complete","complete"] else "米饭弹射实验\n"+message
	context.text=""
	if room.actor.stunt_mode!="":return
	if _near_button():context.text="跳上红色按钮，踩下放球" if phase=="ready" else "再次踩下红色按钮可以复位机关"
	elif _near_bowl():context.text="E  趴进饭碗 · 从外圈绕着吃" if rice_fraction>.05 else "饭碗已经空了 · 米饭能量会强化下一次踩板"
	elif _near_drop():context.text="空格起跳 · WASD 自由控制落点"+(" · 米饭力量" if room.actor.rice_charged else "")

func _physics_process(delta:float) -> void:
	if not room.ready_to_play:return
	runtime+=delta;strike_cooldown=maxf(0,strike_cooldown-delta)
	_update_pressure_button(delta)
	if roof_respawn_at>=0 and runtime>=roof_respawn_at:_respawn_companion()
	if button_age>=0:
		var prior=button_age;button_age+=delta
		if prior<.19 and button_age>=.19:_release_ball()
		if button_age>.55:button_age=-1
	for person in [room.actor,room.companion]:
		if on_seat(person,0):last_seats[person.get_instance_id()]={"side":signf(beam.to_local(person.global_position).x),"time":runtime}
	_update_table_arrival()
	if automatic_ai:_drive_companion(delta)
	actor_peak_after_launch=maxf(actor_peak_after_launch,room.actor.global_position.y)
	npc_peak_after_launch=maxf(npc_peak_after_launch,room.companion.global_position.y)
	if ball.track_mode=="falling":phase="ball_falling" if phase=="rolling" else phase
	if ball.global_position.y< -2:ball.track_mode="spent";room._teleport_prop(ball,Transform3D(Basis.IDENTITY,Vector3(7,.3,-2.8)))

func handle_input(event:InputEvent) -> bool:
	if room.paused or not room.ready_to_play:return false
	if event is InputEventKey and event.pressed and not event.echo:
		if room.actor.stunt_mode!="" and event.physical_keycode in [KEY_E,KEY_F,KEY_SPACE,KEY_Q,KEY_CTRL]:get_viewport().set_input_as_handled();return true
		if event.physical_keycode==KEY_E:
			if _near_bowl():eat_rice();get_viewport().set_input_as_handled();return true
			if ball.track_mode=="spent" and ball.handle_input(event):return true
	if room.actor.stunt_mode!="" and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:get_viewport().set_input_as_handled();return true
	return false

func _near_button() -> bool:
	return room.actor.global_position.distance_to(button_point)<.62 and room.actor.is_on_floor()
func _near_bowl() -> bool:
	return Vector2(room.actor.position.x-BOWL_POINT.x,room.actor.position.z-BOWL_POINT.z).length()<.87 and absf(room.actor.position.y-TABLE_Y)<.58 and room.actor.is_on_floor()
func _near_drop() -> bool:
	return Vector2(room.actor.position.x-drop_point.x,room.actor.position.z-drop_point.z).length()<.52 and absf(room.actor.position.y-TABLE_Y)<.12 and room.actor.is_on_floor()

func press_button() -> bool:
	if button_age>=0 or ball.track_mode in ["rolling","falling"]:return false
	if phase!="ready":reset_puzzle(false)
	button_age=0;event("button_press")
	room._show_toast("按钮踩下了！快站到蓝色一端",3);return true

func _release_ball() -> void:
	ball.freeze=false;ball.sleeping=false;ball.track_mode="rolling";ball.roll_age=0;ball.first_contact_time=-1
	phase="rolling";sound("button_click",button_point,-18);event("ball_started")

func open_gate() -> void:
	gate.collision_layer=0;gate.collision_mask=0;gate.hide();trapdoor.freeze=false;trapdoor.sleeping=false;trapdoor.apply_torque_impulse(Vector3(1.0,0,0));event("gate_open",{"rolling_seconds":ball.roll_age})

func seat_point(side:int) -> Vector3:
	return beam.to_global(Vector3(side*END_X,.091,0))

func on_seat(person,side:int) -> bool:
	if not person.visible or person.stunt_mode!="" or person.state in ["flattened","stunned"]:return false
	var p=beam.to_local(person.global_position)
	return absf(p.z)<.40 and absf(p.x)>.58 and absf(p.x)<1.42 and p.y>-.02 and p.y<.22 and (side==0 or signf(p.x)==side) and person.velocity.y<.9

func occupant(side:int,exclude=null):
	for person in [room.actor,room.companion]:
		if person==exclude:continue
		if on_seat(person,side):return person
		var cached=last_seats.get(person.get_instance_id(),{})
		if not cached.is_empty() and cached.side==side and runtime-cached.time<.15 and person.stunt_mode=="":
			var p=beam.to_local(person.global_position)
			if absf(p.z)<.42 and absf(p.x-side*END_X)<.42:return person
	return null

func ball_hit(incoming:Vector3) -> void:
	last_ball_impact=absf(incoming.y);sound("ball_drop_reference",ball.global_position,-12);event("ball_impact",{"speed":last_ball_impact,"age":ball.roll_age})
	_strike(1,false,null,"iron_ball")
	# The dropping ball rebounds off the end, then continues as a pushable rigid body.
	ball.apply_central_impulse(Vector3(0,.50,1.55)*ball.mass)

func character_hit_board(person,incoming:Vector3,_previous:Vector3) -> void:
	if strike_cooldown>0 or incoming.y> -5.0:return
	var side=int(signf(beam.to_local(person.global_position).x))
	if side==0:return
	var powered:bool=person.rice_charged and (person.stomp_active or person.flight_kind=="drop_power")
	last_fall_impact=-incoming.y
	beam.apply_impulse(Vector3.DOWN*(-incoming.y)*(.95 if not powered else 4.6),person.global_position-beam.global_position)
	event("character_impact",{"side":side,"powered":powered,"speed":-incoming.y})
	_strike(side,powered,person,"character")
	if powered:person.rice_charged=false;person.stomp_active=false

func _strike(side:int,powered:bool,source,reason:String) -> void:
	if strike_cooldown>0:return
	strike_cooldown=.48
	var person=occupant(-side,source)
	if person==null:event("empty_other_end");return
	if person==room.companion:wait_latched=false;waited_partner=null;room.companion.get_node("WanderMind").set_physics_process(false);ai_mode="flying"
	person.global_position+=Vector3.UP*.055
	if powered:
		person.start_flight(Vector3(0,24,0),"roof");powered_launch_count+=1
		shot_kind="roof";shot_time=8.0;camera_tracking=person==room.companion;camera_return_at=-1
		if camera_tracking:_begin_camera_follow()
		sound("rocket_whistle",person.global_position,-15);event("powered_launch")
	else:
		person.start_flight(velocity_to(person.global_position,table_landing,TABLE_Y+1.10,12.15),"table")
		if reason=="iron_ball":first_launch_count+=1;phase="launched"
		else:normal_launch_count+=1
		if person==room.companion:shot_kind="table";shot_time=5.0;camera_tracking=true;camera_return_at=runtime+4.6;_begin_camera_follow()
		event("normal_launch",{"who":"player" if person==room.actor else "companion"})
	last_seats.erase(person.get_instance_id())

func velocity_to(start:Vector3,target:Vector3,apex:float,gravity_value:float) -> Vector3:
	var vy=sqrt(2*gravity_value*maxf(.08,apex-start.y))
	var flight=(vy+sqrt(maxf(.02,vy*vy-2*gravity_value*(target.y-start.y))))/gravity_value
	return Vector3((target.x-start.x)/flight,vy,(target.z-start.z)/flight)

func eat_rice() -> bool:
	if rice_fraction<.05 or room.actor.stunt_mode!="":return false
	room.actor.start_meal(BOWL_POINT);sound("rice_munch",BOWL_POINT,-23)
	event("meal_started");return true

func set_rice_fraction(value:float) -> void:
	rice_fraction=clampf(value,0,1)
	# The whole fine-grained surface lowers from top to bottom. Grains retain
	# their own dimensions; the bowl's taper narrows the food's footprint.
	rice.multimesh.visible_instance_count=rice_grains if rice_fraction>.012 else 0
	rice.material_override.set_shader_parameter("fill_amount",rice_fraction)
	var width=lerpf(.57,1.0,sqrt(rice_fraction))
	rice_mound.scale=Vector3(width,maxf(.001,rice_fraction),width)
	rice_mound.position.y=.10+.203*rice_fraction;rice_mound.visible=rice_fraction>.012
	if absf(rice_fraction-rice_collision_fraction)>.025 or rice_fraction<=.012 or rice_fraction==1:_update_rice_collision()

func _update_rice_collision() -> void:
	if rice_collision==null:return
	rice_collision_fraction=rice_fraction
	rice_collision.set_deferred("disabled",rice_fraction<=.012)
	if rice_fraction<=.012:return
	var points=PackedVector3Array([Vector3(0,rice_surface_height(0)-.004,0),Vector3(0,.075,0)])
	var width=.445*lerpf(.57,1.0,sqrt(rice_fraction))
	for fraction in [.5,.85,1.0]:
		for i in 24:
			var angle=i*TAU/24;var radius=width*fraction
			points.append(Vector3(cos(angle)*radius,rice_surface_height(radius)-.004,sin(angle)*radius))
	for i in 16:
		var angle=i*TAU/16;points.append(Vector3(cos(angle)*width,.075,sin(angle)*width))
	rice_collision.shape.points=points

func rice_surface_height(radius:float) -> float:
	var width=.445*lerpf(.57,1.0,sqrt(rice_fraction))
	return .106+.203*rice_fraction+.095*rice_fraction*sqrt(maxf(0,1-pow(radius/width,2)))

func meal_finished(_person) -> void:
	phase="fed";sound("rice_ready",BOWL_POINT,-20);event("meal_finished")
	room._show_toast("吃饱啦！自己掌握方向，跳到橙色一端",4)

# Leaving the desk uses the ordinary controller and real board contacts.
# There is deliberately no target-seeking drop or Space-key interception.

func _on_writing_desk(person:CharacterBody3D) -> bool:
	var p=person.global_position
	return p.x>2.70 and p.x<7.65 and p.z> -7.15 and p.z< -4.40 and p.y>TABLE_Y-.08 and person.is_on_floor() and person.stunt_mode==""

func _update_table_arrival() -> void:
	var on_table=_on_writing_desk(room.actor)
	if on_table and not player_was_on_table:table_assist_pending=true
	if not on_table:table_assist_pending=false
	player_was_on_table=on_table
	if not table_assist_pending or not automatic_ai:return
	# Never recall a companion who has already reached the table. Only a new
	# grounded table arrival requests help; jumping back onto the seesaw does not.
	if _on_writing_desk(room.companion) or ai_mode in ["table_stay","waiting","walking","boarding","flying","away"]:
		table_assist_pending=false;return
	# Role switching / an expired 12-second command can leave ai_mode="manual".
	# Actual command/hold ownership, rather than that stale label, decides whether
	# the free companion can respond. An active explicit order is still respected.
	if _begin_ai():
		table_assist_pending=false
		if phase not in ["fed","complete"]:phase="table"

func _begin_ai() -> bool:
	if wait_latched or _on_writing_desk(room.companion):return false
	if room.companion.get_node("WanderMind").manual_hold or room.companion.get_node("WanderMind").commanded:return false
	if room.companion.state in ["flattened","stunned"] or room.companion.stunt_mode!="":return false
	if on_seat(room.companion,0):
		_latch_board_wait();return true
	var person=room.companion;person.get_node("WanderMind").set_physics_process(false)
	person.override_direction=Vector3.ZERO;person.input_override=true;person.can_control=false;person.override_sprint=true
	ai_mode="walking";ai_waypoint=0;ai_stuck=0;ai_wait_announced=false;event("ai_called")
	return true

func release_board_wait() -> void:
	wait_latched=false;waited_partner=null
	if ai_mode in ["waiting","walking","boarding"]:
		ai_mode="manual";room.companion.override_direction=Vector3.ZERO;room.companion.push_speed_override=-1
		room.companion.get_node("WanderMind").set_physics_process(true)

func _latch_board_wait() -> void:
	wait_latched=true;waited_partner=room.companion;ai_mode="waiting";set_meta("player_glided_after_wait",false)
	wait_side=-1 if beam.to_local(waited_partner.global_position).x<0 else 1
	waited_partner.get_node("WanderMind").set_physics_process(false)
	waited_partner.override_direction=Vector3.ZERO;waited_partner.override_jump=false;waited_partner.push_speed_override=-1

func _drive_companion(delta:float) -> void:
	var person=room.companion
	if wait_latched:
		# Explicit role selection gives control to that fish immediately.
		if waited_partner!=person:release_board_wait();return
		# A completed paper-plane crossing is the automatic release condition.
		var riding=room.paper_plane.is_riding(room.actor)
		if riding and room.paper_plane.gliding:set_meta("player_glided_after_wait",true)
		if get_meta("player_glided_after_wait",false) and not riding and room.actor.is_on_floor() and room.actor.position.x< -3.4 and room.actor.position.y>2.6 and room.actor.position.z< -2.3 and room.actor.position.z> -4.8:
			set_meta("player_glided_after_wait",false);release_board_wait();person.get_node("WanderMind").set_manual_hold(false);return
	if person.get_node("WanderMind").manual_hold:return
	if ai_mode=="walking":
		var waypoints=[Vector3(4.8,0,2.6),Vector3(5.4,0,2.3),Vector3(5.5,0,1.72)]
		var target:Vector3=waypoints[mini(ai_waypoint,waypoints.size()-1)]
		var d=target-person.global_position;d.y=0
		if d.length()<.18:
			ai_waypoint+=1
			if ai_waypoint>=waypoints.size():
				person.override_direction=Vector3.ZERO;person.start_flight(velocity_to(person.global_position,seat_point(-1)+Vector3.UP*.015,maxf(.95,seat_point(-1).y+.3),12.15),"board_step")
				ai_mode="boarding";ai_hops+=1;return
			return
		var desired=d.normalized()
		if person.test_move(person.global_transform,desired*.32):
			for a in [.65,-.65,1.2,-1.2,1.8,-1.8]:
				var candidate=desired.rotated(Vector3.UP,a)
				if not person.test_move(person.global_transform,candidate*.35):desired=candidate;break
		person.override_direction=desired;person.push_speed_override=minf(1.35,d.length()*3.4)
		if person.global_position.distance_to(ai_last)<.001:ai_stuck+=delta
		else:ai_stuck=0
		if ai_stuck>.65 and person.is_on_floor():person.override_jump=true;ai_stuck=0
	elif ai_mode=="waiting":
		person.override_direction=Vector3.ZERO;person.override_jump=false;person.push_speed_override=-1
		# Stay on this end as the beam rocks. Small normal walking corrections
		# keep the feet aboard; never send the fish down to ground waypoints.
		if person.stunt_mode=="" and person.is_on_floor():
			var d=seat_point(wait_side)-person.global_position;d.y=0
			if d.length()>.07:
				person.override_direction=d.normalized();person.push_speed_override=minf(.38,d.length()*3)
	elif ai_mode=="table_stay":person.override_direction=Vector3.ZERO;person.push_speed_override=-1
	ai_last=person.global_position

func character_landed(person,kind:String) -> void:
	if person==room.actor and _on_writing_desk(person):
		_update_table_arrival()
		if phase!="fed":phase="table"
	if person==room.companion:
		person.override_direction=Vector3.ZERO;person.push_speed_override=-1
		if kind=="ram":
			person.get_node("WanderMind").set_physics_process(true);ai_mode="wander";return
		if kind=="board_step":
			_latch_board_wait();person.heading_yaw=PI*.5
			if not ai_wait_announced:room._show_toast("同伴已经站到蓝色端，等你跳下来",3);ai_wait_announced=true
			event("ai_on_seat")
		elif kind=="table":
			if person.global_position.y>TABLE_Y-.08:ai_mode="table_stay";phase="normal_complete";event("companion_on_table")
			else:_begin_ai();event("companion_missed_table")

func check_roof_crossing(person,next_point:Vector3) -> void:
	if roof_broken or person.velocity.y<=0:return
	if next_point.y+.45>=ROOF_Y:
		break_roof(Vector3(person.position.x,ROOF_Y,person.position.z))

func break_roof(point:Vector3) -> void:
	if roof_broken:return
	roof_broken=true;roof_break_count+=1
	roof_respawn_at=runtime+5.0;camera_return_at=runtime+1.0;roof_escape_announced=false;phase="escaping"
	for c in roof_colliders:c.collision_layer=0
	roof_replacement=Node3D.new();roof_replacement.name="BrokenRoof";add_child(roof_replacement)
	var m=load("res://room_kit/materials/mk_eggshell_warm.tres")
	var center=roof_tile.global_position
	var x=clampf(point.x,center.x-.69,center.x+.69);var z=clampf(point.z,center.z-.69,center.z+.69);var half=.43
	roof_hole_point=Vector3(x,ROOF_Y,z)
	for mesh in roof_tile.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			roof_original_materials.append({"mesh":mesh,"surface":surface,"material":mesh.get_active_material(surface)})
			roof_cut_material.set_shader_parameter("hole_center",Vector2(x,z))
			mesh.set_surface_override_material(surface,roof_cut_material)
	var left=center.x-1.2;var right=center.x+1.2;var back=center.z-1.2;var front=center.z+1.2
	var bounds=[Rect2(left,back,x-half-left,2.4),Rect2(x+half,back,right-x-half,2.4),Rect2(x-half,back,half*2,z-half-back),Rect2(x-half,z+half,half*2,front-z-half)]
	for r in bounds:
		if r.size.x<=0 or r.size.y<=0:continue
		var body=StaticBody3D.new();roof_replacement.add_child(body);body.position=Vector3(r.get_center().x,ROOF_Y+.08,r.get_center().y)
		box_collision(body,Vector3.ZERO,Vector3(r.size.x,.16,r.size.y))
	var sky=MeshInstance3D.new();sky.mesh=roof_sky_mesh;sky.material_override=roof_sky_material
	sky.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;sky.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;sky.layers=2;roof_replacement.add_child(sky)
	roof_sky=sky;roof_sky.global_position=room.camera.global_position
	for i in range(22):
		var shard=RigidBody3D.new();shard.mass=.025;shard.collision_layer=8;shard.collision_mask=1;shard.linear_damp=.18;shard.angular_damp=.24;add_child(shard)
		shard.position=point+Vector3(rng.randf_range(-.38,.38),rng.randf_range(-.07,.10),rng.randf_range(-.38,.38))
		var size=Vector3(rng.randf_range(.06,.18),.035,rng.randf_range(.07,.19))
		var visual=MeshInstance3D.new();visual.mesh=roof_shard_mesh;visual.material_override=m;visual.scale=size;visual.layers=2;visual.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;shard.add_child(visual);box_collision(shard,Vector3.ZERO,size)
		shard.linear_velocity=Vector3(rng.randf_range(-2,2),rng.randf_range(2,5),rng.randf_range(-2,2));shard.angular_velocity=Vector3(rng.randf_range(-5,5),rng.randf_range(-5,5),rng.randf_range(-5,5));debris.append(shard)
		var shard_ref=weakref(shard)
		get_tree().create_timer(6).timeout.connect(func():
			var alive=shard_ref.get_ref()
			if is_instance_valid(alive):alive.queue_free())
	sound("roof_crash_reference",point,-12);event("roof_broken",{"point":str(point)})

func companion_escaped() -> void:
	if roof_escape_announced:return
	roof_escape_announced=true;phase="escaping";ai_mode="away";event("companion_escaped")
	room._show_toast("咻——还在飞！冲出屋顶 5 秒后重生",4)

func _respawn_companion() -> void:
	roof_respawn_at=-1;companion_respawn_count+=1
	var person=room.companion;person.reset_position();person.position=Vector3(4.8,.08,1.6)
	person.velocity=Vector3.ZERO;person.can_control=false;person.input_override=true;person.override_direction=Vector3.ZERO;person.push_speed_override=-1
	person.get_node("WanderMind").set_physics_process(true)
	ai_mode="wander";phase="complete";event("companion_respawned")
	if person.get_node("WanderMind").manual_hold:person.get_node("WanderMind").restore_manual_anchor();ai_mode="manual"
	room._show_toast("大肥鱼回来了！",2)

func _begin_camera_follow() -> void:
	# The ordinary player camera owns position, focus and saved orbit settings.
	# Retain the overlay between shots to avoid an orientation discontinuity.
	camera_look_weight=0.0
	if shot_kind=="roof":
		var center=roof_tile.global_position;var npc=room.companion.global_position
		roof_hole_point=Vector3(clampf(npc.x,center.x-.69,center.x+.69),ROOF_Y,clampf(npc.z,center.z-.69,center.z+.69))

func update_camera(delta:float) -> bool:
	if room.overview:camera_pitch_overlay=0.0;camera_yaw_overlay=0.0;return false
	var active=camera_tracking and shot_time>0 and (camera_return_at<0 or runtime<camera_return_at)
	if not active:camera_tracking=false
	var forward=-room.camera.global_basis.z
	var base_elevation=asin(clampf(forward.y,-1,1))
	var target_offset=0.0
	var target_yaw_offset=0.0
	if active:
		var focus=room.companion.global_position+Vector3.UP*.30
		# Hold the roof opening near the upper edge instead of chasing the NPC into the sky.
		if shot_kind=="roof":
			# Anticipate the upper part of this known arc, while keeping the
			# position and horizontal orbit owned by the player's camera.
			focus=roof_hole_point
		var d=focus-room.camera.global_position
		var elevation=atan2(d.y,maxf(.2,Vector2(d.x,d.z).length()))
		var framing_margin=deg_to_rad(room.camera.fov*.5-7.0)
		camera_look_elevation=elevation-framing_margin
		target_offset=maxf(0,camera_look_elevation-base_elevation)
		var base_yaw=atan2(-forward.x,-forward.z)
		target_yaw_offset=wrapf(atan2(-d.x,-d.z)-base_yaw,-PI,PI)
	# Exponential easing plus an angular rate limit: no single-frame forced turn.
	var rate=5.5 if active else 3.2
	var eased=lerpf(camera_pitch_overlay,target_offset,1-exp(-delta*rate))
	camera_pitch_overlay=move_toward(camera_pitch_overlay,eased,deg_to_rad(70)*delta)
	var yaw_eased=lerp_angle(camera_yaw_overlay,target_yaw_offset,1-exp(-delta*rate))
	camera_yaw_overlay=move_toward(camera_yaw_overlay,yaw_eased,deg_to_rad(70)*delta)
	# Only orientation is temporarily offset. Camera position/focus and the user's
	# orbit settings remain attached to the player, including while the player moves.
	if absf(camera_pitch_overlay)+absf(camera_yaw_overlay)<.0001:return false
	room.camera.global_basis=Basis(Vector3.UP,camera_yaw_overlay)*room.camera.global_basis
	room.camera.rotate_object_local(Vector3.RIGHT,camera_pitch_overlay)
	room.attributes.dof_blur_far_enabled=false;room.attributes.dof_blur_near_enabled=false
	return false

func reset_puzzle(full:bool=true) -> void:
	ball.stop_push();ball.freeze=true;ball.track_mode="ready";ball.roll_age=0;ball.first_contact_time=-1
	room._teleport_prop(ball,Transform3D(Basis.IDENTITY,BALL_HOME));ball.freeze=true
	if full or (not on_seat(room.actor,0) and not on_seat(room.companion,0)):
		beam.global_transform=Transform3D(BOARD_BASIS,PIVOT);PhysicsServer3D.body_set_state(beam.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,beam.global_transform);beam.linear_velocity=Vector3.ZERO;beam.angular_velocity=Vector3.ZERO
	gate.show();gate.collision_layer=1;gate.collision_mask=7
	trapdoor.freeze=true;trapdoor.transform=trapdoor_home;PhysicsServer3D.body_set_state(trapdoor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,trapdoor_home);trapdoor.linear_velocity=Vector3.ZERO;trapdoor.angular_velocity=Vector3.ZERO
	set_rice_fraction(1);room.actor.rice_charged=false;room.actor.stomp_active=false
	if full:
		player_was_on_table=false;table_assist_pending=false
		release_board_wait();room.companion.reset_position();room.companion.position=Vector3(4.8,.04,1.6);room.companion.can_control=false;room.companion.input_override=true;room.companion.override_direction=Vector3.ZERO
		room.companion.get_node("WanderMind").set_physics_process(true);ai_mode="wander";ai_waypoint=0
	phase="ready";button_age=-1;strike_cooldown=0;last_seats.clear();shot_time=0;camera_tracking=false;camera_return_at=-1;camera_look_weight=0;camera_pitch_overlay=0;camera_yaw_overlay=0
	if room.companion.get_node("WanderMind").manual_hold:room.companion.get_node("WanderMind").restore_manual_anchor();ai_mode="manual"
	roof_tile.show()
	for saved in roof_original_materials:saved.mesh.set_surface_override_material(saved.surface,saved.material)
	roof_original_materials.clear()
	for i in roof_colliders.size():roof_colliders[i].collision_layer=roof_layers[i]
	if is_instance_valid(roof_replacement):roof_replacement.queue_free()
	for shard in debris:if is_instance_valid(shard):shard.queue_free()
	debris.clear();roof_broken=false;roof_respawn_at=-1;roof_escape_announced=false
	if full:room.actor.stunt_mode="";room.actor.pose_mode=""
	event("reset")

func sound(key:String,point:Vector3,volume:float=-18) -> void:
	if not room.sounds_enabled:return
	var player=AudioStreamPlayer3D.new();add_child(player);player.global_position=point;player.unit_size=4;player.max_distance=32;player.volume_db=volume
	player.stream=audio_cache.get(key)
	player.pitch_scale=player.stream.get_length()/ROOF_FLIGHT_AUDIO_SECONDS if key=="rocket_whistle" else ROOF_IMPACT_AUDIO_RATE
	sound_rates[key]=player.pitch_scale
	player.finished.connect(player.queue_free);player.play()
	sound_counts[key]=int(sound_counts.get(key,0))+1

func event(key:String,data:Dictionary={}) -> void:
	var row={"event":key,"time":runtime};row.merge(data);events.append(row)
	if room.automated:print("V12_EVENT ",JSON.stringify(row))
