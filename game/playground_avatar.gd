extends "res://chibi_avatar3d.gd"

var playground:Node3D
var stunt_mode=""
var stunt_time=0.0
var stunt_pose:SkeletonModifier3D
var pose_mode=""
var pose_time=0.0
var flight_gravity=12.15
var flight_kind=""
var stunt_prior_control=false
var stunt_prior_override=false
var stunt_prior_mask=71
var stunt_start=Vector3.ZERO
var bowl_point=Vector3.ZERO
var press_target=Vector3.ZERO
var rice_charged=false
var stomp_active=false
var last_grounded_height=0.0
var launch_count=0
var meal_count=0
var meal_spin_angle=0.0
var meal_heading=0.0
var meal_orbit_radius=0.0
var maximum_fall_speed=0.0
var maximum_flight_height=0.0

func setup(view_camera:Camera3D) -> void:
	super.setup(view_camera)
	platform_on_leave=CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	stunt_pose=preload("res://playground_pose.gd").new();stunt_pose.actor=self;skeleton.add_child(stunt_pose)

func _physics_process(delta:float) -> void:
	if stunt_mode!="":
		stunt_time+=delta;pose_time+=delta
		ground_motion=false;locomotion.release_feet()
		if stunt_mode=="flight":_flight_step(delta)
		elif stunt_mode=="meal":_meal_step(delta)
		elif stunt_mode=="press":
			velocity=Vector3(0,-.4,0);move_and_slide()
			if stunt_time>=.52:_finish_stunt()
		return
	if is_on_floor():last_grounded_height=global_position.y
	if rice_charged and state!="dash" and not is_on_floor() and velocity.y<0 and last_grounded_height>4.1:
		stomp_active=true;pose_mode="dive";pose_time+=delta
	var before=global_position
	var incoming=velocity
	# Height and rice never change ordinary horizontal control or fall gravity.
	air_control_multiplier=1.0
	super._physics_process(delta)
	maximum_fall_speed=maxf(maximum_fall_speed,-incoming.y)
	if playground!=null and incoming.y< -2.6:_report_board_contact(incoming,before)
	if stomp_active and is_on_floor():stomp_active=false;pose_mode=""

func _begin_stunt(mode:String) -> void:
	if stunt_mode=="":
		stunt_prior_control=can_control;stunt_prior_override=input_override;stunt_prior_mask=collision_mask
	if state in ["roll","dash","stunned"]:_end_roll()
	if mode!="flight" and game.prop_interaction.held!=null and self==game.actor:game.prop_interaction.drop()
	can_control=false;input_override=false;override_direction=Vector3.ZERO;override_jump=false
	stunt_mode=mode;stunt_time=0;pose_time=0;state="stunt";ground_motion=false
	locomotion.release_feet();gait_weight=0;roll_weight=0
	player.play("anime/wait",.08);player.speed_scale=0;player.seek(0,true)

func start_flight(initial_velocity:Vector3,kind:String="table",gravity_value:float=12.15) -> void:
	_begin_stunt("flight");flight_kind=kind
	# Time-scale the whole ballistic arc, preserving its apex and landing point.
	var flight_rate=.50 if kind=="roof" else 1.0
	flight_gravity=gravity_value*flight_rate*flight_rate;velocity=initial_velocity*flight_rate
	pose_mode="dive" if kind=="drop_power" else "launch"
	stomp_active=kind=="drop_power";launch_count+=1;maximum_flight_height=global_position.y
	if playground!=null:
		add_collision_exception_with(playground.beam)
		get_tree().create_timer(.16).timeout.connect(func():
			if is_instance_valid(playground):remove_collision_exception_with(playground.beam))
	if Vector2(velocity.x,velocity.z).length()>.01:heading_yaw=atan2(-velocity.z,velocity.x)

func start_press(target:Vector3) -> void:
	_begin_stunt("press");pose_mode="press";press_target=target;velocity=Vector3.ZERO
	var d=target-global_position;heading_yaw=atan2(-d.z,d.x);visual.rotation.y=heading_yaw

func start_meal(point:Vector3) -> void:
	_begin_stunt("meal");pose_mode="meal_jump";stunt_start=global_position;bowl_point=point
	velocity=Vector3.ZERO;collision_mask=0;springs.active=false;meal_count+=1;meal_spin_angle=0.0
	meal_heading=heading_yaw;meal_orbit_radius=.205

func _flight_step(delta:float) -> void:
	var before=global_position
	if flight_kind=="roof" and playground!=null and playground.roof_broken:
		# Keep travelling upward beyond the hole until the five-second respawn.
		velocity.y=maxf(velocity.y,9.5)
	else:velocity.y-=flight_gravity*delta
	var incoming=velocity
	if flight_kind=="roof" and playground!=null:playground.check_roof_crossing(self,global_position+velocity*delta)
	move_and_slide()
	maximum_fall_speed=maxf(maximum_fall_speed,-incoming.y);maximum_flight_height=maxf(maximum_flight_height,global_position.y)
	var stretch=1.0+.07*sin(minf(stunt_time/.20,1)*PI)
	visual.basis=(Basis(Vector3.UP,heading_yaw)*Basis(Vector3.BACK,.10*sin(stunt_time*8)*exp(-stunt_time*2))).scaled(Vector3(1/stretch,stretch,1)*visual_scale)
	visual.position=Vector3.ZERO
	if flight_kind=="ram":
		var turn=TAU*smoothstep(.06,.76,stunt_time)
		var frame=Basis(Vector3.UP,heading_yaw)*Basis(Vector3.BACK,turn)
		visual.basis=frame.scaled(Vector3.ONE*visual_scale)
		visual.position=Vector3.UP*.20-frame*Vector3(0,.20,0)
	if playground!=null and incoming.y< -2.6:_report_board_contact(incoming,before)
	if flight_kind=="roof" and global_position.y>13.8:
		playground.companion_escaped()
	if is_on_floor() and stunt_time>.13 and incoming.y<0:
		land_count+=1;var old_kind=flight_kind;_finish_stunt();state="land";jump_timer=.16
		_play("land",.045);player.speed_scale=1.7
		if playground!=null:playground.character_landed(self,old_kind)

func _meal_step(_delta:float) -> void:
	if stunt_time<.48:
		var t=smoothstep(0,.48,stunt_time)
		var entry=bowl_point+Vector3(.205,0,0)
		global_position=stunt_start.lerp(entry,t)+Vector3.UP*sin(t*PI)*.64
		pose_mode="meal_jump";visual.rotation.y=heading_yaw
	elif stunt_time<2.95:
		var t=clampf((stunt_time-.48)/2.47,0,1)
		pose_mode="eat";pose_time=stunt_time-.48
		# Drive along a tightening spiral like a toy car. Heading follows the
		# path tangent only: there is no additional spin around the body's centre.
		var path_progress=t*t*(3.0-2.0*t)
		meal_spin_angle=TAU*2.65*path_progress
		meal_orbit_radius=.205*(1.0-path_progress)
		global_position=bowl_point+Vector3(cos(meal_spin_angle),0,-sin(meal_spin_angle))*meal_orbit_radius
		var radial_derivative=-.205
		var angular_derivative=TAU*2.65
		var tangent=Vector3(radial_derivative*cos(meal_spin_angle)-meal_orbit_radius*sin(meal_spin_angle)*angular_derivative,0,-radial_derivative*sin(meal_spin_angle)-meal_orbit_radius*cos(meal_spin_angle)*angular_derivative)
		meal_heading=lerp_angle(meal_heading,atan2(-tangent.z,tangent.x),1-exp(-_delta*16))
		var lean=smoothstep(0,.16,pose_time)*(1-smoothstep(.90,1,t))
		var frame=Basis(Vector3.UP,meal_heading)*Basis(Vector3.BACK,-PI*.5*lean)
		visual.basis=frame.scaled(Vector3.ONE*visual_scale)
		playground.set_rice_fraction(1-t)
		var rice_top=playground.rice_surface_height(meal_orbit_radius)
		visual.position=Vector3(0,rice_top+.055+.006*sin(pose_time*28),0)-frame*Vector3(.07,.40,0)*visual_scale
	else:
		rice_charged=true;stomp_active=false;playground.set_rice_fraction(0)
		collision_mask=stunt_prior_mask;springs.active=true;springs.reset()
		global_position=bowl_point+Vector3.UP*.41
		visual.position=Vector3.ZERO;visual.basis=Basis(Vector3.UP,heading_yaw).scaled(Vector3.ONE*visual_scale)
		var exit_target=playground.bowl_exit
		var velocity_out=playground.velocity_to(global_position,exit_target,playground.TABLE_Y+.88,12.15)
		start_flight(velocity_out,"meal_exit");playground.meal_finished(self)

func _report_board_contact(incoming:Vector3,before:Vector3) -> void:
	for i in get_slide_collision_count():
		var hit=get_slide_collision(i)
		if hit.get_collider()==playground.beam and hit.get_normal().y>.55:
			playground.character_hit_board(self,incoming,before);return

func _finish_stunt() -> void:
	stunt_mode="";pose_mode="";stomp_active=false;state="idle"
	visual.position=Vector3.ZERO;visual.basis=Basis(Vector3.UP,heading_yaw).scaled(Vector3.ONE*visual_scale)
	collision_mask=stunt_prior_mask;can_control=stunt_prior_control and not game.paused;input_override=stunt_prior_override
	player.speed_scale=1;springs.active=true;springs.reset();locomotion.release_feet()
	restore_action_pose()

func reset_position() -> void:
	if stunt_mode!="":_finish_stunt()
	rice_charged=false;stomp_active=false;pose_mode="";show();super.reset_position()
