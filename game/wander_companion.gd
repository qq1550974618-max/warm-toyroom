extends Node
var commanded=false
var command_route:Array[Vector3]=[]
var command_wait=0.0
var command_hold=12.0
var command_waiting=false
var actor:CharacterBody3D
var room:Node3D
var target:=Vector3.ZERO
var activity_rate:=0.5
var pause_left:=2.8
var manual_hold:=false
var manual_anchor:=Vector3.ZERO
var manual_heading:=0.0
var walking_time:=0.0
var walked_distance:=0.0
var pauses:=0
var last_position:=Vector3.ZERO
var rng:=RandomNumberGenerator.new()
var steering_time:=0.0
var steering:=Vector3.ZERO
var obstacle_hit:=KinematicCollision3D.new()
var command_jump_cooldown=0.0
var patrol:=[Vector3(-1.2,0,3.4),Vector3(1.5,0,4.1),Vector3(3.8,0,2.8),Vector3(-4.2,0,4.5),Vector3(-.5,0,5.8)]
func _ready() -> void:
	process_physics_priority=-15;rng.seed=9364;actor.can_control=false;actor.input_override=true;actor.override_sprint=false;last_position=actor.position
func _physics_process(delta:float) -> void:
	if not room.ready_to_play or actor==room.actor:return
	walked_distance+=Vector2(actor.position.x-last_position.x,actor.position.z-last_position.z).length();last_position=actor.position
	if commanded:
		_update_command(delta);return
	if manual_hold:
		actor.override_direction=Vector3.ZERO;actor.override_jump=false;actor.override_sprint=false;actor.push_speed_override=-1
		return
	if actor.state in ["flattened","stunned","roll","dash"]:actor.override_direction=Vector3.ZERO;return
	if pause_left>0:
		actor.override_direction=Vector3.ZERO;pause_left-=delta
		if pause_left<=0:target=_pick_patrol_target();walking_time=0
		return
	walking_time+=delta
	var d:=target-actor.position;d.y=0
	if d.length()<.18 or walking_time>8:
		# Lengthen the entire walk/rest cycle to halve walk starts per minute,
		# retaining the same actual walking speed and distance-driven gait.
		var base_pause=rng.randf_range(1.1,3.4)
		pause_left=(walking_time+base_pause)/activity_rate-walking_time
		pauses+=1;actor.override_direction=Vector3.ZERO;return
	var desired:=d.normalized();steering_time-=delta
	if actor.test_move(actor.global_transform,desired*.42):
		if steering_time<=0:
			steering_time=.65
			for angle in [.75,-.75,1.5,-1.5,2.4,-2.4]:
				var side:=desired.rotated(Vector3.UP,angle)
				if not actor.test_move(actor.global_transform,side*.48):steering=side;break
		desired=steering
	actor.override_direction=desired

func _pick_patrol_target() -> Vector3:
	if room.puzzles!=null:
		var local_target=room.puzzles.patrol_target(actor.global_position,rng)
		if local_target!=Vector3.INF:return local_target
	return patrol[rng.randi_range(0,patrol.size()-1)]

func set_manual_hold(enabled:bool) -> void:
	manual_hold=enabled;actor.override_direction=Vector3.ZERO;actor.override_jump=false
	if enabled:manual_anchor=actor.position;manual_heading=actor.heading_yaw
	actor.override_sprint=false;actor.push_speed_override=-1
	if actor.stunt_mode=="":actor.input_override=true;actor.can_control=false
	if not enabled:pause_left=2.8;walking_time=0;steering_time=0
	set_physics_process(true)

func restore_manual_anchor() -> void:
	if not manual_hold:return
	actor.position=manual_anchor;actor.velocity=Vector3.ZERO
	actor.heading_yaw=manual_heading;actor.visual.rotation.y=manual_heading
	actor.input_override=true;actor.can_control=false;actor.override_direction=Vector3.ZERO
	actor.override_jump=false;actor.override_sprint=false;actor.push_speed_override=-1
	actor.reset_physics_interpolation();set_physics_process(true)

func command_walk(point:Vector3,wait_seconds:float=12.0) -> void:
	manual_hold=false;commanded=true;command_waiting=false;command_hold=wait_seconds;command_wait=0
	command_route=room.puzzles.navigation_path(actor.global_position,point)
	actor.override_direction=Vector3.ZERO;actor.override_sprint=false;actor.input_override=true;actor.can_control=false;actor.push_speed_override=-1;set_physics_process(true)

func command_stop(seconds:float=12.0) -> void:
	manual_hold=false;commanded=true;command_waiting=true;command_wait=seconds;command_route.clear()
	actor.override_direction=Vector3.ZERO;actor.override_jump=false;actor.push_speed_override=-1;set_physics_process(true)

func command_cancel() -> void:
	commanded=false;command_waiting=false;manual_hold=false;command_route.clear();pause_left=2.8;walking_time=0;actor.push_speed_override=-1;actor.override_direction=Vector3.ZERO
	if actor.has_meta("join_coop"):actor.remove_meta("join_coop")

func _update_command(delta:float) -> void:
	command_jump_cooldown=maxf(0,command_jump_cooldown-delta)
	if room.puzzles.is_pulling(actor) or room.puzzles.is_using_lift(actor):actor.override_direction=Vector3.ZERO;return
	if actor.state in ["flattened","stunned","roll","dash"] or actor.stunt_mode!="":actor.override_direction=Vector3.ZERO;return
	if command_waiting:
		actor.override_direction=Vector3.ZERO;command_wait-=delta
		if command_wait<=0:
			command_cancel()
		return
	if command_route.is_empty():command_stop(command_hold);return
	var d=command_route[0]-actor.global_position;d.y=0
	if d.length()<.085:
		command_route.pop_front();actor.override_direction=Vector3.ZERO
		if command_route.is_empty():command_stop(command_hold)
		return
	var desired=d.normalized();steering_time-=delta
	var blocked=actor.test_move(actor.global_transform,desired*.20,obstacle_hit)
	if blocked and obstacle_hit.get_normal().y>.55:blocked=false
	var rise=command_route[0].y-actor.global_position.y
	if blocked and actor.is_on_floor() and command_jump_cooldown<=0 and not room.puzzles.in_low_passage(actor.global_position):
		var raised=actor.global_transform;raised.origin.y+=.42
		if rise<.53 and not actor.test_move(raised,desired*.38):
			actor.override_jump=true;command_jump_cooldown=1.0;blocked=false
	if blocked:
		if steering_time<=0:
			steering_time=.3;steering=Vector3.ZERO
			for angle in [.6,-.6,1.1,-1.1,1.6,-1.6]:
				var side=desired.rotated(Vector3.UP,angle)
				if not actor.test_move(actor.global_transform,side*.22):steering=side;break
		desired=steering
	actor.override_direction=desired;actor.push_speed_override=minf(.72,d.length()*4)
