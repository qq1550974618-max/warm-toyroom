extends "res://toy_prop_body.gd"
const SIZE_SCALE=.80
const CARRY_HEIGHT=.425
var room
var deck:AnimatableBody3D
var gliding=false
var glide_velocity=Vector3.ZERO
var sink_speed=.65
var travel_time=0.0
var last_frame=Transform3D.IDENTITY
var riders:Array=[]
var assisted_holder:CharacterBody3D
var wall_hits=0
var launches=0
var max_rider_drift=0.0
var carrier:CharacterBody3D
var carrier_release_time=0.0
func set_carrier(person:CharacterBody3D) -> void:
	clear_carrier();carrier=person;carrier_release_time=0
	add_collision_exception_with(person);person.add_collision_exception_with(self)
	deck.add_collision_exception_with(person);person.add_collision_exception_with(deck)
func release_carrier() -> void:carrier_release_time=.35
func clear_carrier() -> void:
	if is_instance_valid(carrier):
		deck.remove_collision_exception_with(carrier);carrier.remove_collision_exception_with(deck)
	carrier=null;carrier_release_time=0
func can_pickup(person:CharacterBody3D) -> bool:
	return not gliding and assisted_holder==null and not is_riding(person)
func _ready() -> void:
	name="CarryPaperPlane";mass=.12;collision_layer=4;collision_mask=7;continuous_cd=true;linear_damp=.4;angular_damp=1.2;process_physics_priority=-35
	set_meta("kind","plane");set_meta("display_name","纸飞机");set_meta("prop_size",Vector3(1.13,.14,1.08)*SIZE_SCALE);set_meta("spawn_transform",transform)
	var model=load("res://assets/playground/v17_paper_plane.glb").instantiate();model.scale=Vector3.ONE*SIZE_SCALE;add_child(model);room._prepare_prop_meshes(model)
	var cs=CollisionShape3D.new();var shape=ConvexPolygonShape3D.new();var points=PackedVector3Array()
	for p in [Vector3(.60,.03,0),Vector3(-.53,.03,-.54),Vector3(-.53,.03,.54),Vector3(-.43,-.10,0)]:
		points.append(p*SIZE_SCALE);points.append((p+Vector3.DOWN*.008)*SIZE_SCALE)
	shape.points=points;shape.margin=.001;cs.shape=shape;add_child(cs)
	var material=PhysicsMaterial.new();material.friction=.85;material.bounce=.02;physics_material_override=material
	deck=AnimatableBody3D.new();deck.name="PaperWingStandingSurface";deck.sync_to_physics=false;deck.collision_layer=64;deck.collision_mask=0;room.add_child(deck)
	var wing=CollisionShape3D.new();var wing_shape=ConvexPolygonShape3D.new();var wing_points=PackedVector3Array()
	for y in [.018,.034]:
		for v in [Vector3(.58,y,0),Vector3(-.51,y,-.52),Vector3(-.51,y,.52)]:wing_points.append(v*SIZE_SCALE)
	wing_shape.points=wing_points;wing_shape.margin=.001;wing.shape=wing_shape;deck.add_child(wing)
	last_frame=global_transform;deck.global_transform=global_transform
	# A single standing surface prevents the rigid hull and the passenger deck
	# from both transporting/pushing the character in the same physics tick.
	for person in [room.actor,room.companion]:
		add_collision_exception_with(person);person.add_collision_exception_with(self)
func launch_glide(initial:Vector3) -> void:
	release_carrier()
	gliding=true;launches+=1;travel_time=0;freeze=true;freeze_mode=RigidBody3D.FREEZE_MODE_KINEMATIC;collision_layer=0
	glide_velocity=Vector3(initial.x,0,initial.z).limit_length(4.2)
	if glide_velocity.length()<1:glide_velocity=global_basis.x*2.5
	rotation=Vector3(0,atan2(-glide_velocity.z,glide_velocity.x),0);linear_velocity=Vector3.ZERO;angular_velocity=Vector3.ZERO
	last_frame=global_transform;reset_physics_interpolation()
func is_riding(person:CharacterBody3D) -> bool:
	return on_wing_at(person,global_transform)
func on_wing_at(person:CharacterBody3D,frame:Transform3D) -> bool:
	var local=(frame.affine_inverse()*person.global_position)/SIZE_SCALE
	var half_width=maxf(0,(.58-local.x)*.52/1.09)
	return local.x>-.54 and local.x<.48 and absf(local.z)<half_width+.025 and absf(local.y-.035)<.065 and person.velocity.y<=.15
func _physics_process(delta:float) -> void:
	if not room.ready_to_play:return
	if carrier_release_time>0:
		carrier_release_time-=delta
		if carrier_release_time<=0:clear_carrier()
	var old=last_frame
	if gliding:
		travel_time+=delta
		var motion=(glide_velocity+Vector3.DOWN*sink_speed)*delta
		var query=PhysicsShapeQueryParameters3D.new();query.shape=deck.get_child(0).shape;query.transform=global_transform*deck.get_child(0).transform;query.motion=motion;query.collision_mask=1;query.exclude=[get_rid(),deck.get_rid()]
		var result=get_world_3d().direct_space_state.cast_motion(query)
		if result[0]<.98:
			global_position+=motion*maxf(0,result[0]-.04)
			var contact=get_world_3d().direct_space_state.get_rest_info(query)
			var ray=PhysicsRayQueryParameters3D.create(global_position,global_position+motion.normalized()*.8,1)
			var hit=get_world_3d().direct_space_state.intersect_ray(ray)
			var normal:Vector3=contact.get("normal",hit.get("normal",-glide_velocity.normalized()))
			if absf(normal.y)<.6:wall_hits+=1
			stop_glide(normal)
		else:global_position+=motion
		if travel_time>15 or global_position.y<.02:stop_glide(Vector3.UP)
	deck.global_transform=global_transform
	# Transport planted feet by the deck delta; normal controls still run afterward.
	# No flight pose, input lock, or extra inertia is imposed on passengers.
	riders.clear()
	for person in [room.actor,room.companion]:
		if person==assisted_holder or person==room.actor and room.prop_interaction.held==self:continue
		var local=old.affine_inverse()*person.global_position
		if on_wing_at(person,old):
			var shift=global_transform*local-person.global_position
			person.global_position+=shift
			for leg in person.locomotion.legs:
				if leg.locked:leg.anchor+=shift
			riders.append(person)
	last_frame=global_transform
func stop_glide(normal:Vector3) -> void:
	gliding=false;freeze=false;collision_layer=4;sleeping=false
	linear_velocity=Vector3(0,-.45,0) if absf(normal.y)<.6 else Vector3.ZERO
	angular_velocity=Vector3(0,0,.7) if absf(normal.y)<.6 else Vector3.ZERO
func reset_plane() -> void:
	clear_carrier()
	gliding=false;assisted_holder=null;freeze=false;collision_layer=4;collision_mask=7;sink_speed=.65;room._teleport_prop(self,get_meta("spawn_transform"));last_frame=global_transform;deck.global_transform=global_transform;deck.reset_physics_interpolation()
func predict_glide(initial:Vector3) -> Dictionary:
	var p=global_position;var pts=PackedVector3Array([p]);var v=Vector3(initial.x,-sink_speed,initial.z);var duration=0.0;var normal=Vector3.UP;var hit_surface=false
	for i in 40:
		var next=p+v*.15;var ray=PhysicsRayQueryParameters3D.create(p,next,1);ray.exclude=[get_rid(),deck.get_rid()];var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		duration+=.15
		if not hit.is_empty():p=hit.position;normal=hit.normal;hit_surface=true;pts.append(p);break
		p=next;pts.append(p)
	return {"point":p,"normal":normal,"gain":duration,"time":duration,"hit":hit_surface,"points":pts}
