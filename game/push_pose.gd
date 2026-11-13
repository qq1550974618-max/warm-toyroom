extends SkeletonModifier3D
var actor:CharacterBody3D
var ball:RigidBody3D
var weight:=0.0
var hand_surface_gaps:Array=[]
var contact_diagnostics:Array=[]
func reset_transient_pose() -> void:
	if ball==null or not ball.pushing:weight=0.0
func _process_modification_with_delta(delta:float) -> void:
	weight=move_toward(weight,1.0 if ball.pushing and actor.state!="flattened" else 0.0,delta*6)
	if weight<.001:return
	var s:=get_skeleton();var saved:Array[Transform3D]=[]
	for i in s.get_bone_count():saved.append(s.get_bone_pose(i))
	actor.locomotion._bend(s,"Spine01",Vector3.BACK,-.20)
	var chest_id:=s.find_bone("Spine01");var chest:=s.get_bone_global_pose(chest_id)
	chest.origin+=Vector3(.14,.01,0);s.set_bone_global_pose(chest_id,chest)
	# Lean the chest into the push while keeping the large toy head clear.
	var neck_id:=s.find_bone("NeckTwist01");var neck:=s.get_bone_global_pose(neck_id)
	neck.origin.x-=.14;s.set_bone_global_pose(neck_id,neck)
	contact_diagnostics.clear()
	for pair in [["L",-1.0],["R",1.0]]:
		var upper:Vector3=s.global_transform*s.get_bone_global_pose(s.find_bone(pair[0]+"_Upperarm")).origin
		# Each short arm reaches its own nearest patch; the old fixed side targets
		# crossed the two hands and were beyond this chibi rig's arm length.
		var target:Vector3=ball.global_position+(upper-ball.global_position).normalized()*(ball.radius+.008)
		var fore:Vector3=s.global_transform*s.get_bone_global_pose(s.find_bone(pair[0]+"_Forearm")).origin
		var tip:Vector3=s.global_transform*s.get_bone_global_pose(s.find_bone(pair[0]+"_Hand")).origin
		contact_diagnostics.append({"upper":str(upper),"target":str(target),"distance":upper.distance_to(target),"reach":upper.distance_to(fore)+fore.distance_to(tip),"actor":str(actor.global_position),"ball":str(ball.global_position)})
		actor.locomotion._chain(s,pair[0]+"_Upperarm",pair[0]+"_Forearm",pair[0]+"_Hand",s.global_transform.affine_inverse()*target,Vector3(0,-.6,pair[1]))
	for i in s.get_bone_count():
		var p:=saved[i].interpolate_with(s.get_bone_pose(i),weight);s.set_bone_pose_position(i,p.origin);s.set_bone_pose_rotation(i,p.basis.get_rotation_quaternion())
		s.set_bone_pose_scale(i,p.basis.get_scale())
	# Record the evaluated pose before SkeletonModifier restores its input bones.
	hand_surface_gaps.clear()
	for hand in ["L_Hand","R_Hand"]:
		var point:Vector3=s.global_transform*s.get_bone_global_pose(s.find_bone(hand)).origin
		hand_surface_gaps.append(absf(point.distance_to(ball.global_position)-ball.radius))
