extends "res://character.gd"

signal magic_requested(direction: Vector3)
var game: Node
var heading_yaw := PI/2.0
var spawn_heading := PI/2.0
var cast_direction := Vector3.FORWARD
var walk_distance := 0.0
var idle_seconds := 0.0
var completed_idle_cycles := 0
var death_seconds := 0.0
var walk_reference_speed := 0.19713
const WALK_GAIT_SPEED := 0.45
const RUN_GAIT_SPEED := 1.40
var movement_walk_speed := 0.30
var movement_run_speed := 0.85
var movement_air_speed := 1.15
var gait_translation_scale := 1.0
var visual_scale := 0.5
var jump_velocity := 3.5
var input_override := false
var override_direction := Vector3.ZERO
var override_sprint := true
var override_jump := false

func _physics_process(delta: float) -> void:
	if player == null: return
	if state=="dead":
		action_time+=delta
		if not is_on_floor(): velocity.y-=GRAVITY*delta
		velocity.x=0; velocity.z=0; move_and_slide()
		ground_motion=false
		return
	if state in ["hurt","cast","victory"]:
		_special_action(delta)
		return
	var input := Input.get_vector("move_left","move_right","move_forward","move_back") if can_control else Vector2.ZERO
	var right := camera.global_basis.x
	var back := camera.global_basis.z
	right.y = 0; back.y = 0
	var direction := (right.normalized()*input.x+back.normalized()*input.y).normalized()
	if input_override:
		direction = override_direction.normalized()
		input = Vector2(1,0) if direction.length_squared()>0.01 else Vector2.ZERO
	if direction.length_squared()>0.01: heading_yaw = atan2(-direction.z,direction.x)
	if can_control and Input.is_action_just_pressed("cast") and is_on_floor() and state not in ["prepare","air"]:
		cast_direction = game.aim_direction(Basis(Vector3.UP,heading_yaw)*Vector3.RIGHT)
		heading_yaw = atan2(-cast_direction.z,cast_direction.x)
		visual.rotation.y = heading_yaw
		state = "cast"; action_time = 0; action_fired = false
		velocity.x = 0; velocity.z = 0
		player.play("free/cast",0.08); player.speed_scale = 1
		cast_count += 1
		locomotion.release_feet()
		return
	if (can_control and Input.is_action_just_pressed("jump")) or override_jump:
		jump_buffer = 0.14
		override_jump = false
	else: jump_buffer = maxf(0,jump_buffer-delta)
	coyote = 0.12 if is_on_floor() else maxf(0,coyote-delta)
	if jump_buffer>0 and coyote>0 and state not in ["prepare","land"]:
		state = "prepare"; jump_timer = 0.20 if extra_motion_set else 0.10; jump_buffer = 0
		_play("jump",0.09); player.speed_scale = 1.0 if extra_motion_set else 2.8
	if state == "prepare":
		jump_timer -= delta
		if jump_timer<=0:
			velocity.y = jump_velocity; state = "air"; coyote = 0; air_time = 0
			jump_count += 1; locomotion.release_feet()
	if not is_on_floor(): velocity.y -= GRAVITY*delta
	var sprinting:=can_control and Input.is_action_pressed("sprint")
	if input_override: sprinting = override_sprint
	gait_translation_scale = 1.0
	var speed := movement_run_speed if sprinting else movement_walk_speed
	if sprinting and state in ["prepare", "air"]: speed = movement_air_speed
	var desired := direction*speed*input.length()
	velocity.x = move_toward(velocity.x,desired.x,delta*14*gait_translation_scale)
	velocity.z = move_toward(velocity.z,desired.z,delta*14*gait_translation_scale)
	var previous := global_position
	var grounded := is_on_floor()
	if grounded and state not in ["air","prepare"]: _step_up3d(delta)
	move_and_slide()
	walk_distance += Vector2(global_position.x-previous.x,global_position.z-previous.z).length()
	if grounded and velocity.y<=0 and state not in ["air","prepare"] and not is_on_floor(): apply_floor_snap()
	if not grounded and is_on_floor() and state=="air":
		state = "land"; jump_timer = 0.36 if extra_motion_set else 0.20; land_count += 1
		_play("land",0.04); player.speed_scale = 1
	if not is_on_floor():
		air_time += delta
		if state not in ["prepare","air"] and air_time>0.12:
			state = "air"
			if extra_motion_set:_play("fall_air",0.1);player.speed_scale=1.0
			else:_play("jump",0.1);player.seek(0.65,true);player.speed_scale=1.5
	else: air_time = 0
	if state=="land":
		jump_timer -= delta
		if jump_timer<=0 or (extra_motion_set and jump_timer<0.18 and input.length()>0.1): state = "idle"
	var horizontal_speed := Vector2(velocity.x,velocity.z).length()
	ground_motion = is_on_floor() and state not in ["air","prepare"]
	if state not in ["air","prepare","land"]:
		if horizontal_speed>0.08:
			state = "run" if sprinting else "walk"
			_play("run" if sprinting else "walk",0.16)
			walk_reference_speed=float(player.get_animation_library("anime").get_meta("walk_reference_speed",0.635))
			# Animation cadence follows real travel at the exact half-size scale.
			player.speed_scale=horizontal_speed/maxf((source_root_speed if sprinting else walk_reference_speed)*visual_scale,0.05)
			idle_seconds = 0
		else:
			state = "idle"; _play("wait",0.18); player.speed_scale = 1
			idle_seconds += delta
			completed_idle_cycles = maxi(completed_idle_cycles,floori(idle_seconds/4.0))
	turning_amount = absf(wrapf(heading_yaw-visual.rotation.y,-PI,PI))
	visual.rotation.y = lerp_angle(visual.rotation.y,heading_yaw,1-exp(-delta*14))
	cloth_lag = cloth_lag.lerp(Vector3(-velocity.x,0,-velocity.z)*0.009,1-exp(-delta*5))
	if skirt_material != null: skirt_material.set_shader_parameter("cloth_lag",cloth_lag)

func _step_up3d(delta: float) -> void:
	var move := Vector3(velocity.x,0,velocity.z)*delta
	if move.length_squared()<0.000001: return
	move += move.normalized()*0.025*(visual_scale/.5)
	if not test_move(global_transform,move): return
	var raised := global_transform; raised.origin.y += 0.055*(visual_scale/.5)
	if not test_move(raised,move):
		global_position.y += 0.055*(visual_scale/.5)
		apply_floor_snap()

func _special_action(delta: float) -> void:
	action_time += delta
	if not is_on_floor(): velocity.y -= GRAVITY*delta
	velocity.x = move_toward(velocity.x,0,delta*6)
	velocity.z = move_toward(velocity.z,0,delta*6)
	move_and_slide()
	ground_motion = is_on_floor() and state!="hurt"
	turning_amount = 0
	if state=="cast" and not action_fired and action_time>=0.25:
		cast_direction=game.aim_direction(cast_direction)
		action_fired = true; magic_requested.emit(cast_direction)
	if (state=="cast" and action_time>=0.70) or (state=="hurt" and action_time>=0.38):
		state = "idle"; _play("wait",0.12); player.speed_scale = 1

func hurt_from(direction: Vector3) -> void:
	take_hit(1)
	velocity = direction.normalized()*1.6+Vector3.UP*1.45

func begin_death() -> float:
	state="dead"; can_control=false; action_time=0; ground_motion=false
	velocity.x=0; velocity.z=0; velocity.y=minf(velocity.y,0)
	jump_buffer=0; locomotion.release_feet(); visual.show()
	player.play(animation_names["fall"],0.12); player.speed_scale=1.25
	death_seconds=player.get_animation(animation_names["fall"]).length/1.25+0.65
	return death_seconds

func reset_position() -> void:
	super.reset_position()
	heading_yaw = spawn_heading
	visual.rotation.y = heading_yaw
	velocity = Vector3.ZERO
	state = "idle"; idle_seconds = 0
	reset_physics_interpolation()
	player.speed_scale=1; death_seconds=0; ground_motion=true

func celebrate() -> void:
	super.celebrate()
	velocity = Vector3.ZERO
