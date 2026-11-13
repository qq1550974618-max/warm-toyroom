extends SkeletonModifier3D

# Only the existing 1,969-vertex forelock receives three lightweight bend binds.
# The rest of the character keeps its original geometry, weights and materials.
var actor:CharacterBody3D
var room:Node3D
var strand:MeshInstance3D
var head_id=-1
var bend_bones:PackedInt32Array=[]
var head_inverse:Transform3D
var base=Vector3.ZERO
var height=.1
var probes:PackedVector3Array=[]
var angles=Vector2.ZERO
var rates=Vector2.ZERO
var previous_head=Vector3.ZERO
var previous_velocity=Vector3.ZERO
var initialized=false
var small_sphere=SphereShape3D.new()
var broad_sphere=SphereShape3D.new()
var contact_frames=0
var maximum_bend=0.0
var maximum_inertial_bend=0.0
var last_minimum_clearance=1.0
var last_solve_usec=0
var last_world_probes:PackedVector3Array=[]
const RADIUS=.0035

func reset_transient_pose() -> void:
	angles=Vector2.ZERO;rates=Vector2.ZERO;initialized=false

func _ready() -> void:
	small_sphere.radius=RADIUS;broad_sphere.radius=.085
	var skel=get_skeleton();head_id=skel.find_bone("Head");head_inverse=skel.get_bone_global_rest(head_id).affine_inverse()
	for mesh in actor.chibi_meshes:
		if str(mesh.name).begins_with("QPart_15_"):strand=mesh;break
	if strand==null:active=false;return
	var source:ArrayMesh=strand.mesh;var bounds=source.get_aabb();var low=Vector3.ZERO;var low_count=0
	for surface in source.get_surface_count():
		var verts:PackedVector3Array=source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for point in verts:
			if point.y<bounds.position.y+.006:low+=point;low_count+=1
	base=low/maxf(1,low_count);height=maxf(.001,bounds.end.y-base.y)
	var skin=Skin.new()
	for i in 3:
		var bone_name="ForelockBend%d"%i;skel.add_bone(bone_name);var index=skel.find_bone(bone_name)
		skel.set_bone_parent(index,head_id);skel.set_bone_rest(index,head_inverse*Transform3D(Basis.IDENTITY,base));skel.reset_bone_pose(index)
		bend_bones.append(index);skin.add_named_bind(bone_name,Transform3D(Basis.IDENTITY,base).affine_inverse())
	var replacement=ArrayMesh.new();var cells={}
	for surface in source.get_surface_count():
		var arrays=source.surface_get_arrays(surface);var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones=PackedInt32Array();var weights=PackedFloat32Array();bones.resize(verts.size()*4);weights.resize(verts.size()*4)
		for i in verts.size():
			var t=clampf((verts[i].y-base.y)/height,0,1)*2;var first=mini(1,int(t));var blend=t-first
			bones[i*4]=first;bones[i*4+1]=first+1;weights[i*4]=1-blend;weights[i*4+1]=blend
			# Surface representatives on both faces, including the fine curled tip.
			var cell=Vector3i(floori((verts[i].x-bounds.position.x)/.05),floori((verts[i].y-base.y)/.03),floori((verts[i].z-bounds.position.z)/.045))
			if not cells.has(cell) or verts[i].y>cells[cell].y:cells[cell]=verts[i]
		arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights
		replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		replacement.surface_set_material(surface,source.surface_get_material(surface))
	strand.mesh=replacement;strand.skin=skin
	for point in cells.values():
		if point.y-base.y>.018:probes.append(point)
	strand.custom_aabb=bounds.grow(.15)

func deform(point:Vector3,bend:Vector2) -> Vector3:
	var t=clampf((point.y-base.y)/height,0,1)*2;var first=mini(1,int(t));var blend=t-first
	var a=Basis.from_euler(Vector3(bend.x*first*.5,0,bend.y*first*.5))
	var b=Basis.from_euler(Vector3(bend.x*(first+1)*.5,0,bend.y*(first+1)*.5))
	return base+(a*(point-base)).lerp(b*(point-base),blend)

func _process_modification_with_delta(delta:float) -> void:
	if not is_instance_valid(actor) or strand==null:return
	var started=Time.get_ticks_usec();var skel=get_skeleton()
	if not room.ready_to_play or actor.state in ["roll","dash","flattened","dead"]:
		angles=Vector2.ZERO;rates=Vector2.ZERO;initialized=false;return
	var head_frame=skel.global_transform*skel.get_bone_global_pose(head_id)*head_inverse
	var head_point=head_frame*base
	if not initialized or head_point.distance_to(previous_head)>.30:
		previous_head=head_point;previous_velocity=Vector3.ZERO;angles=Vector2.ZERO;rates=Vector2.ZERO;initialized=true
	var step=clampf(delta,.001,.034);var velocity=(head_point-previous_head)/step
	var acceleration=(velocity-previous_velocity)/step;previous_head=head_point;previous_velocity=velocity
	var local_accel=head_frame.basis.orthonormalized().inverse()*acceleration.limit_length(8)
	var target=Vector2(-local_accel.z,local_accel.x).limit_length(4)*.045
	for substep in 2:
		rates+=((target-angles)*65-rates*8)*step*.5;angles+=rates*step*.5
	angles=angles.limit_length(1.35)
	var excluded:Array[RID]=[actor.get_rid()]
	if room.paper_plane!=null:excluded.append(room.paper_plane.get_rid());excluded.append(room.paper_plane.deck.get_rid())
	var query=PhysicsShapeQueryParameters3D.new();query.shape=broad_sphere;query.transform=Transform3D(Basis.IDENTITY,head_point);query.collision_mask=5;query.exclude=excluded
	var space=actor.get_world_3d().direct_space_state
	var nearby=not space.intersect_shape(query,1).is_empty()
	query.shape=small_sphere
	var touched=false;last_minimum_clearance=1.0
	for iteration in 3:
		var corrected=false
		for point in probes:
			var world:Vector3=head_frame*deform(point,angles);var normal=Vector3.ZERO;var penetration=0.0
			if room.paper_plane!=null and world.distance_to(room.paper_plane.position)<.95:
				var hit=preload("res://carry_geometry.gd").paper_contact(room.paper_plane.to_local(world))
				if hit.w<RADIUS:
					normal=(room.paper_plane.global_basis*Vector3(hit.x,hit.y,hit.z)).normalized();penetration=RADIUS-hit.w
			if nearby:
				query.transform.origin=world;var contact=space.get_rest_info(query)
				if not contact.is_empty():
					var n:Vector3=contact.normal;var depth=RADIUS-(world-contact.point).dot(n)
					if depth>penetration:normal=n;penetration=depth
			if penetration<=.00015:continue
			var dx:Vector3=(head_frame*deform(point,angles+Vector2(.015,0))-world)/.015
			var dz:Vector3=(head_frame*deform(point,angles+Vector2(0,.015))-world)/.015
			var gradient=Vector2(normal.dot(dx),normal.dot(dz))
			if gradient.length_squared()<.0000001:continue
			angles+=(gradient*penetration/(gradient.length_squared()+.000001)).limit_length(.18)
			angles=angles.limit_length(1.35)
			var inward=rates.dot(gradient)
			if inward<0:rates-=gradient*inward/gradient.length_squared()
			touched=true;corrected=true
		if not corrected:break
	last_world_probes.clear()
	for point in probes:
		var world:Vector3=head_frame*deform(point,angles);last_world_probes.append(world)
		if room.paper_plane!=null and world.distance_to(room.paper_plane.position)<.95:
			last_minimum_clearance=minf(last_minimum_clearance,preload("res://carry_geometry.gd").paper_contact(room.paper_plane.to_local(world)).w)
	if touched:contact_frames+=1
	else:maximum_inertial_bend=maxf(maximum_inertial_bend,angles.length())
	maximum_bend=maxf(maximum_bend,angles.length())
	for i in 3:
		var global_pose=skel.get_bone_global_pose(head_id)*head_inverse*Transform3D(Basis.from_euler(Vector3(angles.x*i*.5,0,angles.y*i*.5)),base)
		skel.set_bone_global_pose(bend_bones[i],global_pose)
	last_solve_usec=Time.get_ticks_usec()-started
