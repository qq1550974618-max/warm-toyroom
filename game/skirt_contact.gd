extends SkeletonModifier3D

# Eight skinned panels respond to thigh/calf capsules after locomotion and carry IK.
# Only the fabric moves: cloth contact never changes player motion or foot anchors.
var actor:CharacterBody3D
var angles:=PackedFloat32Array()
var rates:=PackedFloat32Array()
var contact_count:=0
var maximum_deflection:=0.0
var capsules:Array=[]
var applied_stride_scale=1.0
var minimum_contact_clearance=1.0
var panel_offsets:Array[Vector3]=[]
var subtle_walk_contact:=true

func _ready() -> void:
	angles.resize(8);rates.resize(8);panel_offsets.resize(8);panel_offsets.fill(Vector3.ZERO)

func closest(a:Vector3,b:Vector3,p:Vector3) -> Vector3:
	var d:=b-a
	return a+d*clampf((p-a).dot(d)/maxf(d.length_squared(),.00001),0,1)

func clearance(skel:Skeleton3D,root_pose:Transform3D,child:Vector3,axis:Vector3,angle:float) -> float:
	var end:=root_pose.origin+Basis(axis,angle)*(child-root_pose.origin);var result:=1.0
	for t in [.30,.55,.80,1.0]:
		var p:=root_pose.origin.lerp(end,t)
		for cap in capsules:result=minf(result,p.distance_to(closest(cap[0],cap[1],p))-cap[2])
	return result

func _process_modification_with_delta(delta:float) -> void:
	if actor==null:return
	if actor.state in ["roll","dash","stunned","flattened"]:
		angles.fill(0);rates.fill(0);panel_offsets.fill(Vector3.ZERO);return
	var skel:=get_skeleton();capsules.clear()
	var calm_walk:bool=subtle_walk_contact and actor.state=="walk"
	applied_stride_scale=actor.gait_stride_scale(actor.state=="run") if actor.state in ["walk","run"] else 1.0
	if applied_stride_scale<.999:
		for i in skel.get_bone_count():
			if not skel.get_bone_name(i).begins_with("Skirt_"):continue
			var rest=skel.get_bone_rest(i)
			# The imported clip already flares all three bones of each skirt panel.
			# Keep a smaller authored sway before adding actual leg contact, rather
			# than stacking a large baked flare and a large collision flare.
			var sway=applied_stride_scale*(.65 if calm_walk else 1.0)
			skel.set_bone_pose_rotation(i,rest.basis.get_rotation_quaternion().slerp(skel.get_bone_pose_rotation(i),sway))
	# Use authored rest chains for the resting skirt, independent of idle clip oscillation.
	if actor.state=="idle":
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).begins_with("Skirt_"):skel.reset_bone_pose(i)
	for side in ["L","R"]:
		var thigh:=skel.get_bone_global_pose(skel.find_bone(side+"_Thigh")).origin
		var knee:=skel.get_bone_global_pose(skel.find_bone(side+"_Calf")).origin
		var foot:=skel.get_bone_global_pose(skel.find_bone(side+"_Foot")).origin
		capsules.append([thigh,knee,.064]);capsules.append([knee,foot,.053])
	for n in 8:
		var index:=skel.find_bone("Skirt_%02d_01"%(n+1));var tip:=skel.find_bone("Skirt_%02d_Tip"%(n+1))
		var pose:=skel.get_bone_global_pose(index);var child:=skel.get_bone_global_pose(tip).origin
		var outward:=Vector3(child.x-.045,0,child.z-.002).normalized();var axis:=(child-pose.origin).cross(outward).normalized()
		var needed:=0.0
		if clearance(skel,pose,child,axis,0)<.003:
			var lo=0.0;var hi=.25 if calm_walk else .60
			for step in 7:
				var mid=(lo+hi)*.5
				if clearance(skel,pose,child,axis,mid)<.004:lo=mid
				else:hi=mid
			needed=hi
		# A small contact dead band avoids toggling cloth on a nearly touching leg.
		if absf(needed-angles[n])<.008:needed=angles[n]
		if needed>.001:contact_count+=1
		# Immediate non-penetrating contact and damped release, with no bounce.
		rates[n]=0
		angles[n]=maxf(needed,lerpf(angles[n],needed,1-exp(-delta*17)))
		if angles[n]<=needed and rates[n]<0:rates[n]=0
		maximum_deflection=maxf(maximum_deflection,angles[n])
		# At the upper thigh, rotating the hem alone cannot resolve contact.
		# A small local fabric offset clears the leg without a larger skirt flare.
		# Walking uses this local response instead of rotating the whole panel up.
		var correction=Vector3.ZERO
		var end=pose.origin+Basis(axis,angles[n])*(child-pose.origin)
		for iteration in 5:
			var worst=.003;var away=Vector3.ZERO
			for t in [.30,.55,.80,1.0]:
				var point=pose.origin.lerp(end,t)+correction
				for cap in capsules:
					var difference=point-closest(cap[0],cap[1],point);var gap=difference.length()-cap[2]
					if gap<worst:worst=gap;away=Vector3(difference.x,0,difference.z)
			if worst>=.003:break
			if away.length_squared()<.000001:away=outward
			correction+=away.normalized()*(.003-worst)*1.15
		var prior=panel_offsets[n]
		panel_offsets[n]=correction if correction.length()>prior.length() or correction.dot(prior)<0 else prior.lerp(correction,1-exp(-delta*17))
		pose.origin+=panel_offsets[n];child+=panel_offsets[n]
		minimum_contact_clearance=minf(minimum_contact_clearance,clearance(skel,pose,child,axis,angles[n]))
		pose.basis=Basis(axis,angles[n])*pose.basis;skel.set_bone_global_pose(index,pose)
