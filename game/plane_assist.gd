extends Node
var room
var phase="idle"
var phase_time=0.0
var route_index=0
var route:Array[Vector3]=[]
var standing_time=0.0
var npc
var plane
var arm_weight=0.0
var arm_target=Vector3.ZERO
var body_bend=0.0
var grip_local=Vector3(0,-.075,.055)
var held
var held_basis=Basis.IDENTITY
var carry_offset=Vector3(0,.425,0)
var lift_start=Transform3D.IDENTITY
var restore_auto=true
var successful_throws=0
var step_jump_cooldown=0.0
func _ready() -> void:
	npc=room.companion;plane=room.paper_plane;process_physics_priority=-45
	var pose=preload("res://carry_pose.gd").new();pose.actor=npc;pose.interaction=self;npc.skeleton.add_child(pose)
func begin() -> bool:
	if phase!="idle":room._show_toast("同伴正在准备纸飞机",2);return false
	var nearest=INF
	for prop in room.physics_props:
		if prop.get_meta("kind","")=="plane" and not prop.gliding and not prop.freeze:
			var distance=prop.position.distance_to(npc.position)
			if distance<nearest:nearest=distance;plane=prop
	if npc.position.distance_to(room.actor.position)>3.2 or plane.position.distance_to(npc.position)>3.2 or plane.gliding or plane.freeze or room.prop_interaction.held==plane:
		room._show_toast("需要同伴和纸飞机都在附近，且飞机没有被拿起",4);return false
	if npc.position.y<4.1 or absf(plane.position.y-npc.position.y)>1:
		room._show_toast("先把同伴和纸飞机带到书桌上，再准备滑翔",4);return false
	room.playground.release_board_wait()
	restore_auto=room.playground.automatic_ai;room.playground.automatic_ai=false;room.playground.ai_mode="manual"
	npc.get_node("WanderMind").set_physics_process(false);npc.input_override=true;npc.override_sprint=false
	phase="approach";phase_time=0;room._show_toast("同伴去拿纸飞机，再走到桌边等你",4);return true
func cancel() -> void:
	if phase=="idle":return
	if held!=null:room.prop_interaction._restore_body_contacts(held);held.freeze=false;held.assisted_holder=null;held.release_carrier();held=null
	npc.override_direction=Vector3.ZERO;npc.push_speed_override=-1;npc.get_node("WanderMind").set_physics_process(true)
	room.playground.automatic_ai=restore_auto;phase="idle";arm_weight=0;standing_time=0
func _physics_process(delta:float) -> void:
	if phase=="idle" or not room.ready_to_play:return
	phase_time+=delta
	step_jump_cooldown=maxf(0,step_jump_cooldown-delta)
	if npc.state in ["flattened","stunned","dead"] or npc.stunt_mode!="" or npc.position.y<3.7:cancel();return
	if phase=="approach":
		var d=plane.position-npc.position;d.y=0;npc.override_direction=d.normalized() if d.length()>.20 else Vector3.ZERO
		if plane.position.y-npc.position.y>.28 and d.length()<.9 and npc.is_on_floor():npc.override_jump=true
		if d.length()<.65 and absf(plane.position.y-npc.position.y)<.58:
			held=plane;plane.freeze=true;room.prop_interaction._suspend_body_contacts(plane);plane.freeze_mode=RigidBody3D.FREEZE_MODE_KINEMATIC;plane.assisted_holder=npc;plane.set_carrier(npc);lift_start=plane.global_transform;phase="lift";phase_time=0;npc.override_direction=Vector3.ZERO
		elif phase_time>12:cancel();room._show_toast("同伴没能走到纸飞机旁，请挪开障碍后再试",4)
	elif phase=="lift":
		arm_weight=smoothstep(0,.25,phase_time);body_bend=.18*sin(clampf(phase_time/.8,0,1)*PI)
		var target=Transform3D(Basis(Vector3.UP,npc.heading_yaw),npc.position+Basis(Vector3.UP,npc.heading_yaw)*carry_offset)
		var lift=preload("res://plane_lift.gd").sample(lift_start,target,npc.position,Basis(Vector3.UP,npc.heading_yaw),clampf((phase_time-.20)/.78,0,1))
		plane.global_transform=lift.transform;grip_local=lift.grip;arm_target=plane.position
		if phase_time>.98:
			phase="walk_edge";phase_time=0;route_index=0
			route=[Vector3(npc.position.x,0,-5.50),Vector3(3.12,0,-5.50),Vector3(2.84,0,-4.90)]
	elif phase=="walk_edge":
		var d=route[route_index]-npc.position;d.y=0;npc.override_direction=d.normalized() if d.length()>.06 else Vector3.ZERO
		npc.push_speed_override=clampf(d.length()*2,.18,.58)
		if npc.is_on_floor() and npc.is_on_wall() and step_jump_cooldown<=0:
			npc.override_jump=true;step_jump_cooldown=.9
		if d.length()<.08:
			route_index+=1
			if route_index>=route.size():phase="wait_rider";phase_time=0;npc.override_direction=Vector3.ZERO;room._show_toast("同伴已举稳飞机 · 跳上机翼站稳 1 秒即可出发",5)
		if phase_time>20:cancel();room._show_toast("桌边路径被挡住了，请调整附近物品",4)
	elif phase=="wait_rider":
		npc.override_direction=Vector3.ZERO
		var d=Vector3(-4.05,0,-3.35)-npc.position;d.y=0;npc.heading_yaw=atan2(-d.z,d.x);npc.visual.rotation.y=lerp_angle(npc.visual.rotation.y,npc.heading_yaw,1-exp(-delta*8))
		standing_time=standing_time+delta if plane.is_riding(room.actor) else 0.0
		if standing_time>=1:phase="throw";phase_time=0
	elif phase=="throw":
		body_bend=.10*sin(clampf(phase_time/.24,0,1)*PI)
		if phase_time>=.24:
			var target=Vector3(-4.08,3.08,-3.35);var d=target-plane.position;d.y=0
			plane.sink_speed=clampf((plane.position.y-target.y)/(d.length()/3.2),.35,1.0)
			room.prop_interaction._restore_body_contacts(plane);plane.assisted_holder=null;plane.launch_glide(d.normalized()*3.2);held=null;successful_throws+=1;phase="recover";phase_time=0;room._show_toast("出发！可以在飞机上站立、走动或跳下",3)
	elif phase=="recover":
		arm_weight=1-smoothstep(0,.45,phase_time)
		if phase_time>.5:cancel()
	if held!=null and phase in ["walk_edge","wait_rider","throw"]:
		var frame=Basis(Vector3.UP,npc.visual.rotation.y);plane.global_transform=Transform3D(frame,npc.position+frame*carry_offset);arm_target=plane.position;arm_weight=1
