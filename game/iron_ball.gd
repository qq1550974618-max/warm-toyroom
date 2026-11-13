extends RigidBody3D
var room:Node3D
var radius:=.252
var pushing:=false
var override_hold:=false
var override_input:=Vector3.ZERO
var use_override:=false
var push_elapsed:=0.0
var peak_speed:=0.0
var previous_velocity:=Vector3.ZERO
var flatten_hits:=0
var prior_control:=true
var prior_override:=false
var loop_sound:AudioStreamPlayer3D
var push_direction:=Vector3.FORWARD
var previous_position:=Vector3.ZERO
var target_yaw:=0.0
var last_view_yaw:=0.0
var previous_override_hold:=false
var prior_sprint:=false
var maximum_grip_gap:=0.0
var push_pose:SkeletonModifier3D
var overrun_candidates:Dictionary={}
var overrun_samples:Dictionary={}
var last_overrun:Dictionary={}
var release_boost:=0.0
var wall_bounces:=0
var bounce_cooldown:=0.0
var release_direction:=Vector3.ZERO
const MAX_PUSH_SPEED:=2.8
const CRUSH_MIN_SPEED:=MAX_PUSH_SPEED*.5

func can_grip() -> bool:
	var actor:CharacterBody3D=room.actor
	return actor.is_on_floor() and actor.state in ["idle","walk","run","land"] and room.prop_interaction.held==null and Vector2(actor.position.x-position.x,actor.position.z-position.z).length()<radius+.55 and absf(actor.position.y-(position.y-radius))<.22

func start_push() -> bool:
	if pushing:return true
	if not can_grip():return false
	var actor:CharacterBody3D=room.actor
	prior_control=actor.can_control;prior_override=actor.input_override;prior_sprint=actor.override_sprint
	actor.can_control=false;actor.input_override=true;actor.override_sprint=false
	pushing=true;release_boost=0;push_elapsed=0;maximum_grip_gap=0
	add_collision_exception_with(actor);actor.add_collision_exception_with(self)
	push_direction=global_position-actor.global_position;push_direction.y=0;push_direction=push_direction.normalized()
	target_yaw=atan2(-push_direction.z,push_direction.x);last_view_yaw=room.camera_yaw
	return true

func handle_input(event:InputEvent) -> bool:
	if room.paused or not room.ready_to_play:return false
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E:
		if pushing:stop_push()
		elif not start_push():return false
		get_viewport().set_input_as_handled();return true
	return false

func _ready() -> void:
	name="HeavyIronBall";mass=12;collision_layer=4;collision_mask=7;continuous_cd=true;linear_damp=.16;angular_damp=.10;contact_monitor=true;max_contacts_reported=8;set_meta("heavy_push_only",true)
	process_physics_priority=-10
	var pm:=PhysicsMaterial.new();pm.friction=.65;pm.bounce=.08;physics_material_override=pm
	var cs:=CollisionShape3D.new();var sh:=SphereShape3D.new();sh.radius=radius;cs.shape=sh;add_child(cs)
	var visual:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=radius;sphere.height=radius*2;sphere.radial_segments=64;sphere.rings=32;visual.mesh=sphere;visual.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;add_child(visual)
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.48,.50,.53);mat.metallic=.92;mat.roughness=.38;mat.metallic_specular=.65;visual.material_override=mat;visual.layers=2
	# Recess-like forging seam makes the sphere's physical rotation visible.
	var ring:=MeshInstance3D.new();var torus:=TorusMesh.new();torus.inner_radius=radius-.003;torus.outer_radius=radius+.001;torus.rings=64;torus.ring_segments=6;ring.mesh=torus;var seam:=mat.duplicate();seam.albedo_color=Color(.12,.14,.16);seam.roughness=.55;ring.material_override=seam;ring.layers=2;visual.add_child(ring)
	loop_sound=AudioStreamPlayer3D.new();add_child(loop_sound);var stream=load("res://assets/audio/toy_roll_loop.wav").duplicate();stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=int(stream.get_length()*stream.mix_rate);loop_sound.stream=stream;loop_sound.unit_size=3;loop_sound.volume_db=-80;loop_sound.pitch_scale=.48
	body_entered.connect(_contact)
	push_pose=load("res://push_pose.gd").new();push_pose.actor=room.actor;push_pose.ball=self;room.actor.skeleton.add_child(push_pose)
	previous_position=global_position

func _contact(body:Node) -> void:
	# Merely touching the side of a person is not an overrun. Crushing is
	# committed only after the sphere actually travels over their ground position.
	pass

func reset_overrun_tracking() -> void:
	for id in overrun_candidates:
		var person=instance_from_id(id)
		if is_instance_valid(person):remove_collision_exception_with(person);person.remove_collision_exception_with(self)
	overrun_candidates.clear();overrun_samples.clear();previous_position=global_position;previous_velocity=Vector3.ZERO

func _overrun_half_width(person:CharacterBody3D) -> float:
	# Use the doll's actual ground footprint. A fixed 6.5 cm centreline was
	# narrower than her 9.9 cm capsule and rejected real, slightly off-centre runs.
	var width:=0.0
	for child in person.get_children():
		if not child is CollisionShape3D or child.disabled:continue
		if child.shape is CapsuleShape3D or child.shape is SphereShape3D:
			width=maxf(width,child.shape.radius*maxf(absf(child.global_basis.x.length()),absf(child.global_basis.z.length())))
	return maxf(width,.04)

func _release_overrun(person:CharacterBody3D) -> void:
	overrun_candidates.erase(person.get_instance_id())
	remove_collision_exception_with(person);person.remove_collision_exception_with(self)

func _check_overruns(delta:float) -> void:
	var motion:=Vector3(linear_velocity.x,0,linear_velocity.z)
	var speed:=motion.length()
	for person in [room.actor,room.companion]:
		if person==null or (person==room.actor and pushing):continue
		var id=person.get_instance_id()
		var prior:Dictionary=overrun_samples.get(id,{"position":person.global_position,"ground_age":1.0})
		var ground_age:float=0.0 if person.is_on_floor() else float(prior.ground_age)+delta
		overrun_samples[id]={"position":person.global_position,"ground_age":ground_age}
		if person.state=="flattened":overrun_candidates.erase(id);continue
		var body_radius:=_overrun_half_width(person)
		# Test the sphere's coverage, not only the narrow capsule centreline.
		# A small inset leaves edge-only contact as a normal physical deflection.
		var width:=maxf(.01,radius-body_radius*.10)
		var same_floor:bool=absf(global_position.y-radius-person.global_position.y)<.11 and ground_age<=.05 and person.velocity.y<.35
		# Sweep both bodies, including a walking companion. Physics snapshots
		# belong to the same pair of frames; do not compare a whole ball segment
		# against only the person's final foot position.
		var a:Vector3=previous_position-Vector3(prior.position)
		var b:Vector3=global_position-person.global_position;a.y=0;b.y=0
		var travel:=b-a
		var crossed:=false
		if travel.length_squared()>.0000001 and previous_position.distance_to(global_position)<1.0 and Vector3(prior.position).distance_to(person.global_position)<.5:
			var fraction:float=-a.dot(travel)/travel.length_squared()
			crossed=fraction>=0.0 and fraction<=1.0 and (a+travel*fraction).length()<=width
		var incoming:=Vector3(previous_velocity.x,0,previous_velocity.z)
		var approach:Vector3=incoming if incoming.length()>speed and incoming.dot(-b)>0 else motion
		var approach_speed:=approach.length()
		var candidate:Dictionary=overrun_candidates.get(id,{})
		var qualified:bool=approach_speed>=CRUSH_MIN_SPEED or not candidate.is_empty()
		if qualified and speed>.6 and same_floor and crossed:
			last_overrun={"threshold":CRUSH_MIN_SPEED,"incoming_speed":candidate.get("speed",approach_speed),"crossing_speed":speed,"coverage_radius":width,"target":str(person.name)}
			flatten_hits+=1;person.flatten_from(motion,self);overrun_candidates.erase(id)
			continue
		var relative_motion:Vector3=approach-Vector3(person.velocity.x,0,person.velocity.z)
		var relative_speed:=relative_motion.length()
		if approach_speed>=CRUSH_MIN_SPEED and relative_speed>.05 and same_floor and not overrun_candidates.has(id):
			var direction:=relative_motion/relative_speed
			var forward:float=(-b).dot(direction)
			var side:float=(-b-direction*forward).length()
			# Open before the physics solver stops the ball at the capsule.
			# The speed-dependent lookahead also covers a fast sphere crossing
			# the old 4 cm arming interval between two 60 Hz physics ticks.
			if forward>0 and forward<radius+body_radius+relative_speed*delta*2+.025 and side<=width:
				overrun_candidates[id]={"remaining":.75,"speed":approach_speed}
				add_collision_exception_with(person);person.add_collision_exception_with(self)
		if overrun_candidates.has(id):
			overrun_candidates[id].remaining-=delta
			if overrun_candidates[id].remaining<=0 or not same_floor or speed<.6:_release_overrun(person)

func stop_push() -> void:
	if not pushing:return
	release_boost=1.0 if Vector2(linear_velocity.x,linear_velocity.z).length()>=MAX_PUSH_SPEED*.5 else 0.0
	release_direction=Vector3(linear_velocity.x,0,linear_velocity.z).normalized()
	remove_collision_exception_with(room.actor);room.actor.remove_collision_exception_with(self)
	pushing=false;room.actor.can_control=prior_control and not room.paused;room.actor.input_override=prior_override;room.actor.override_sprint=prior_sprint;room.actor.override_direction=Vector3.ZERO;room.actor.push_speed_override=-1

func _physics_process(delta:float) -> void:
	if not room.ready_to_play:return
	var actor:CharacterBody3D=room.actor
	# Legacy scripted demos use explicit edges; real input is a single E toggle.
	if use_override and override_hold!=previous_override_hold:
		if override_hold:start_push()
		else:stop_push()
		previous_override_hold=override_hold
	if pushing:
		var separation:=actor.global_position.distance_to(global_position-Vector3.UP*radius)
		if separation>1.2 or absf(actor.position.y-(position.y-radius))>.5 or actor.state in ["flattened","stunned","roll","dash","dead","victory"]:stop_push()
		else:
			push_elapsed+=delta;actor.can_control=false;actor.input_override=true
			var keys:=Input.get_vector("move_left","move_right","move_forward","move_back")
			var throttle:float=-keys.y
			var view_delta:=wrapf(room.camera_yaw-last_view_yaw,-PI,PI);last_view_yaw=room.camera_yaw
			if not room.overview:target_yaw+=clampf(view_delta,-.24,.24)*.72
			target_yaw-=keys.x*deg_to_rad(65)*delta
			if use_override:
				throttle=override_input.length()
				if throttle>.1:target_yaw=atan2(-override_input.z,override_input.x)
			var current_yaw:=atan2(-push_direction.z,push_direction.x)
			var turn:=clampf(wrapf(target_yaw-current_yaw,-PI,PI),-deg_to_rad(70)*delta,deg_to_rad(70)*delta)
			current_yaw+=turn;push_direction=Basis(Vector3.UP,current_yaw)*Vector3.RIGHT
			var horizontal:=Vector3(linear_velocity.x,0,linear_velocity.z)
			var desired:=push_direction*(MAX_PUSH_SPEED if throttle>=0 else 1.0)*throttle
			# Hands stay attached while idle; a soft brake holds the heavy ball.
			# The ordinary rigid-body damping is restored simply by releasing E.
			var acceleration:Vector3=(desired-horizontal)*2.8
			acceleration=acceleration.limit_length(.95 if absf(throttle)>.05 else 1.9)
			apply_central_force((acceleration+horizontal*(linear_damp+.1))*mass)
			var target:Vector3=global_position-push_direction*(radius+.112);target.y=actor.global_position.y
			var delta_position:Vector3=target-actor.global_position
			maximum_grip_gap=maxf(maximum_grip_gap,delta_position.length())
			# Match the moving contact point, rather than always chasing it from behind.
			var orbit_velocity:Vector3=-Vector3.UP.cross(push_direction)*(turn/maxf(delta,.001))*(radius+.112)
			var follow_velocity:Vector3=(horizontal+orbit_velocity+delta_position*12).limit_length(3.1)
			actor.override_direction=follow_velocity.normalized() if follow_velocity.length()>.012 else Vector3.ZERO
			actor.push_speed_override=follow_velocity.length()
			actor.heading_yaw=current_yaw
	var speed:=Vector2(linear_velocity.x,linear_velocity.z).length();peak_speed=maxf(peak_speed,speed)
	loop_sound.volume_db=lerpf(loop_sound.volume_db,lerpf(-37,-23,minf(speed/2.2,1)) if speed>.06 and room.sounds_enabled else -80,1-exp(-delta*8));loop_sound.pitch_scale=lerpf(.42,.70,minf(speed/2.2,1))
	if speed>.06 and room.sounds_enabled and not loop_sound.playing:loop_sound.play()
	if loop_sound.volume_db< -65:loop_sound.stop()
	_check_overruns(delta)
	previous_velocity=linear_velocity;previous_position=global_position

func _integrate_forces(state:PhysicsDirectBodyState3D) -> void:
	bounce_cooldown=maxf(0,bounce_cooldown-state.step)
	if pushing:return
	var horizontal=Vector3(state.linear_velocity.x,0,state.linear_velocity.z)
	if release_boost>0:
		release_boost=maxf(0,release_boost-state.step)
		if horizontal.length()>.1:
			horizontal=horizontal.normalized()*minf(MAX_PUSH_SPEED,horizontal.length()+2.4*state.step)
			# Match the rolling spin as the released heavy ball gains momentum.
			state.angular_velocity=Vector3.UP.cross(horizontal)/radius
	# The rounded skirting can lift the sphere and brake it before its center
	# reaches the vertical wall. Sweep the upper contact band as well.
	if bounce_cooldown<=0 and horizontal.length()>.55:
		var start=state.transform.origin+Vector3.UP*.10
		var query=PhysicsRayQueryParameters3D.create(start,start+horizontal.normalized()*(radius+.075+horizontal.length()*state.step),1,[get_rid()])
		var hit=state.get_space_state().intersect_ray(query)
		if not hit.is_empty() and hit.collider is StaticBody3D and absf(hit.normal.y)<.35 and horizontal.dot(hit.normal)<-.5:
			horizontal=horizontal.bounce(hit.normal)*.96;release_boost=0;bounce_cooldown=.18;wall_bounces+=1
			state.angular_velocity=Vector3.UP.cross(horizontal)/radius
	for i in state.get_contact_count():
		var other=state.get_contact_collider_object(i)
		var normal=state.get_contact_local_normal(i)
		if other is StaticBody3D and "FloorSeals" in str(other.get_path()) and Vector2(normal.x,normal.z).length()>.10:
			normal=Vector3(normal.x,0,normal.z).normalized()
		if other is StaticBody3D and absf(normal.y)<.3 and bounce_cooldown<=0:
			var incoming=Vector3(previous_velocity.x,0,previous_velocity.z)
			if incoming.dot(normal)<-.5:
				horizontal=incoming.bounce(normal)*.96;release_boost=0;bounce_cooldown=.18;wall_bounces+=1;state.angular_velocity=Vector3.UP.cross(horizontal)/radius
				break
	state.linear_velocity=Vector3(horizontal.x,state.linear_velocity.y,horizontal.z)
