extends Node

# Pickable bodies stay the original meshes and return to real rigid-body physics.
var room:Node3D
var actor:CharacterBody3D
var held:RigidBody3D
var candidate:RigidBody3D
var phase:="idle"
var phase_time:=0.0
var charge:=0.0
var charge_seconds:=1.35
var charging:=false
var lift_start:=Transform3D.IDENTITY
var lift_actor_start:=Vector3.ZERO
var held_basis:=Basis.IDENTITY
var grip_local:=Vector3.ZERO
var carry_offset:=Vector3.ZERO
var charge_recoil:=Vector3(-.020,.020,0)
var pose:SkeletonModifier3D
var label:Label
var meter:ProgressBar
var ui:CanvasLayer
var arrow:MeshInstance3D
var release_body:RigidBody3D
var collision_grace:=0.0
var throw_count:=0
var pickup_count:=0
var last_throw_speed:=0.0
var last_throw_charge:=0.0
var arm_weight:=0.0
var arm_target:=Vector3.ZERO
var body_bend:=0.0
var prior_control:=true
var prior_override:=false
var prior_sprint:=false
var last_good_transform:=Transform3D.IDENTITY
var last_blocked:Dictionary={}
var impact_sounds:=0
var trajectory_enabled:=true
var trajectory:MeshInstance3D
var landing:MeshInstance3D
var trajectory_timer:=0.0
var trajectory_button:Button
var aim_input:=Vector2.ZERO
var throw_velocity:=Vector3.ZERO
var last_launch_velocity:=Vector3.ZERO
var last_prediction:Dictionary={}
var orbit_while_holding:=false
var impact_fx:Node3D
var aim_cursor=Vector2.ZERO
var mouse_aim_active=false
var aim_reticle:Label
var requested_aim_point=Vector3.ZERO
var throw_damping=.5
var throw_gravity=9.8
var candidate_timer=0.0
var hold_blocked_time=0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	actor=room.actor
	impact_fx=preload("res://prop_impact_fx.gd").new();impact_fx.name="ToyImpactEffects";add_child(impact_fx)
	pose=preload("res://carry_pose.gd").new();pose.actor=actor;pose.interaction=self
	actor.skeleton.add_child(pose)
	for body in room.physics_props:
		body.contact_monitor=true;body.max_contacts_reported=4
		var sound:=AudioStreamPlayer3D.new();sound.name="ToyContactAudio";body.add_child(sound)
		sound.stream=impact_fx.sounds.get(str(body.get_meta("kind")),impact_fx.sounds["pencil"]);sound.unit_size=2.5;sound.max_distance=14
		body.body_entered.connect(func(_other:Node):_contact_sound.call_deferred(body,sound))
	_build_ui()
	_build_trajectory()
	var config:=ConfigFile.new()
	if not room.automated and config.load("user://gameplay_v9.cfg")==OK:trajectory_enabled=config.get_value("gameplay","throw_guide",true)
	_update_trajectory_button()
	var skirt=preload("res://skirt_contact.gd").new();skirt.name="LegClothContact";skirt.actor=actor;actor.skeleton.add_child(skirt)

func _contact_sound(body:RigidBody3D,sound:AudioStreamPlayer3D) -> void:
	if not room.ready_to_play or body.freeze:return
	var speed:float=body.get_meta("contact_speed",body.get_meta("previous_speed",0.0))
	var now:=Engine.get_physics_frames()
	if speed<.65 or now-int(body.get_meta("last_contact_frame",-30))<6:return
	body.set_meta("last_contact_frame",now)
	var kind:String=body.get_meta("kind","pencil")
	if room.sounds_enabled:
		sound.volume_db=lerpf(-27,-17,clampf(speed/5,0,1));sound.pitch_scale=1.0+randf_range(-.06,.06);sound.play();impact_sounds+=1
	if now<=int(body.get_meta("thrown_until_frame",-1)) and body.has_meta("contact_position"):
		impact_fx.burst(kind,body.get_meta("contact_position"),body.get_meta("contact_normal",Vector3.UP),speed)

func warmup_visuals() -> void:
	for person in [room.actor,room.companion]:
		person.prepare_action_effects()
		# Compile the actual action materials while the HTML loading cover is up.
		# Merely instantiating hidden meshes does not warm WebGL draw programs.
		var actor_tick=person.is_physics_processing()
		person.set_physics_process(false)
		var fold=person.ground_fold
		var fold_tick=fold.is_physics_processing()
		fold.set_physics_process(false)
		var visuals=[fold.model,person.flat_paper,person.dizzy_stars]
		var saved=[]
		for item in visuals:
			saved.append([item.transform,item.visible])
			item.global_transform=room.camera.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,0,-1.2))
			item.show()
		fold.model.scale=Vector3.ONE*.13
		for frame in 3:await RenderingServer.frame_post_draw
		for index in visuals.size():
			visuals[index].transform=saved[index][0]
			visuals[index].visible=saved[index][1]
		fold.set_physics_process(fold_tick)
		person.set_physics_process(actor_tick)
	var point=room.camera.global_position-room.camera.global_basis.z*.8
	for kind in ["marble","pencil","reel","chicken"]:impact_fx.burst(kind,point,Vector3.UP,2.0)
	await get_tree().create_timer(.6).timeout

func _build_ui() -> void:
	ui=CanvasLayer.new();ui.layer=8;add_child(ui)
	label=Label.new();label.position=Vector2(850,1190);label.size=Vector2(860,52);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var font:=preload("res://web/noto_sans_sc.ttf")
	label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",29)
	label.add_theme_color_override("font_shadow_color",Color(0,0,0,.9));label.add_theme_constant_override("shadow_offset_x",2);label.add_theme_constant_override("shadow_offset_y",2);ui.add_child(label)
	meter=ProgressBar.new();meter.position=Vector2(1080,1252);meter.size=Vector2(400,17);meter.show_percentage=false;meter.max_value=1;ui.add_child(meter)
	arrow=MeshInstance3D.new();var mesh:=TorusMesh.new();mesh.inner_radius=.115;mesh.outer_radius=.125;mesh.rings=24;mesh.ring_segments=6;arrow.mesh=mesh
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color(1,.78,.35);arrow.material_override=mat;arrow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(arrow);arrow.hide()
	aim_reticle=Label.new();aim_reticle.text="＋";aim_reticle.add_theme_font_size_override("font_size",24);aim_reticle.add_theme_color_override("font_color",Color(1,.88,.53));aim_reticle.add_theme_color_override("font_shadow_color",Color.BLACK);aim_reticle.add_theme_constant_override("shadow_offset_x",1);aim_reticle.add_theme_constant_override("shadow_offset_y",1);aim_reticle.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(aim_reticle);aim_reticle.hide()

func handle_input(event:InputEvent) -> bool:
	if room.paused or not room.ready_to_play:return false
	if held!=null and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		orbit_while_holding=event.pressed;return false
	if held!=null and phase=="hold" and event is InputEventMouseMotion and charging:
		aim_cursor=(aim_cursor+event.relative).clamp(Vector2(12,12),get_viewport().get_visible_rect().size-Vector2(12,12));mouse_aim_active=true
		get_viewport().set_input_as_handled();return true
	if held!=null and phase=="hold" and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_C:
		_reset_mouse_aim();trajectory_timer=0;get_viewport().set_input_as_handled();return true
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_G:
		toggle_trajectory();get_viewport().set_input_as_handled();return true
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F:
		if held!=null:drop()
		elif phase=="idle":try_pickup()
		get_viewport().set_input_as_handled();return true
	if held!=null and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if phase=="hold":
			if event.pressed:charging=true;charge=0.0
			elif charging:begin_throw()
		get_viewport().set_input_as_handled();return true
	return false

func _nearest() -> RigidBody3D:
	var found:RigidBody3D;var score:=INF
	for body in room.physics_props:
		if not is_instance_valid(body) or body==held:continue
		if body.has_method("can_pickup") and not body.can_pickup(actor):continue
		var delta:Vector3=body.global_position-(actor.global_position+Vector3.UP*.13)
		if Vector2(delta.x,delta.z).length()>.80 or absf(delta.y)>.53:continue
		# Reach the visible upper half of a toy on a book too; a ray aimed only
		# at its centre was falsely occluded by the edge of the book.
		var visible_part=false
		for target in [body.global_position,body.global_position+Vector3.UP*.13]:
			var query:=PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.30,target,1)
			if actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty():visible_part=true;break
		if not visible_part:continue
		var facing:Vector3=Basis(Vector3.UP,actor.heading_yaw)*Vector3.RIGHT
		var value:=delta.length()+.12*(1-facing.dot(delta.normalized()))
		if value<score:found=body;score=value
	return found

func try_pickup() -> bool:
	if held!=null or actor.state in ["roll","dash","stunned","flattened","dead","victory"] or not actor.is_on_floor():return false
	if room.iron_ball!=null and room.iron_ball.pushing:return false
	var target:=_nearest()
	if target==null:return false
	held=target
	throw_damping=held.linear_damp+(float(ProjectSettings.get_setting("physics/3d/default_linear_damp",.1)) if held.linear_damp_mode==RigidBody3D.DAMP_MODE_COMBINE else 0.0)
	throw_gravity=float(ProjectSettings.get_setting("physics/3d/default_gravity",9.8))*held.gravity_scale
	pickup_count+=1;phase="approach";phase_time=0;charge=0;charging=false
	held.set_meta("thrown_until_frame",-1)
	aim_input=Vector2.ZERO;orbit_while_holding=false
	_reset_mouse_aim()
	prior_control=actor.can_control;prior_override=actor.input_override;prior_sprint=actor.override_sprint
	actor.can_control=false;actor.input_override=true;actor.override_sprint=false;actor.override_direction=Vector3.ZERO;actor.velocity=Vector3.ZERO
	var direction:Vector3=held.global_position-actor.global_position;direction.y=0
	if direction.length()>.02:actor.heading_yaw=atan2(-direction.z,direction.x);actor.visual.rotation.y=actor.heading_yaw
	lift_start=held.global_transform;lift_actor_start=actor.global_position;last_good_transform=lift_start
	held.freeze_mode=RigidBody3D.FREEZE_MODE_KINEMATIC;held.freeze=true;held.linear_velocity=Vector3.ZERO;held.angular_velocity=Vector3.ZERO
	_suspend_body_contacts(held)
	_set_held_transform(lift_start)
	held.add_collision_exception_with(actor);actor.add_collision_exception_with(held)
	var kind:String=held.get_meta("kind","");var size:Vector3=held.get_meta("prop_size",Vector3.ONE*.196)
	var radius:float=.19 if kind=="reel" else (.098 if kind=="marble" else .035)
	carry_offset=Vector3(.063+radius,maxf(.162,size.y*.5+.054),0)
	charge_recoil=Vector3(-.020,.020,0)
	grip_local=Vector3(-radius*.90,-.025 if kind=="reel" else -.005,.0495)
	if kind=="reel":
		# The rim is wider than the yarn: support the lower wooden rim with both hands.
		carry_offset.y=.312;grip_local.y=-.15
	if kind=="plane":
		held.set_carrier(actor)
		actor.push_speed_override=.50
		carry_offset=Vector3(0,.425,0);grip_local=Vector3(-.416,.012,.055)
	if kind=="chicken":
		carry_offset=Vector3(.170,.255,0);grip_local=Vector3(-.080,-.070,.048)
	if kind=="pencil":
		if not held.has_meta("carry_capsule"):_cache_pencil_capsule(held)
		# Restore the v8 low, two-handed cradle. Collision and face clearance remain live.
		carry_offset=Vector3(.095,.145,0);grip_local=Vector3(0,-.012,.055)
		charge_recoil=Vector3(-.008,.006,0)
		# Mesh vertices already contain the artist's diagonal placement. Align its
		# measured principal shaft axis, not the rigid body's unrelated local X.
		var axis:Vector3=held.get_meta("shaft_axis",Vector3.RIGHT)
		var world_axis:Vector3=held.global_basis*axis
		var yaw:=atan2(-world_axis.z,world_axis.x)
		var turn:=wrapf(actor.heading_yaw-PI*.5-yaw,-PI,PI)
		held_basis=Basis(Vector3.UP,actor.heading_yaw).inverse()*Basis(Vector3.UP,turn)*held.global_basis
	else:held_basis=Basis.IDENTITY
	if kind=="marble":carry_offset=Vector3(.18,.235,0);grip_local.y=-.045
	hold_blocked_time=0.0
	return true

func _physics_process(delta:float) -> void:
	if not room.ready_to_play:return
	for body in room.physics_props:body.set_meta("previous_speed",body.linear_velocity.length())
	if release_body!=null:
		collision_grace-=delta
		if collision_grace<=0:
				if release_body.get_meta("kind","")!="plane":release_body.remove_collision_exception_with(actor);actor.remove_collision_exception_with(release_body)
				release_body=null
	if held!=null and actor.state in ["roll","dash","stunned","flattened","dead","victory"]:drop()
	phase_time+=delta
	var frame:=Basis(Vector3.UP,actor.visual.rotation.y)
	var carry:=Transform3D(frame*held_basis,actor.global_position+frame*carry_offset)
	if phase=="approach" and held!=null:
		var to_prop:Vector3=held.global_position-actor.global_position;to_prop.y=0
		actor.override_direction=to_prop.normalized()
		var reached=to_prop.length()<=maxf(.13,carry_offset.x+.01)
		if held.get_meta("kind","")=="chicken":reached=to_prop.length()<.30
		if held.get_meta("kind","")=="pencil":reached=to_prop.length()<.31
		if held.get_meta("kind","")=="plane":
			reached=absf(to_prop.length()-.56)<.035
			actor.override_direction=to_prop.normalized()*signf(to_prop.length()-.56)
		if reached:
			actor.override_direction=Vector3.ZERO;actor.velocity=Vector3.ZERO;actor.push_speed_override=-1;phase="reach";phase_time=0
		elif phase_time>1.8:
			if to_prop.length()<.36 and held.get_meta("kind","")!="plane":
				actor.override_direction=Vector3.ZERO;actor.velocity=Vector3.ZERO;phase="reach";phase_time=0
			else:drop()
	elif phase=="reach" and held!=null:
		var bend_amount=.12 if held.get_meta("kind","")=="plane" else .25
		arm_weight=smoothstep(0,.24,phase_time);arm_target=lift_start.origin;body_bend=bend_amount*sin(clampf(phase_time/.38,0,1)*PI*.5)
		if phase_time>=.38:phase="lift";phase_time=0
	elif phase=="lift" and held!=null:
		var duration:=.78 if held.get_meta("kind","")=="plane" else .38
		var t:=smoothstep(0,duration,phase_time);var lifted:=lift_start.interpolate_with(carry,t)
		if held.get_meta("kind","")=="plane":
			var lift=preload("res://plane_lift.gd").sample(lift_start,carry,actor.global_position,frame,phase_time/duration)
			lifted=lift.transform;grip_local=lift.grip
		if _blocked(lifted.origin,lifted.basis):drop()
		else:
			_set_held_transform(lifted);last_good_transform=lifted;arm_target=held.global_position;arm_weight=1;body_bend=(.12 if held.get_meta("kind","")=="plane" else .25)*(1-t)
			if phase_time>=duration:
				phase="hold";phase_time=0;_restore_control();last_good_transform=carry
				_reset_mouse_aim()
				if held.has_method("play_cue"):held.play_cue("pickup")
	elif phase=="hold" and held!=null:
		if charging:charge=minf(1,charge+delta/charge_seconds)
		carry.origin+=frame*charge_recoil*charge
		if _blocked(carry.origin):
			hold_blocked_time+=delta;arm_target=held.global_position;arm_weight=1
			# Keep the last clear pose on a gentle scrape. Only a sustained pull
			# beyond arm reach releases the prop; no movement through solid walls.
			if hold_blocked_time>.45 and held.global_position.distance_to(carry.origin)>.23:drop()
		else:
			hold_blocked_time=0
			_set_held_transform(carry);last_good_transform=carry;arm_target=carry.origin;arm_weight=1;body_bend=-.08*charge
	elif phase=="throw" and held!=null:
		var t:=smoothstep(0,.20,phase_time)
		carry.origin+=frame*charge_recoil.lerp(Vector3(.015,.025,0),t)
		if _blocked(carry.origin):drop()
		else:
			_set_held_transform(carry);arm_target=carry.origin;arm_weight=1;body_bend=.12*t
			if phase_time>=.20:_release_throw()
	elif phase=="recover":
		arm_weight=1-smoothstep(.06,.30,phase_time);body_bend=.12*arm_weight
		if phase_time>.30:phase="idle";_restore_control()
	else:arm_weight=0;body_bend=0
	candidate_timer-=delta
	if phase!="idle":candidate=null
	elif candidate_timer<=0:candidate=_nearest();candidate_timer=.1
	_update_ui()
	trajectory_timer-=delta
	if trajectory_timer<=0:trajectory_timer=.0667;_update_trajectory()

func _blocked(target:Vector3,target_basis:Variant=null) -> bool:
	# A shape sweep prevents carrying or releasing an object through a wall.
	var shape:CollisionShape3D
	for child in held.get_children():
		if child is CollisionShape3D:shape=child;break
	if shape==null:return false
	var q:=PhysicsShapeQueryParameters3D.new();q.shape=shape.shape;q.transform=last_good_transform*shape.transform;q.motion=target-last_good_transform.origin;q.collision_mask=1;q.margin=.0001
	var hit:PackedFloat32Array=actor.get_world_3d().direct_space_state.cast_motion(q)
	if hit.size()==2 and hit[0]<.98:
		var contact:Dictionary=actor.get_world_3d().direct_space_state.get_rest_info(q)
		last_blocked={"phase":phase,"time":phase_time,"type":"sweep","fraction":hit[0],"contact":str(contact),"from":str(last_good_transform.origin),"target":str(target)}
		if not _separating_floor_contact(contact,q.motion):return true
	var actual_basis:Basis=Basis(Vector3.UP,actor.visual.rotation.y)*held_basis if target_basis==null else target_basis
	q.motion=Vector3.ZERO;q.transform=Transform3D(actual_basis,target)*shape.transform
	var overlaps:Array[Dictionary]=actor.get_world_3d().direct_space_state.intersect_shape(q,1)
	if not overlaps.is_empty():
		last_blocked={"phase":phase,"time":phase_time,"type":"overlap","collider":str(overlaps[0].collider),"from":str(last_good_transform.origin),"target":str(target)}
		var rest:Dictionary=actor.get_world_3d().direct_space_state.get_rest_info(q)
		if _separating_floor_contact(rest,target-last_good_transform.origin):return false
	return not overlaps.is_empty()

func _set_held_transform(value:Transform3D) -> void:
	held.global_transform=value
	PhysicsServer3D.body_set_state(held.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,value)

func _suspend_body_contacts(body:RigidBody3D) -> void:
	# Held props use the existing shape sweep against the environment. They must
	# not also resolve hundreds of kinematic contacts against the carrier/book.
	body.set_meta("carry_saved_layer",body.collision_layer)
	body.set_meta("carry_saved_mask",body.collision_mask)
	body.collision_layer=0;body.collision_mask=0

func _restore_body_contacts(body:RigidBody3D) -> void:
	body.collision_layer=int(body.get_meta("carry_saved_layer",4))
	body.collision_mask=int(body.get_meta("carry_saved_mask",7))

func _cache_pencil_capsule(body:RigidBody3D) -> void:
	# Extrude the actual convex outline, including the raised lettering.
	# This avoids both an oversized diagonal AABB and holes between shaft end vertices.
	for child in body.get_children():
		if not child is CollisionShape3D or not child.shape is ConvexPolygonShape3D:continue
		var points:PackedVector3Array=child.shape.points;var outline:=PackedVector2Array();var height:=0.0
		var xx:=0.0;var zz:=0.0;var xz:=0.0
		for point in points:xx+=point.x*point.x;zz+=point.z*point.z;xz+=point.x*point.z
		var angle:=.5*atan2(2*xz,xx-zz);body.set_meta("shaft_axis",Vector3(cos(angle),0,sin(angle)))
		for point in points:outline.append(Vector2(point.x,point.z));height=maxf(height,absf(point.y))
		var hull:=Geometry2D.convex_hull(outline);var center:=Vector2.ZERO
		for point in hull:center+=point
		center/=hull.size()
		var planes:=PackedVector3Array()
		for i in hull.size()-1:
			var edge:Vector2=hull[i+1]-hull[i];var n:=Vector2(edge.y,-edge.x).normalized();var distance:=n.dot(hull[i])
			if n.dot(center)>distance:n=-n;distance=-distance
			planes.append(Vector3(n.x,n.y,distance))
		body.set_meta("carry_capsule",{"planes":planes,"half_height":height})

func _separating_floor_contact(contact:Dictionary,motion:Vector3) -> bool:
	# Resting rigid bodies may begin with the engine's small allowed floor penetration.
	# During the first lift frames, permit separating upward from that contact only.
	if phase!="lift" or phase_time>.15 or motion.y<=0 or contact.is_empty():return false
	var normal:Vector3=contact.get("normal",Vector3.ZERO)
	return normal.y>.8 and motion.dot(normal)>0

func _aim() -> Vector3:
	return (Basis(Vector3.UP,actor.visual.rotation.y)*Vector3.RIGHT).normalized()

func _reset_mouse_aim() -> void:
	mouse_aim_active=false;aim_input=Vector2.ZERO
	aim_cursor=get_viewport().get_visible_rect().size*.5
	if held!=null:
		var point=actor.global_position+_aim()*1.5
		if not room.camera.is_position_behind(point):aim_cursor=room.camera.unproject_position(point).clamp(Vector2(12,12),get_viewport().get_visible_rect().size-Vector2(12,12))

func _mouse_target() -> Vector3:
	var from=room.camera.project_ray_origin(aim_cursor);var direction=room.camera.project_ray_normal(aim_cursor)
	var ray=PhysicsRayQueryParameters3D.create(from,from+direction*45,7);ray.exclude=[actor.get_rid(),held.get_rid()]
	var hit=actor.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():return hit.position+hit.normal*.025
	if direction.y<-.001:return from+direction*((.02-from.y)/direction.y)
	return held.global_position+direction*12

func _required_throw_velocity(target:Vector3,time:float) -> Vector3:
	var gain=(1-exp(-throw_damping*time))/throw_damping if throw_damping>.001 else time
	var drop=-throw_gravity*(time-gain)/throw_damping if throw_damping>.001 else -.5*throw_gravity*time*time
	return (target-held.global_position-Vector3.UP*drop)/gain

func _solve_mouse_target(target:Vector3,speed:float) -> Dictionary:
	# Required speed versus flight time has a single minimum. A bounded search
	# replaces 100 time samples for every one of the reach-limit candidates.
	var low=.025;var high=3.0
	for i in 15:
		var a=lerpf(low,high,.381966);var b=lerpf(low,high,.618034)
		if _required_throw_velocity(target,a).length_squared()<_required_throw_velocity(target,b).length_squared():high=b
		else:low=a
	var best_time=(low+high)*.5;var best=_required_throw_velocity(target,best_time)
	if best.length_squared()>speed*speed:return {"reachable":false,"velocity":best}
	low=.025;high=best_time
	for i in 12:
		var mid=(low+high)*.5
		if _required_throw_velocity(target,mid).length_squared()>speed*speed:low=mid
		else:high=mid
	return {"reachable":true,"velocity":_required_throw_velocity(target,high)}

func _base_launch_velocity(amount:float) -> Vector3:
	var speed:float=lerpf(1.8,6.8,smoothstep(0,1,amount))*actor.motion_scale
	return (_aim()+Vector3.UP*lerpf(.28,.85,amount)).normalized()*speed+Vector3(actor.velocity.x,0,actor.velocity.z)*.45

func _sample_trajectory(initial:Vector3) -> Dictionary:
	if held!=null and held.has_method("predict_glide"):return held.predict_glide(initial)
	var point:Vector3=held.global_position
	var points:=PackedVector3Array([point]);var velocity:=initial
	var gravity:float=float(ProjectSettings.get_setting("physics/3d/default_gravity",9.8))*held.gravity_scale
	var damping:float=held.linear_damp
	if held.linear_damp_mode==RigidBody3D.DAMP_MODE_COMBINE:damping+=float(ProjectSettings.get_setting("physics/3d/default_linear_damp",.1))
	var dt:=1.0/60.0;var decay:=maxf(0,1.0-damping*dt)
	var gain:=0.0;var velocity_gain:=1.0;var duration:=0.0
	var normal:=Vector3.UP;var hit_surface:=false
	for i in 120:
		velocity=(velocity+Vector3.DOWN*gravity*dt)*decay;velocity_gain*=decay
		var next:Vector3=point+velocity*dt
		var ray:=PhysicsRayQueryParameters3D.create(point,next,7);ray.exclude=[actor.get_rid(),held.get_rid()]
		var hit:Dictionary=actor.get_world_3d().direct_space_state.intersect_ray(ray)
		var fraction:=1.0
		if not hit.is_empty():
			next=hit.position;normal=hit.normal;hit_surface=true
			fraction=clampf(point.distance_to(next)/maxf(velocity.length()*dt,.00001),0,1)
		gain+=velocity_gain*dt*fraction;duration+=dt*fraction;point=next;points.append(point)
		if hit_surface:break
	return {"point":point,"normal":normal,"gain":gain,"time":duration,"hit":hit_surface,"points":points}

func aim_solution(amount:float) -> Dictionary:
	if mouse_aim_active:
		requested_aim_point=_mouse_target()
		var speed=lerpf(1.8,6.8,smoothstep(0,1,amount))*actor.motion_scale
		var solution=_solve_mouse_target(requested_aim_point,speed)
		var target=requested_aim_point
		if not solution.reachable:
			var low=0.0;var high=1.0
			for i in 10:
				var fraction=(low+high)*.5;var point=held.global_position.lerp(requested_aim_point,fraction)
				var attempt=_solve_mouse_target(point,speed)
				if attempt.reachable:low=fraction;solution=attempt;target=point
				else:high=fraction
		return {"velocity":solution.velocity,"target":target,"requested":requested_aim_point}
	var base_velocity:=_base_launch_velocity(amount)
	var base:=_sample_trajectory(base_velocity)
	var normal:Vector3=base.normal
	var right:Vector3=room.camera.global_basis.x.slide(normal).normalized()
	if right.length()<.2:right=_aim().cross(Vector3.UP).slide(normal).normalized()
	var up:Vector3=normal.cross(right).normalized()
	if up.dot(room.camera.global_basis.y)<0:up=-up
	var travel:float=held.global_position.distance_to(base.point)
	var limits:=Vector2(minf(.32,travel*.25),minf(.40,travel*.28))
	var offset:Vector3=right*aim_input.x*limits.x+up*aim_input.y*limits.y
	var velocity:Vector3=base_velocity+offset/maxf(float(base.gain),.15)
	return {"velocity":velocity,"base":base,"right":right,"up":up,"limits":limits,"offset":offset}

func launch_velocity(amount:float) -> Vector3:
	if held!=null and held.get_meta("kind","")=="plane":
		var d=(_mouse_target()-held.global_position) if mouse_aim_active else _aim();d.y=0
		return d.normalized()*lerpf(2.5,4.2,amount)+Vector3.UP*.12
	if held==null or not mouse_aim_active:return _base_launch_velocity(amount)
	return aim_solution(amount).velocity

func begin_throw() -> void:
	if held==null or phase!="hold":return
	throw_velocity=launch_velocity(charge)
	charging=false;phase="throw";phase_time=0;prior_control=actor.can_control;prior_override=actor.input_override;prior_sprint=actor.override_sprint;actor.can_control=false;actor.input_override=false
	var direction:=_aim();actor.heading_yaw=atan2(-direction.z,direction.x)
	if mouse_aim_active:
		var facing=throw_velocity;facing.y=0
		if facing.length()>.01:actor.heading_yaw=atan2(-facing.z,facing.x)

func _release_throw() -> void:
	var body:=held;var direction:=_aim()
	var launch:=throw_velocity;last_launch_velocity=launch
	held=null;phase="recover";phase_time=0;throw_count+=1;last_throw_speed=launch.length();last_throw_charge=charge
	_restore_body_contacts(body)
	body.freeze=false;body.sleeping=false;body.linear_velocity=launch;body.angular_velocity=Vector3(direction.z,0,-direction.x)*lerpf(3,12,charge)
	body.set_meta("thrown_until_frame",Engine.get_physics_frames()+300);body.set_meta("last_contact_frame",-30)
	if body.has_method("launch_glide"):body.launch_glide(launch)
	if body.has_method("play_cue"):body.play_cue("throw")
	_begin_grace(body)
	room._tone(lerpf(430,650,charge),.055,.22)
	charge=0;aim_input=Vector2.ZERO;orbit_while_holding=false

func drop() -> void:
	if held!=null:
		var body:=held;held=null;_restore_body_contacts(body);body.freeze=false;body.sleeping=false;body.linear_velocity=Vector3(actor.velocity.x,0,actor.velocity.z)*.5
		if body.has_method("release_carrier"):body.release_carrier()
		_begin_grace(body)
	if phase in ["approach","reach","lift","throw","recover"]:_restore_control()
	phase="idle";phase_time=0;charging=false;charge=0;arm_weight=0;body_bend=0
	aim_input=Vector2.ZERO;orbit_while_holding=false

func _restore_control() -> void:
	actor.can_control=prior_control;actor.input_override=prior_override;actor.override_sprint=prior_sprint;actor.override_direction=Vector3.ZERO;actor.push_speed_override=-1

func _begin_grace(body:RigidBody3D) -> void:
	if is_instance_valid(release_body) and release_body!=body:
		if release_body.get_meta("kind","")!="plane":release_body.remove_collision_exception_with(actor);actor.remove_collision_exception_with(release_body)
	release_body=body;collision_grace=.22

func cancel_charge() -> void:
	charging=false;charge=0;orbit_while_holding=false

func _update_ui() -> void:
	ui.visible=room.hud!=null and room.hud.visible;meter.visible=charging;meter.value=charge
	aim_reticle.visible=held!=null and phase=="hold";aim_reticle.position=room.resolution.logical_point(aim_cursor)-Vector2(12,14)
	arrow.visible=candidate!=null and ui.visible
	if arrow.visible:arrow.global_position=Vector3(candidate.global_position.x,.025,candidate.global_position.z)
	if phase=="hold":label.text="鼠标转镜头 · 按住左键瞄准蓄力 · 松开投掷" if not charging else "投掷力度 %d%% · 鼠标自由瞄准 · C 回中"%roundi(charge*100)
	elif phase in ["approach","reach","lift"]:label.text="嘿咻！"
	elif room.iron_ball!=null and room.iron_ball.pushing:label.text="W/S 推动 · 鼠标 / A/D 转弯 · E 松开"
	elif candidate!=null:label.text="F 拿起"+str(candidate.get_meta("display_name","小玩具"))
	elif room.iron_ball!=null and actor.global_position.distance_to(room.iron_ball.global_position-Vector3.UP*room.iron_ball.radius)<room.iron_ball.radius+.55:label.text="E 扶住铁球，再用 W/S 推动"
	else:label.text=""

func _build_trajectory() -> void:
	trajectory=MeshInstance3D.new();trajectory.mesh=ImmediateMesh.new();trajectory.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;trajectory.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;add_child(trajectory)
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color(1,.78,.36);trajectory.material_override=mat
	landing=MeshInstance3D.new();var ring:=TorusMesh.new();ring.inner_radius=.065;ring.outer_radius=.075;ring.rings=24;ring.ring_segments=6;landing.mesh=ring;landing.material_override=mat;landing.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(landing)
	trajectory_button=Button.new();trajectory_button.position=Vector2(2270,116);trajectory_button.size=Vector2(252,48);trajectory_button.focus_mode=Control.FOCUS_NONE;trajectory_button.add_theme_font_size_override("font_size",23);ui.add_child(trajectory_button);trajectory_button.pressed.connect(toggle_trajectory)
	trajectory.hide();landing.hide()

func toggle_trajectory() -> void:
	trajectory_enabled=not trajectory_enabled;_update_trajectory_button();_update_trajectory()
	if not room.automated:
		var config:=ConfigFile.new();config.set_value("gameplay","throw_guide",trajectory_enabled);config.save("user://gameplay_v9.cfg")

func _update_trajectory_button() -> void:
	trajectory_button.text="投掷轨迹："+("开" if trajectory_enabled else "关")+" [G]"

func _update_trajectory() -> void:
	var show_guide:bool=trajectory_enabled and held!=null and phase=="hold" and not room.paused
	trajectory.visible=show_guide;landing.hide();trajectory_button.visible=held!=null
	var mesh:ImmediateMesh=trajectory.mesh;mesh.clear_surfaces()
	if not show_guide:return
	var solution:=aim_solution(charge)
	var prediction:=_sample_trajectory(solution.velocity);last_prediction=prediction
	var points:PackedVector3Array=prediction.points
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1,points.size()):mesh.surface_add_vertex(points[i-1]);mesh.surface_add_vertex(points[i])
	mesh.surface_end()
	# The line itself ends at the predicted contact. No large landing ring.
