extends Node

var actor:Node3D
var faces:Array[MeshInstance3D]=[]
var clock:=0.0
var next_blink:=2.3
var blink_time:=-1.0
var blink_count:=0
var blink_value:=0.0
var force_blink:=-1.0

func setup(owner_actor:Node3D) -> void:
	actor=owner_actor
	for node in actor.chibi_meshes:
		if not (str(node.name).begins_with("QPart_56") or str(node.name).begins_with("QPart_51") or str(node.name).begins_with("QPart_52")):continue
		var original:Mesh=node.mesh;var replacement:=ArrayMesh.new();replacement.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED;replacement.add_blend_shape("Blink")
		var to_model:Transform3D=actor.visual.global_transform.affine_inverse()*node.global_transform
		for s in original.get_surface_count():
			var arrays:=original.surface_get_arrays(s);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var closed:=vertices.duplicate()
			for i in vertices.size():
				var p:Vector3=to_model*vertices[i];var dz:float=minf(absf(p.z+.076),absf(p.z-.080))
				var strength:float=(1-smoothstep(.036,.060,dz))*smoothstep(.125,.158,p.x)
				var y_weight:float=smoothstep(.513,.540,p.y)*(1-smoothstep(.605,.646,p.y))
				var target_y:float=.557+(p.y-.570)*.045
				p.y=lerpf(p.y,target_y,strength*y_weight);closed[i]=to_model.affine_inverse()*p
			var shape:Array=[];shape.resize(Mesh.ARRAY_MAX);shape[Mesh.ARRAY_VERTEX]=closed;shape[Mesh.ARRAY_NORMAL]=arrays[Mesh.ARRAY_NORMAL];shape[Mesh.ARRAY_TANGENT]=arrays[Mesh.ARRAY_TANGENT]
			var flags:int=Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if arrays[Mesh.ARRAY_BONES].size()>vertices.size()*4 else 0
			replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[shape],{},flags);replacement.surface_set_material(s,original.surface_get_material(s))
		node.mesh=replacement;faces.append(node)

func _process(delta:float) -> void:
	clock+=delta
	blink_value=0
	if clock>=next_blink and blink_time<0:blink_time=0;blink_count+=1;next_blink=clock+3.0+fmod(blink_count*1.618,1.5)
	if blink_time>=0:
		blink_time+=delta
		if blink_time<.075:blink_value=smoothstep(0,.075,blink_time)
		elif blink_time<.115:blink_value=1
		elif blink_time<.235:blink_value=1-smoothstep(.115,.235,blink_time)
		else:blink_value=0;blink_time=-1
	if force_blink>=0:blink_value=force_blink
	if actor.state in ["roll","dash"]:blink_value=maxf(blink_value,actor.roll_weight)
	if actor.state=="stunned":blink_value=1.0 if actor.stun_time<actor.stun_duration else .5
	for face in faces:face.set_blend_shape_value(0,blink_value)
