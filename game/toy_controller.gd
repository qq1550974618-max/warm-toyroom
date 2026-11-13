extends "res://avatar3d.gd"

var motion_scale := 0.81
var gait_cadence_multiplier := 0.70
var gait_stride_multiplier := 0.85
var walking_amplitude_multiplier := 0.90
var gait_reach_adjustment := 0.90
var run_cadence_adjustment := 1.10
var push_speed_override := -1.0
var override_hold_jump := true
var air_control_multiplier := 1.0
var override_roll := false
var gait_phase := 0.0
var gait_rate := 1.65
var gait_weight := 0.0
var air_jumps_left := 0
var double_jump_count := 0
var dash_count := 0
var air_dash_available := true
var roll_count := 0
var roll_time := 0.0
var roll_distance := 0.0
var roll_angle := 0.0
var roll_weight := 0.0
var roll_radius := .1845
var roll_recovery := -1.0
var roll_recovery_angle := 0.0
var roll_cooldown := 0.0
var roll_direction := Vector3.RIGHT
var roll_collider: CollisionShape3D
var standing_colliders: Array[CollisionShape3D] = []
var air_takeoff_position := Vector3.ZERO
var last_jump_distance := 0.0
var jump_peak := 0.0
var push_contacts := 0
var maximum_walk_rate := 0.0

func _configure_controller() -> void:
	movement_walk_speed=.72*1.50*motion_scale;movement_run_speed=1.45*1.20*motion_scale;movement_air_speed=1.95*motion_scale;jump_velocity=4.85*motion_scale

func gait_stride_scale(running:bool) -> float:
	return gait_stride_multiplier*(1.0 if running else walking_amplitude_multiplier)*gait_reach_adjustment

func gait_frequency_scale(running:bool) -> float:
	return run_cadence_adjustment if running else 1.0

func gait_contact_fraction(running:bool) -> float:
	# Shorter leg reach is independent of cadence and world movement. Adjust
	# planted time with it so soles stay fixed instead of sliding under the body.
	return (.18 if running else .24)*gait_reach_adjustment*gait_frequency_scale(running)

func gait_body_amplitude(running:bool) -> float:
	return (1.0 if running else walking_amplitude_multiplier)*gait_reach_adjustment

func gait_cycle_distance(running:bool) -> float:
	# Keep v19 walking cadence; increase only running cadence by ten percent.
	# Do not derive cadence from the new visual reach a second time.
	var baseline_scale=gait_stride_multiplier*(1.0 if running else walking_amplitude_multiplier)
	return (1.45/2.45 if running else .72/1.72)*motion_scale/gait_cadence_multiplier*baseline_scale/gait_frequency_scale(running)

func _ensure_roll_collider() -> void:
	if roll_collider!=null:return
	for c in get_children():
		if c is CollisionShape3D:standing_colliders.append(c)
	roll_collider=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=roll_radius
	roll_collider.shape=sphere;roll_collider.position=Vector3(0,roll_radius,0);roll_collider.disabled=true;add_child(roll_collider)

func _physics_process(delta: float) -> void:
	if player==null:return
	_ensure_roll_collider();roll_cooldown=maxf(0,roll_cooldown-delta)
	if state=="dead":return
	if state in ["victory","hurt","cast"]:_special_action(delta);return
	var input:=Input.get_vector("move_left","move_right","move_forward","move_back") if can_control else Vector2.ZERO
	var right:=camera.global_basis.x;var back:=camera.global_basis.z;right.y=0;back.y=0
	var direction:Vector3=(right.normalized()*input.x+back.normalized()*input.y).normalized()
	var sprinting:=can_control and Input.is_action_pressed("sprint")
	if input_override:direction=override_direction.normalized();input=Vector2(1,0) if direction.length_squared()>.01 else Vector2.ZERO;sprinting=override_sprint
	var confined=game!=null and game.puzzles!=null and game.puzzles.in_low_passage(global_position)
	if confined and state=="dash":_end_roll();velocity.y=minf(velocity.y,0)
	var anchored=game!=null and game.puzzles!=null and (game.puzzles.is_using_lift(self) or game.puzzles.is_pulling(self))
	if anchored:direction=Vector3.ZERO;input=Vector2.ZERO;override_jump=false;override_roll=false;velocity=Vector3.ZERO
	var wants_roll:bool=(can_control and Input.is_action_just_pressed("roll")) or override_roll;override_roll=false
	if wants_roll and roll_cooldown<=0 and state not in ["roll","dash","prepare"]:
		if direction.length_squared()<.01:direction=Basis(Vector3.UP,heading_yaw)*Vector3.RIGHT
		if is_on_floor():_begin_roll(direction)
		elif air_dash_available and not confined:_begin_dash(direction)
	if state in ["roll","dash"]:_process_roll(delta);return
	# Commanded walking uses a speed cap, but must still turn toward its route.
	# Only the actual attached iron-ball push owns its facing direction.
	var attached_push=self==game.actor and game.iron_ball!=null and game.iron_ball.pushing
	if direction.length_squared()>.01 and not attached_push:heading_yaw=atan2(-direction.z,direction.x)
	turning_amount=absf(wrapf(heading_yaw-visual.rotation.y,-PI,PI));visual.rotation.y=lerp_angle(visual.rotation.y,heading_yaw,1-exp(-delta*16))
	var wants_jump:bool=(can_control and Input.is_action_just_pressed("jump")) or override_jump;override_jump=false
	if confined or anchored:wants_jump=false
	jump_buffer=.13 if wants_jump else maxf(0,jump_buffer-delta);coyote=.10 if is_on_floor() else maxf(0,coyote-delta)
	if jump_buffer>0 and state!="prepare":
		if coyote>0:
			state="prepare";jump_timer=.065;jump_buffer=0;_play("jump",.035);player.speed_scale=2.5;locomotion.release_feet()
	if state=="prepare":
		jump_timer-=delta
		if jump_timer<=0:
			velocity.x=direction.x*movement_air_speed*input.length();velocity.z=direction.z*movement_air_speed*input.length()
			velocity.y=jump_velocity;state="air";coyote=0;air_time=0;jump_count+=1;air_takeoff_position=global_position;jump_peak=global_position.y;air_jumps_left=0;air_dash_available=true
	var airborne:bool=not is_on_floor() or state=="air"
	if airborne:
		var gravity:=11.2 if velocity.y>0 else 15.0
		var held:bool=override_hold_jump if input_override else Input.is_action_pressed("jump")
		if velocity.y>0 and not held and air_time>.075:gravity*=1.85
		velocity.y-=gravity*motion_scale*delta
	var speed:float=movement_run_speed if sprinting else movement_walk_speed
	if push_speed_override>=0:speed=push_speed_override
	if airborne and push_speed_override<0:speed=movement_air_speed
	var desired:=direction*speed*input.length();var accel:float=4.8*air_control_multiplier if airborne else (7.0 if input.length()>.1 else 9.0)
	# A single horizontal acceleration vector avoids extra speed when turning diagonally.
	var horizontal=Vector2(velocity.x,velocity.z).move_toward(Vector2(desired.x,desired.z),accel*motion_scale*delta)
	if not airborne:horizontal=horizontal.limit_length(speed)
	velocity.x=horizontal.x;velocity.z=horizontal.y
	if not airborne and state!="prepare":velocity.y=-.5
	var before:=global_position;var grounded:=is_on_floor()
	if grounded and state not in ["air","prepare"]:_step_up3d(delta)
	move_and_slide();_push_rigid_bodies()
	var travelled:=Vector2(global_position.x-before.x,global_position.z-before.z).length();walk_distance+=travelled
	if grounded and state not in ["air","prepare"] and velocity.y<=0 and not is_on_floor():apply_floor_snap()
	if not grounded and is_on_floor():
		land_count+=1;last_jump_distance=Vector2(global_position.x-air_takeoff_position.x,global_position.z-air_takeoff_position.z).length();state="land";jump_timer=.13;air_jumps_left=0;air_dash_available=true
		_play("land",.03);player.speed_scale=2.1;locomotion.release_feet()
	if not is_on_floor():
		air_time+=delta;jump_peak=maxf(jump_peak,global_position.y)
		if state not in ["air","prepare"] and air_time>.06:state="air"
	else:air_time=0
	if state=="air":
		_play("jump",.04);player.speed_scale=0;player.seek(.27+.19*(1-clampf(velocity.y/jump_velocity,0,1)) if velocity.y>0 else .52+.20*clampf(-velocity.y/5,0,1),true)
	if state=="land":
		jump_timer-=delta
		if jump_timer<=0 or (jump_timer<.075 and input.length()>.1):state="idle"
	var actual_speed:float=travelled/maxf(delta,.001);ground_motion=is_on_floor() and state not in ["air","prepare","land"]
	gait_weight=move_toward(gait_weight,1.0 if ground_motion and actual_speed>.08 else 0.0,delta*10)
	if state not in ["air","prepare","land"]:
		if actual_speed>.06:
			state="run" if sprinting else "walk";_play("run" if sprinting else "walk",.10)
			# Phase follows actual travel; animation never adds character velocity.
			var stride_length:float=gait_cycle_distance(sprinting)
			gait_rate=maxf(.1,actual_speed/stride_length);gait_phase=fposmod(gait_phase+delta*gait_rate,1.0)
			player.speed_scale=gait_rate*player.get_animation(player.assigned_animation).length
			if state=="walk":maximum_walk_rate=maxf(maximum_walk_rate,player.speed_scale)
			idle_seconds=0
		else:state="idle";_play("wait",.15);player.speed_scale=1;idle_seconds+=delta
	visual.position=Vector3.ZERO;visual.rotation.z=0

func _begin_roll(direction: Vector3) -> void:
	state="roll";roll_direction=direction.normalized();heading_yaw=atan2(-direction.z,direction.x)
	roll_time=0;roll_distance=0;roll_angle=0;roll_recovery=-1;roll_weight=0;roll_count+=1;ground_motion=false;locomotion.release_feet()
	player.play("anime/wait",0);player.speed_scale=0;springs.active=false
	for c in standing_colliders:c.set_deferred("disabled",true)
	roll_collider.set_deferred("disabled",false)

func _begin_dash(direction: Vector3) -> void:
	state="dash";air_dash_available=false;dash_count+=1;roll_direction=direction.normalized();heading_yaw=atan2(-direction.z,direction.x)
	roll_time=0;roll_weight=0;roll_angle=0;velocity.y=maxf(velocity.y,0)*.25;ground_motion=false;locomotion.release_feet();springs.active=false

func _process_roll(delta: float) -> void:
	roll_time+=delta;ground_motion=false
	if state=="dash":
		roll_weight=sin(clampf(roll_time/.34,0,1)*PI)*.94;roll_angle=-TAU*clampf(roll_time/.34,0,1)
		velocity.x=roll_direction.x*3.5*motion_scale;velocity.z=roll_direction.z*3.5*motion_scale;velocity.y-=3*motion_scale*delta
		move_and_slide();_push_rigid_bodies();_roll_visual()
		if roll_time>=.34 or is_on_floor():
			var landed:=is_on_floor();_end_roll()
			if landed:
				land_count+=1;state="land";jump_timer=.12;air_jumps_left=0;air_dash_available=true;_play("land",.03);player.speed_scale=2.1
		return
	if roll_recovery>=0:
		roll_recovery+=delta;var t:=clampf(roll_recovery/.14,0,1);roll_weight=1-smoothstep(0,1,t);roll_angle=lerpf(roll_recovery_angle,roundf(roll_recovery_angle/TAU)*TAU,smoothstep(0,1,t))
		velocity.x=0;velocity.z=0
	else:
		roll_weight=smoothstep(0,.085,roll_time);var remaining:float=TAU*roll_radius-roll_distance;var speed:float=minf(3.25*roll_weight,remaining/maxf(delta,.001))
		velocity.x=roll_direction.x*speed;velocity.z=roll_direction.z*speed
	if not is_on_floor():velocity.y-=15*motion_scale*delta
	var before:=global_position;move_and_slide();_push_rigid_bodies();var distance:=Vector2(global_position.x-before.x,global_position.z-before.z).length()
	if roll_recovery<0:
		roll_distance+=distance;roll_angle=-roll_distance/roll_radius
		if roll_distance>=TAU*roll_radius-.004 or roll_time>1.1 or (is_on_wall() and roll_time>.12):roll_recovery=0;roll_recovery_angle=roll_angle
	_roll_visual()
	if roll_recovery>=.14:_end_roll()

func _roll_visual() -> void:
	var basis:=Basis(Vector3.UP,heading_yaw)*Basis(Vector3.BACK,roll_angle)
	visual.basis=basis.scaled(Vector3.ONE*visual_scale)
	var pivot:=Vector3(.22,.50,.002)*visual_scale
	visual.position=(Vector3(0,roll_radius,0)-basis*pivot)*roll_weight

func _end_roll() -> void:
	state="idle" if is_on_floor() else "air";roll_weight=0;roll_angle=0;roll_cooldown=.15
	visual.basis=Basis(Vector3.UP,heading_yaw).scaled(Vector3.ONE*visual_scale);visual.position=Vector3.ZERO
	for c in standing_colliders:c.set_deferred("disabled",false)
	if roll_collider!=null:roll_collider.set_deferred("disabled",true)
	springs.active=true;springs.reset();locomotion.release_feet();player.speed_scale=1
	if has_method("restore_action_pose"):call("restore_action_pose")

func _push_rigid_bodies() -> void:
	for i in get_slide_collision_count():
		var hit:=get_slide_collision(i);var body:=hit.get_collider()
		if body is RigidBody3D and not body.get_meta("heavy_push_only",false):
			var direction:Vector3=-hit.get_normal();direction.y=0
			if direction.length_squared()<.05:continue
			direction=direction.normalized();var strength:float=clampf(Vector2(velocity.x,velocity.z).length(),.25,3.4)
			body.apply_impulse(direction*body.mass*strength*.85,hit.get_position()-body.global_position);push_contacts+=1

func reset_position() -> void:
	if roll_collider!=null:_end_roll()
	super.reset_position();visual.position=Vector3.ZERO;air_jumps_left=0;air_dash_available=true;roll_weight=0;gait_weight=0;roll_cooldown=0
