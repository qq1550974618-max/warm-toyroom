extends Node3D
var room
var carriage:AnimatableBody3D
var door:AnimatableBody3D
var wheels:Array[Node3D]=[]
var door_open=false
var door_angle=0.0
var seated=false
var camera_active=false
var speed=0.0
var maximum_speed=1.4
var rail_position=2.25
var test_throttle=0.0
var input_override=false
var seat_pose:SkeletonModifier3D
var ride_sound:AudioStreamPlayer3D
var prior_control=true
var station_steps:StaticBody3D
var cargo:Array[RigidBody3D]=[]
var hint_layer:CanvasLayer
var door_hint:Label
const DRIVE_GAIN_DB=3.521825
const CAB_X=-.5635
func model(path:String,parent:Node) -> Node3D:
	var extension=".tscn" if path.begins_with("v19_") else ".glb"
	var node=load("res://assets/playground/"+path+extension).instantiate();parent.add_child(node)
	var finish=preload("res://rice_seesaw.gd").new()
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
		for si in mesh.mesh.get_surface_count():mesh.set_surface_override_material(si,finish._prop_finish(mesh.get_active_material(si)))
	finish.free();return node
func box(parent:Node,point:Vector3,size:Vector3) -> void:
	preload("res://v17_scene_refinement.gd").new().add_box(parent,point,size)
func _ready() -> void:
	name="InteractiveTrain";process_physics_priority=-25
	var old=room.room.get_node("Props/WoodenTrain");position=old.global_position;old.hide()
	for cs in old.find_children("*","CollisionShape3D",true,false):cs.disabled=true
	model("v17_train_track",self)
	var track=StaticBody3D.new();track.collision_layer=1;track.collision_mask=6;add_child(track)
	for z in [-.39,.39]:box(track,Vector3(.9635,.096,z),Vector3(6.274,.048,.049))
	for j in 34:box(track,Vector3(-2.1735+j*.189,.049,0),Vector3(.084,.07,.98))
	carriage=AnimatableBody3D.new();carriage.name="MovingCab";carriage.sync_to_physics=false;carriage.collision_layer=1;carriage.collision_mask=6;add_child(carriage);carriage.position.x=rail_position
	model("v19_train_body",carriage)
	station_steps=StaticBody3D.new();station_steps.name="StationBoardingSteps";station_steps.collision_layer=1;station_steps.collision_mask=6;add_child(station_steps);station_steps.position.x=2.25
	model("v19_1_station_steps",station_steps)
	for cx in [-.9835,.6265]:
		box(carriage,Vector3(cx,.365,0),Vector3(1.4,.15,.64))
		for x in [cx-.46,cx+.46]:
			for z in [-.39,.39]:
				var wheel=model("v17_train_wheel",carriage);wheel.position=Vector3(x,.31,z)
				if z>0:wheel.rotation.y=PI
				wheels.append(wheel)
	box(carriage,Vector3(-1.16,.69,0),Vector3(.94,.50,.51))
	box(carriage,Vector3(CAB_X+.27,.775,0),Vector3(.068,.64,.61))
	box(carriage,Vector3(CAB_X,1.142,0),Vector3(.70,.105,.76))
	box(carriage,Vector3(CAB_X,.70,-.306),Vector3(.6,.60,.046))
	for x in [CAB_X-.264,CAB_X+.264]:box(carriage,Vector3(x,.785,.306),Vector3(.065,.70,.05))
	box(carriage,Vector3(CAB_X+.1,.61,0),Vector3(.25,.08,.33))
	# Keep the upper two fixed treads clear of the moving wheels/carriage.
	for j in 8:box(station_steps,Vector3(CAB_X,.024+j*.043,.95-j*.0675),Vector3(.43,.038,.077))
	box(carriage,Vector3(.6265,.49,0),Vector3(1.24,.05,.60))
	for z in [-.315,.315]:box(carriage,Vector3(.6265,.67,z),Vector3(1.3,.34,.055))
	for x in [.0065,1.2465]:box(carriage,Vector3(x,.67,0),Vector3(.055,.34,.6))
	door=AnimatableBody3D.new();door.sync_to_physics=false;door.collision_layer=1;door.collision_mask=6;carriage.add_child(door);door.position=Vector3(CAB_X+.225,.435,.335)
	model("v17_train_door",door);box(door,Vector3(-.225,.29,0),Vector3(.44,.58,.036))
	seat_pose=preload("res://train_seat_pose.gd").new();seat_pose.train=self;seat_pose.actor=room.actor;room.actor.skeleton.add_child(seat_pose)
	ride_sound=AudioStreamPlayer3D.new();carriage.add_child(ride_sound);ride_sound.stream=load("res://assets/audio/toy_roll_loop.wav").duplicate();ride_sound.stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;ride_sound.stream.loop_end=int(ride_sound.stream.get_length()*ride_sound.stream.mix_rate);ride_sound.unit_size=2;ride_sound.volume_db=-80
	for i in 2:
		var ball=RigidBody3D.new();ball.name="WagonCargoBall%d"%i;ball.mass=.12;ball.collision_layer=4;ball.collision_mask=7;ball.continuous_cd=true;ball.linear_damp=.15;ball.angular_damp=.15;add_child(ball)
		var material=PhysicsMaterial.new();material.friction=1.0;material.bounce=.02;ball.physics_material_override=material
		var mesh=MeshInstance3D.new();var sphere=SphereMesh.new();sphere.radius=.203;sphere.height=.406;sphere.radial_segments=48;sphere.rings=24;mesh.mesh=sphere;mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;mesh.layers=2
		var finish=StandardMaterial3D.new();finish.resource_name="V15_BluePaint" if i==0 else "V15_GreenPaint";finish.albedo_color=Color(.12,.28,.35) if i==0 else Color(.105,.235,.205);finish.roughness=.62;mesh.material_override=finish;ball.add_child(mesh)
		var shape=CollisionShape3D.new();var contact=SphereShape3D.new();contact.radius=.203;shape.shape=contact;ball.add_child(shape);cargo.append(ball)
	_reset_cargo()
	hint_layer=CanvasLayer.new();hint_layer.layer=10;add_child(hint_layer);door_hint=Label.new();hint_layer.add_child(door_hint)
	door_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);door_hint.offset_left=-400;door_hint.offset_right=400;door_hint.offset_top=-215;door_hint.offset_bottom=-165
	door_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;door_hint.add_theme_font_size_override("font_size",24);door_hint.add_theme_color_override("font_color",Color(1,.90,.64));door_hint.add_theme_color_override("font_outline_color",Color(.06,.045,.03));door_hint.add_theme_constant_override("outline_size",5);door_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE

func _reset_cargo() -> void:
	for i in cargo.size():
		cargo[i].global_position=carriage.to_global(Vector3(.3565+i*.54,.72,0));cargo[i].linear_velocity=Vector3.ZERO;cargo[i].angular_velocity=Vector3.ZERO;cargo[i].sleeping=false;cargo[i].reset_physics_interpolation()

func prompt_text() -> String:
	if seated:return "W / S 驾驶 · E 离开驾驶椅"
	var local=carriage.to_local(room.actor.global_position)
	if door_open and absf(local.x-CAB_X)<.3 and absf(local.z)<.32 and local.y>.40:return "E 坐到驾驶椅"
	if room.actor.global_position.distance_to(carriage.to_global(Vector3(CAB_X,.50,.65)))<.80:
		return "E 关门 · 小火车" if door_open else "E 开门 · 小火车"
	return ""
func seat_point() -> Vector3:return carriage.to_global(Vector3(CAB_X+.10,.52,0))
func handle_input(event:InputEvent) -> bool:
	if not room.ready_to_play or room.paused:return false
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E:
		if seated:leave_seat();return true
		var local=carriage.to_local(room.actor.global_position)
		if door_open and absf(local.x-CAB_X)<.3 and absf(local.z)<.32 and local.y>.40:
			board();return true
		if room.actor.global_position.distance_to(carriage.to_global(Vector3(CAB_X,.50,.65)))<.80:
			if absf(speed)>.05:room._show_toast("停车后再开门",2);return true
			door_open=not door_open;room._tone(220,.07,.16);room._show_toast("车门已打开 · 沿踏步进入，E 坐到驾驶椅" if door_open else "车门已关闭",4);return true
	return false
func board() -> bool:
	if seated or room.prop_interaction.held!=null:return false
	seated=true;door_open=false;prior_control=room.actor.can_control
	room.actor.can_control=false;room.actor.set_physics_process(false);room.actor.state="train";room.actor.velocity=Vector3.ZERO;room.actor.ground_motion=false;room.actor.locomotion.release_feet()
	room.actor.player.play("anime/wait",.12);room.actor.player.speed_scale=0
	room._show_toast("W 前进 · S 后退 · 松开减速 · E 离开座位",5);return true
func leave_seat() -> void:
	if not seated:return
	speed=0;seated=false;door_open=true
	room.actor.position=carriage.to_global(Vector3(CAB_X,.44,.273));room.actor.can_control=prior_control;room.actor.state="idle";room.actor.player.speed_scale=1;room.actor.set_physics_process(true);room.actor.reset_physics_interpolation()
	room.actor.restore_action_pose()
func reset_train() -> void:
	leave_seat();rail_position=2.25;carriage.position.x=rail_position;speed=0;door_open=false;carriage.reset_physics_interpolation()
	_reset_cargo()
func _physics_process(delta:float) -> void:
	if not room.ready_to_play:return
	door_hint.text=prompt_text();door_hint.visible=not room.paused and room.hud.visible and not door_hint.text.is_empty()
	var inside=carriage.to_local(room.actor.get_global_transform_interpolated().origin)
	camera_active=seated or (absf(inside.x-CAB_X)<.28 and absf(inside.z)<.34 and inside.y>.39 and inside.y<1.0)
	var throttle=test_throttle if input_override else (Input.get_action_strength("move_forward")-Input.get_action_strength("move_back"))
	if not seated:throttle=0
	speed=move_toward(speed,-throttle*maximum_speed,(maximum_speed if absf(throttle)>.01 else maximum_speed*1.8)*delta)
	var travel=speed*delta;rail_position=clampf(rail_position+travel,0,2.6)
	if (rail_position<=0 and speed<0) or (rail_position>=2.6 and speed>0):speed=0
	carriage.position.x=rail_position
	for ball in cargo:
		if absf(speed)>.01:ball.sleeping=false
	for wheel in wheels:wheel.rotate_object_local(Vector3.BACK,-travel/.192*(1 if wheel.position.z<0 else -1))
	door_angle=move_toward(door_angle,deg_to_rad(-105) if door_open else 0,delta*3.8);door.rotation.y=door_angle
	if seated:
		room.actor.global_position=seat_point();room.actor.heading_yaw=PI;room.actor.visual.rotation.y=PI;room.actor.visual.position=Vector3.ZERO
	ride_sound.volume_db=lerpf(ride_sound.volume_db,-30+DRIVE_GAIN_DB if absf(speed)>.03 and room.sounds_enabled else -80,1-exp(-delta*12));ride_sound.pitch_scale=.65+absf(speed)*.4
	if absf(speed)>.03 and room.sounds_enabled and not ride_sound.playing:ride_sound.play()
	if ride_sound.volume_db< -65:ride_sound.stop()
