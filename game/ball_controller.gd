extends "res://toy_controller.gd"

const BALL_CROUCH_TIME=0.28
const BALL_READY_TIME=0.43
var ball_entry_velocity=Vector3.ZERO
var ball_contact_ready=false

var override_roll_hold:=false
var ball_velocity:=Vector3.ZERO
var ball_initial_speed:=.729
var ball_acceleration:=1.62
var ball_max_speed:=4.698
var ball_coast_drag:=.4455
var ball_release_drag:=2.835
var ball_releasing:=false
var ball_peak_speed:=0.0
var impact_count:=0
var impact_speed:=0.0
var impact_normal:=Vector3.ZERO
var impact_position:=Vector3.ZERO
var impact_recoil_distance:=0.0
var stun_time:=0.0
var stun_duration:=2.0
var stun_elapsed_record:=0.0
var last_stun_duration:=0.0
var stun_heading:=0.0
var stun_start_visual:=Transform3D.IDENTITY
var dizzy_stars:Node3D
var roll_audio:AudioStreamPlayer3D
var hit_audio:AudioStreamPlayer3D
var dizzy_audio:AudioStreamPlayer3D
var audio_peak_db:=-80.0
var fold_support:Array=[]
var flat_time:=0.0
var flat_count:=0
var flat_duration:=8.0
var flat_start:=Transform3D.IDENTITY
var flat_pose_offset:Vector3=Vector3.ZERO
var flat_prior_control:=true
var flat_collision:CollisionShape3D
var crushing_ball:RigidBody3D
var roll_hit_cooldown=0.0
var roll_launch_hits=0
const ROLL_LAUNCH_THRESHOLD=.70
var flat_paper:MeshInstance3D
var flat_footprint=Vector2.ZERO
var flat_model_bounds:=AABB()
var flat_mesh_cache:Array[MeshInstance3D]=[]
var flat_meshes_visible:=true
var flat_turn_query:PhysicsShapeQueryParameters3D
var cue_mode=""
var cue_owner:Node3D
var cue_clock=0.0
var cue_rebounds=0

func prepare_action_effects() -> void:
	_ensure_roll_collider();_ensure_effects()
	if flat_collision==null:
		flat_collision=CollisionShape3D.new();flat_collision.name="FlattenedContact"
		var shape:=BoxShape3D.new();shape.size=Vector3(.30,.025,.24);shape.margin=.001;flat_collision.shape=shape
		flat_collision.position.y=.025;flat_collision.disabled=true;add_child(flat_collision)
	if flat_mesh_cache.is_empty():
		for mesh in visual.find_children("*","MeshInstance3D",true,false):flat_mesh_cache.append(mesh)
	_make_flat_paper()

func _physics_process(delta:float) -> void:
	roll_hit_cooldown=maxf(0,roll_hit_cooldown-delta)
	_ensure_effects()
	if cue_mode!="":_process_cue_roll(delta)
	elif state=="flattened":_process_flatten(delta)
	elif state=="stunned":_process_stun(delta)
	else:super._physics_process(delta)
	_update_effects(delta)

func _ball_input() -> Vector3:
	if input_override:return override_direction.normalized()
	if not can_control:return Vector3.ZERO
	var axes:=Input.get_vector("move_left","move_right","move_forward","move_back")
	var right:=camera.global_basis.x;right.y=0;var back:=camera.global_basis.z;back.y=0
	return (right.normalized()*axes.x+back.normalized()*axes.y).limit_length(1)

func _begin_roll(direction:Vector3) -> void:
	if fold_support.is_empty():
		var support_data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/ground_fold_support.json"))
		fold_support=support_data.support
	var initial:float=maxf(ball_initial_speed,Vector2(velocity.x,velocity.z).length())
	ball_entry_velocity=Vector3(velocity.x,0,velocity.z);ball_contact_ready=false
	roll_radius=.14*motion_scale
	roll_collider.shape.radius=roll_radius;roll_collider.position.y=roll_radius
	super._begin_roll(direction)
	# Keep the upright contact until the visible crouch is nearly complete.
	for c in standing_colliders:c.set_deferred("disabled",false)
	roll_collider.set_deferred("disabled",true)
	ball_velocity=direction.normalized()*minf(initial,ball_max_speed);ball_releasing=false;ball_peak_speed=ball_velocity.length()

func _end_roll() -> void:
	super._end_roll();roll_radius=.205*motion_scale

func _begin_dash(direction:Vector3) -> void:
	roll_radius=.205*motion_scale;super._begin_dash(direction)

func _process_roll(delta:float) -> void:
	# The original aerial roll is delegated verbatim; only ground ball movement is replaced.
	if state=="dash":super._process_roll(delta);return
	roll_time+=delta;ground_motion=false
	var held:bool=override_roll_hold if input_override else (can_control and Input.is_action_pressed("roll"))
	if not held:ball_releasing=true
	if roll_recovery>=0:
		roll_recovery+=delta;var t:=clampf(roll_recovery/.20,0,1);roll_weight=1-smoothstep(0,1,t)
		roll_angle=lerpf(roll_recovery_angle,roundf(roll_recovery_angle/TAU)*TAU,smoothstep(0,1,t));velocity.x=0;velocity.z=0
		if not is_on_floor():velocity.y-=15*motion_scale*delta
		move_and_slide();_roll_visual()
		if t>=1:_end_roll()
		return
	roll_weight=smoothstep(BALL_CROUCH_TIME,BALL_READY_TIME,roll_time)
	if not ball_contact_ready and roll_time>=BALL_CROUCH_TIME:
		ball_contact_ready=true
		for c in standing_colliders:c.set_deferred("disabled",true)
		roll_collider.set_deferred("disabled",false)
	if roll_time<BALL_READY_TIME:
		# Settle existing momentum while bending; do not spin a standing doll.
		var settle=1.0-smoothstep(0,.18,roll_time)
		velocity.x=ball_entry_velocity.x*settle;velocity.z=ball_entry_velocity.z*settle
		velocity.y=-.5 if is_on_floor() else velocity.y-15*motion_scale*delta
		move_and_slide();_roll_visual();return
	var direction:=_ball_input()
	if held and not ball_releasing and direction.length_squared()>.01:
		ball_velocity=ball_velocity.move_toward(direction*ball_max_speed,ball_acceleration*delta)
	else:
		ball_velocity=ball_velocity.move_toward(Vector3.ZERO,(ball_release_drag if ball_releasing else ball_coast_drag)*delta)
	if is_on_floor():
		var normal:=get_floor_normal();var gravity:=Vector3.DOWN*8.0*motion_scale;ball_velocity+=gravity.slide(normal)*delta
	ball_velocity.y=0;ball_velocity=ball_velocity.limit_length(ball_max_speed)
	# Rolling remains available, but the low single-file aisle has no room for a charging run-up.
	if game.puzzles!=null and game.puzzles.in_low_passage(global_position):ball_velocity=ball_velocity.limit_length(movement_run_speed)
	ball_peak_speed=maxf(ball_peak_speed,ball_velocity.length())
	if ball_velocity.length()>.05:heading_yaw=atan2(-ball_velocity.z,ball_velocity.x)
	velocity.x=ball_velocity.x;velocity.z=ball_velocity.z
	if not is_on_floor():velocity.y-=15*motion_scale*delta
	var before:=global_position;var incoming:=velocity
	move_and_slide();_push_rigid_bodies()
	var travel:=Vector2(global_position.x-before.x,global_position.z-before.z).length()
	roll_distance+=travel;roll_angle-=travel/roll_radius;_roll_visual()
	for i in get_slide_collision_count():
		var hit:=get_slide_collision(i);var n:=hit.get_normal();var body:=hit.get_collider()
		if body==game.companion and is_on_floor() and Vector2(incoming.x,incoming.z).length()>=ball_max_speed*ROLL_LAUNCH_THRESHOLD and -incoming.dot(n)>.65 and roll_hit_cooldown<=0 and body.stunt_mode=="" and body.state!="flattened":
			roll_hit_cooldown=1.2;roll_launch_hits+=1
			body.get_node("WanderMind").set_physics_process(false)
			body.start_flight(Vector3(incoming.x*.92,5.8,incoming.z*.92),"ram")
			add_collision_exception_with(body);body.add_collision_exception_with(self)
			get_tree().create_timer(.45).timeout.connect(func():remove_collision_exception_with(body);body.remove_collision_exception_with(self))
			game.playground.sound("body_collision",hit.get_position(),-11)
			game._show_toast("滚动冲撞！",1.2)
			ball_velocity*=.82
		if body is StaticBody3D and absf(n.y)<.55 and -incoming.dot(n)>.45:
			_begin_stun(n,incoming);return
	if ball_releasing and ball_velocity.length()<.08:
		roll_recovery=0;roll_recovery_angle=roll_angle

func _begin_stun(normal:Vector3,incoming:Vector3) -> void:
	stun_start_visual=visual.transform
	impact_count+=1;impact_speed=-incoming.dot(normal);impact_normal=normal;impact_position=global_position
	stun_time=0;stun_elapsed_record=0;state="stunned";stun_heading=heading_yaw;ground_motion=false;locomotion.release_feet()
	var recoil:=incoming.bounce(normal)*.48;recoil.y=1.4*motion_scale
	velocity=recoil;ball_velocity=Vector3.ZERO;roll_weight=0;roll_angle=0;roll_recovery=-1
	player.play("anime/wait",0);player.speed_scale=0;springs.active=false
	if hit_audio!=null and game.sounds_enabled:hit_audio.volume_db=-14;hit_audio.play();dizzy_audio.play()
	if dizzy_stars!=null:dizzy_stars.visible=true

func _roll_visual() -> void:
	if state=="dash":super._roll_visual();return
	var basis:=Basis(Vector3.UP,heading_yaw)*Basis(Vector3.BACK,roll_angle)
	# Let the curled silhouette contract into the growing ball before hiding it.
	# Reversing the same weight also unfolds smoothly on release.
	var morph_scale:=visual_scale*lerpf(1.0,.60,roll_weight)
	visual.basis=basis.scaled(Vector3.ONE*morph_scale)
	var pivot:=Vector3(.11,.395,0)*morph_scale
	visual.position=(Vector3(0,roll_radius,0)-basis*pivot)*roll_weight
	if false and not fold_support.is_empty():
		var phase:float=fposmod(roll_angle,TAU)/TAU*fold_support.size()
		var index:int=int(phase);var support:float=lerpf(float(fold_support[index]),float(fold_support[(index+1)%fold_support.size()]),phase-index)*visual_scale
		visual.position.y+=(support-roll_radius)*roll_weight

func _process_stun(delta:float) -> void:
	stun_time+=delta;stun_elapsed_record+=delta;ground_motion=false
	velocity.x=move_toward(velocity.x,0,1.9*motion_scale*delta);velocity.z=move_toward(velocity.z,0,1.9*motion_scale*delta)
	if not is_on_floor():velocity.y-=15*motion_scale*delta
	move_and_slide();impact_recoil_distance=maxf(impact_recoil_distance,Vector2(global_position.x-impact_position.x,global_position.z-impact_position.z).length())
	var fall:=smoothstep(.045,.25,stun_time);var getup:=smoothstep(stun_duration,stun_duration+.38,stun_time)
	var back_angle:float=(PI*.5+.035*sin(stun_time*18)*exp(-stun_time*6))*fall*(1-getup)
	back_angle-=.12*sin(getup*PI)
	var target_basis:Basis=(Basis(Vector3.UP,stun_heading)*Basis(Vector3.BACK,PI*.5 if stun_time<.25 else back_angle)).scaled(Vector3.ONE*visual_scale)
	var target_position:=Vector3(0,.15*(1-getup)+.025*sin(getup*PI),0)*motion_scale
	visual.transform=stun_start_visual.interpolate_with(Transform3D(target_basis,target_position),fall) if stun_time<.25 else Transform3D(target_basis,target_position)
	if stun_time>=stun_duration:
		if last_stun_duration==0:last_stun_duration=stun_time
		if dizzy_stars!=null:dizzy_stars.visible=false
	if stun_time>=stun_duration+.38:
		_end_roll();stun_time=0;roll_cooldown=.30;player.speed_scale=1

func _ensure_effects() -> void:
	if roll_audio!=null or game==null:return
	roll_audio=AudioStreamPlayer3D.new();roll_audio.name="Ball wood friction";add_child(roll_audio)
	var stream=load("res://assets/audio/toy_roll_loop.wav") as AudioStreamWAV
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=int(stream.get_length()*stream.mix_rate);roll_audio.stream=stream
	roll_audio.unit_size=3;roll_audio.max_distance=18;roll_audio.volume_db=-80
	hit_audio=AudioStreamPlayer3D.new();add_child(hit_audio);hit_audio.stream=load("res://assets/audio/toy_impact.wav");hit_audio.unit_size=3
	dizzy_audio=AudioStreamPlayer3D.new();add_child(dizzy_audio);dizzy_audio.stream=load("res://assets/ui_v26/whale_house_dizzy.wav");dizzy_audio.unit_size=3;dizzy_audio.volume_db=-22
	dizzy_stars=Node3D.new();dizzy_stars.name="Dizzy orbit stars";add_child(dizzy_stars);dizzy_stars.visible=false
	for i in range(4):
		var star:=MeshInstance3D.new();star.mesh=game._star_mesh();star.scale=Vector3.ONE*.38;star.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;star.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		var m:=StandardMaterial3D.new();m.albedo_color=Color(1,.72,.12);m.emission_enabled=true;m.emission=Color(1,.52,.06);m.emission_energy_multiplier=1.2;m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;star.material_override=m;dizzy_stars.add_child(star)

func _update_effects(delta:float) -> void:
	if roll_audio==null:return
	var rolling:bool=state=="roll" and roll_time>=BALL_READY_TIME and is_on_floor() and roll_recovery<0 and ball_velocity.length()>.08 and game.sounds_enabled
	var target:float=lerpf(-30,-16,clampf(ball_velocity.length()/ball_max_speed,0,1)) if rolling else -80
	roll_audio.volume_db=lerpf(roll_audio.volume_db,target,1-exp(-delta*14))
	roll_audio.pitch_scale=lerpf(.60,1.30,clampf(ball_velocity.length()/ball_max_speed,0,1))
	if rolling and not roll_audio.playing:roll_audio.play()
	if not rolling and roll_audio.volume_db< -65:roll_audio.stop()
	if rolling:audio_peak_db=maxf(audio_peak_db,roll_audio.volume_db)
	if dizzy_stars.visible:
		var head:=skeleton.find_bone("Head");var head_world:Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(head).origin
		dizzy_stars.global_position=head_world+Vector3.UP*.26
		for i in range(4):
			var angle:=stun_time*4.6+TAU*i/4;var star:=dizzy_stars.get_child(i) as Node3D
			star.position=Vector3(cos(angle)*.14,sin(angle*2)*.025,sin(angle)*.10);star.look_at(camera.global_position);star.rotate_object_local(Vector3.BACK,stun_time*2+i*.8)

func reset_position() -> void:
	if state=="flattened":_restore_flatten()
	super.reset_position();ball_velocity=Vector3.ZERO;ball_releasing=false;stun_time=0;last_stun_duration=0
	if dizzy_stars!=null:dizzy_stars.visible=false
	if roll_audio!=null:roll_audio.stop();dizzy_audio.stop()

func flatten_from(incoming:Vector3,ball:RigidBody3D) -> void:
	if state=="flattened":return
	_ensure_roll_collider();_ensure_effects()
	if game.prop_interaction.held!=null and self==game.actor:game.prop_interaction.drop()
	if self==game.actor and game.iron_ball.pushing:game.iron_ball.stop_push()
	if state in ["roll","dash","stunned"]:_end_roll()
	flat_start=visual.transform;flat_prior_control=can_control;can_control=false;state="flattened";flat_time=0;flat_count+=1;ground_motion=false;locomotion.release_feet();springs.active=false;roll_weight=0
	player.play("anime/wait",0);player.speed_scale=0;velocity=Vector3(incoming.x,0,incoming.z)*.12
	crushing_ball=ball;add_collision_exception_with(ball);ball.add_collision_exception_with(self)
	for collider in standing_colliders:collider.set_deferred("disabled",true)
	roll_collider.set_deferred("disabled",true)
	if flat_collision==null:prepare_action_effects()
	flat_collision.set_deferred("disabled",false)
	_make_flat_paper()
	# Re-anchor at the paper's actual centre without moving the printed image or
	# collider in world space. Input now guides what the player sees into the hole.
	var centre_offset=Vector3(flat_paper.position.x,0,flat_paper.position.z)
	global_position+=centre_offset;flat_start.origin-=centre_offset;visual.position-=centre_offset
	flat_pose_offset=-centre_offset
	flat_paper.position.x=0;flat_paper.position.z=0;flat_collision.position.x=0;flat_collision.position.z=0
	reset_physics_interpolation()
	if game.sounds_enabled:hit_audio.pitch_scale=.67;hit_audio.volume_db=-12;hit_audio.play();dizzy_audio.play()

func _make_flat_paper() -> void:
	if flat_paper==null:
		flat_paper=MeshInstance3D.new();flat_paper.name="Actual2DPaper";add_child(flat_paper)
		var quad=QuadMesh.new();quad.size=Vector2(.29,.25);flat_paper.mesh=quad
		var material=ShaderMaterial.new();material.shader=preload("res://paper_sticker.gdshader");material.set_shader_parameter("printed_character",load("res://assets/playground/whale_paper.png"));flat_paper.material_override=material
		flat_paper.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;flat_paper.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;flat_paper.layers=2
	# The doll faces local +X. Lying on its back maps its original height Y
	# onto ground X; standing depth X is not the head-to-feet length.
	# Cache cheap mesh bounds, never read/deform skin vertices during impact.
	if flat_model_bounds.size==Vector3.ZERO:
		var first=true
		for mesh in visual.find_children("*","MeshInstance3D",true,false):
			var b=visual.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
			flat_model_bounds=b if first else flat_model_bounds.merge(b);first=false
	flat_footprint=Vector2(flat_model_bounds.size.z,flat_model_bounds.size.y)*visual_scale
	flat_paper.mesh.size=flat_footprint
	flat_paper.basis=Basis(Vector3.UP,heading_yaw+PI*.5)*Basis(Vector3.RIGHT,-PI*.5)
	var centre=flat_model_bounds.get_center()*visual_scale
	flat_paper.position=Basis(Vector3.UP,heading_yaw)*Vector3(-centre.y,.004,centre.z);flat_paper.hide()
	if flat_collision!=null:
		# Chamfer the empty transparent corners of the print, keeping its true size.
		# The old rotated box caught on the short corner opening at oblique angles.
		var shape=ConvexPolygonShape3D.new();var points=PackedVector3Array()
		var hx=flat_footprint.y*.47;var hz=flat_footprint.x*.45;var bevel=.052
		for y in [-.010,.010]:
			for corner in [Vector2(-hx+bevel,-hz),Vector2(hx-bevel,-hz),Vector2(hx,-hz+bevel),Vector2(hx,hz-bevel),Vector2(hx-bevel,hz),Vector2(-hx+bevel,hz),Vector2(-hx,hz-bevel),Vector2(-hx,-hz+bevel)]:points.append(Vector3(corner.x,y,corner.y))
		shape.points=points;shape.margin=.0005;flat_collision.shape=shape
		flat_collision.position=Vector3(flat_paper.position.x,.012,flat_paper.position.z);flat_collision.rotation.y=heading_yaw

func _flat_model_visible(value:bool) -> void:
	if flat_meshes_visible==value:return
	flat_meshes_visible=value
	for mesh in flat_mesh_cache:mesh.visible=value

func _process_flatten(delta:float) -> void:
	flat_time+=delta;ground_motion=false
	# Do not stand up inside a narrow slot. Only this short pose timer is held;
	# no collider or mesh is allocated while moving through the passage.
	if flat_time>=flat_duration and not _standing_clear():flat_time=flat_duration
	var desired=Vector3.ZERO
	if self==game.actor and not game.paused and flat_time>.2 and flat_time<=flat_duration+.02:
		if input_override:desired=override_direction.limit_length(1)
		else:
			var axes=Input.get_vector("move_left","move_right","move_forward","move_back")
			var right=camera.global_basis.x;right.y=0;var back=camera.global_basis.z;back.y=0
			desired=(right.normalized()*axes.x+back.normalized()*axes.y).limit_length(1)
	_turn_flat_paper(desired,delta)
	var movement_target=desired*.90
	velocity.x=move_toward(velocity.x,movement_target.x,delta*5);velocity.z=move_toward(velocity.z,movement_target.z,delta*5)
	velocity.y=-.35 if is_on_floor() else velocity.y-12*motion_scale*delta;move_and_slide()
	# The contact solver tolerates millimetres of penetration; keep the printed
	# surface on top of the actual floor instead of sinking beneath its texture.
	for i in get_slide_collision_count():
		var hit=get_slide_collision(i)
		if hit.get_normal().y>.7:
			var support=hit.get_collider();var surface_y=hit.get_position().y
			if support is Node3D and support.has_meta("paper_surface_height"):
				surface_y=support.to_global(Vector3(0,float(support.get_meta("paper_surface_height")),0)).y
			flat_paper.position.y=surface_y-global_position.y+.004
			break
	var fall:=smoothstep(0,.13,flat_time);var recover:=clampf((flat_time-.13-flat_duration)/.72,0,1)
	var upright:=smoothstep(0,.55,recover)
	var jelly:=sin(recover*PI*4)*exp(-recover*4)*.35
	var vertical:=lerpf(.012,1.0,upright)+jelly*upright
	# Rotate the same doll onto the floor, compress depth only. Its in-plane
	# dimensions never exceed the unflattened model, including recovery.
	var horizontal:=1.0-maxf(0,jelly)*.12*upright
	var rotation:=Basis(Vector3.UP,heading_yaw)*Basis(Vector3.BACK,PI*.5*(1-upright))
	var scaled:=Basis.from_scale(Vector3(horizontal,vertical,horizontal))*rotation*Basis.from_scale(Vector3.ONE*visual_scale)
	var position:=Vector3.UP*(.0035*(1-upright)+.045*sin(recover*PI))+flat_pose_offset*(1-upright)
	var target:=Transform3D(scaled,position)
	visual.transform=flat_start.interpolate_with(target,fall) if flat_time<.13 else target
	if flat_time>=.13 and recover<.12:
		_flat_model_visible(false);flat_paper.show()
	else:
		_flat_model_visible(true);flat_paper.hide()
	if flat_time>=flat_duration+.85:_restore_flatten()

func _turn_flat_paper(direction:Vector3,delta:float) -> void:
	# A paper doll keeps its full footprint. Steer its long axis smoothly into
	# a narrow doorway instead of wedging a fixed diagonal hull between walls.
	if direction.length_squared()<.01 or flat_time<.2 or flat_time>flat_duration:return
	var target=atan2(-direction.z,direction.x)
	var turn=wrapf(target-heading_yaw,-PI,PI)
	if absf(turn)>PI*.5:turn=wrapf(turn+PI,-PI,PI)
	if absf(turn)<.0001:return
	var next_yaw=heading_yaw+clampf(turn,-delta*3.2,delta*3.2)
	if flat_turn_query==null:flat_turn_query=PhysicsShapeQueryParameters3D.new()
	flat_turn_query.shape=flat_collision.shape
	flat_turn_query.transform=global_transform*Transform3D(Basis(Vector3.UP,next_yaw),flat_collision.position+Vector3.UP*.012)
	flat_turn_query.collision_mask=collision_mask;flat_turn_query.margin=.0005
	flat_turn_query.exclude=[get_rid()]
	if is_instance_valid(crushing_ball):flat_turn_query.exclude=[get_rid(),crushing_ball.get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(flat_turn_query,1).is_empty():return
	heading_yaw=next_yaw;flat_collision.rotation.y=next_yaw
	flat_paper.basis=Basis(Vector3.UP,next_yaw+PI*.5)*Basis(Vector3.RIGHT,-PI*.5)

func _restore_flatten() -> void:
	_flat_model_visible(true)
	if flat_paper!=null:flat_paper.hide()
	if flat_collision!=null:flat_collision.set_deferred("disabled",true)
	for collider in standing_colliders:collider.set_deferred("disabled",false)
	if is_instance_valid(crushing_ball):remove_collision_exception_with(crushing_ball);crushing_ball.remove_collision_exception_with(self)
	crushing_ball=null;state="idle";visual.basis=Basis(Vector3.UP,heading_yaw).scaled(Vector3.ONE*visual_scale);visual.position=Vector3.ZERO;player.speed_scale=1;springs.active=true;springs.reset();can_control=self==game.actor and not game.paused;locomotion.release_feet();velocity=Vector3.ZERO
	call("restore_action_pose")

func _standing_clear() -> bool:
	for collider in standing_colliders:
		var query=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape
		query.transform=global_transform*collider.transform;query.transform.origin+=Vector3.UP*.016
		query.collision_mask=1;query.exclude=[get_rid()];query.margin=.001
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
	return true

func begin_cue_roll(owner_puzzle:Node3D,immediate:bool=false) -> void:
	if state=="flattened" or cue_mode!="":return
	if self==game.actor and game.prop_interaction.held!=null:game.prop_interaction.drop()
	if self==game.actor and game.iron_ball.pushing:game.iron_ball.stop_push()
	if state in ["roll","dash","stunned"]:_end_roll()
	cue_owner=owner_puzzle;cue_clock=0
	_begin_roll(-cue_owner.global_basis.z)
	cue_mode="out" if immediate else "windup";can_control=false
	velocity=Vector3.ZERO;ball_velocity=Vector3.ZERO
	get_node("WanderMind").set_physics_process(false)

func _process_cue_roll(delta:float) -> void:
	cue_clock+=delta;ground_motion=false;roll_time=BALL_READY_TIME+cue_clock
	roll_weight=smoothstep(0,.16,cue_clock)
	if not ball_contact_ready and cue_clock>=.08:
		ball_contact_ready=true
		for c in standing_colliders:c.set_deferred("disabled",true)
		roll_collider.set_deferred("disabled",false)
	var p=cue_owner.to_local(global_position)
	var signed_speed=0.0
	if cue_mode=="out":
		signed_speed=-3.5
		if p.z<cue_owner.BOARD_CONTACT_Z:
			if cue_owner.board_weight>.85:
				cue_owner.bounce_board();cue_mode="compression";cue_clock=0;cue_rebounds+=1
			# Without the spring board, continue along the clear cross-aisle.
			# Only an actual wall contact below may end the roll and cause stun.
	elif cue_mode=="compression":
		roll_weight=1
		if cue_clock>.14:cue_mode="return";cue_clock=1
	elif cue_mode=="return":
		signed_speed=4.4
		if p.z>cue_owner.SAFE_Z:signed_speed=maxf(.35,(cue_owner.RETURN_STOP_Z+.02-p.z)*5)
		if p.z>cue_owner.RETURN_STOP_Z:end_cue_roll(false);return
	# Narrow center correction is collision tested by move_and_slide, never a teleport.
	var lateral=clampf(-p.x*7,-1.2,1.2)
	var motion=cue_owner.global_basis*Vector3(lateral,0,signed_speed)
	ball_velocity=motion;velocity.x=motion.x;velocity.z=motion.z
	velocity.y=-.35 if is_on_floor() else velocity.y-12*delta
	if absf(signed_speed)>.05:heading_yaw=atan2(-motion.z,motion.x)
	var before=global_position;move_and_slide()
	var travel=Vector2(global_position.x-before.x,global_position.z-before.z).length()
	roll_angle-=travel/maxf(.08,roll_radius);roll_distance+=travel;_roll_visual()
	if cue_mode=="out":
		for i in get_slide_collision_count():
			var contact=get_slide_collision(i)
			var other=contact.get_collider()
			# An oncoming toy must not pin the struck ball in the single-file aisle.
			# Transfer the impact into the same visible ball action, preserving solid
			# contact and spacing, rather than disabling either character's collision.
			if other is CharacterBody3D and other.has_method("begin_cue_roll") and absf(contact.get_normal().y)<.35 and contact.get_normal().dot(motion.normalized())<-.55:
				if other.cue_mode=="" and other.state not in ["flattened","stunned"] and not cue_owner._holds_eight(other):
					other.begin_cue_roll(cue_owner,true);other.set_meta("cue_chain_hits",other.get_meta("cue_chain_hits",0)+1)
				elif other.state=="stunned" or cue_owner._holds_eight(other):end_cue_roll(true);return
			if contact.get_collider() is StaticBody3D and absf(contact.get_normal().y)<.35 and contact.get_normal().dot(motion.normalized())<-.55:
				set_meta("cue_wall_impact",contact.get_position());set_meta("cue_wall_impacts",get_meta("cue_wall_impacts",0)+1)
				end_cue_roll(true);return
	# Safety fallback remains physical: if external clutter obstructs the aisle,
	# recover here rather than forcing the toy through it or keeping control locked.
	if cue_clock>5.0:end_cue_roll(true)

func end_cue_roll(dizzy:bool) -> void:
	cue_mode="";ball_velocity=Vector3.ZERO;velocity=Vector3.ZERO
	_end_roll();get_node("WanderMind").set_physics_process(true)
	input_override=self!=game.actor;can_control=self==game.actor and not game.paused
	if dizzy:
		_begin_stun(cue_owner.global_basis.z,Vector3.ZERO)
		velocity=Vector3.ZERO
	else:call("restore_action_pose")

