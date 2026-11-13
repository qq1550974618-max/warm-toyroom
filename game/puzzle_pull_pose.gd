extends SkeletonModifier3D
var actor:CharacterBody3D
var puzzles:Node3D
var weight:=0.0
func reset_transient_pose() -> void:weight=0
func _process_modification_with_delta(delta:float) -> void:
	var active=puzzles.is_pulling(actor) or puzzles.is_using_lift(actor)
	weight=move_toward(weight,1.0 if active else 0.0,delta*5)
	if weight<.001:return
	var s=get_skeleton();var saved:Array=[]
	for i in s.get_bone_count():saved.append(s.get_bone_pose(i))
	# Hip/back counterbalance, soft knee bend, both hands pull at reachable height.
	actor.locomotion._bend(s,"Spine01",Vector3.BACK,.14*weight)
	actor.locomotion._bend(s,"L_Thigh",Vector3.BACK,-.18*weight)
	actor.locomotion._bend(s,"R_Thigh",Vector3.BACK,-.18*weight)
	for side in ["L","R"]:
		var shoulder=s.find_bone(side+"_Upperarm")
		if shoulder<0:continue
		var handle=puzzles.board_handle.global_position if puzzles.is_pulling(actor) else puzzles.lift_lever.to_global(Vector3(0,.073,0))
		# Model forward is +X, so anatomical left is -Z. Keep hands on their
		# own sides of the grip instead of crossing both arms through the chest.
		var left=-actor.visual.global_basis.z.normalized()
		var p=s.global_transform.affine_inverse()*(handle+left*(.045 if side=="L" else -.045))
		actor.locomotion._chain(s,side+"_Upperarm",side+"_Forearm",side+"_Hand",p,Vector3(0,-.5,-1 if side=="L" else 1))
	for i in s.get_bone_count():
		var p:Transform3D=saved[i].interpolate_with(s.get_bone_pose(i),weight)
		s.set_bone_pose_position(i,p.origin);s.set_bone_pose_rotation(i,p.basis.get_rotation_quaternion());s.set_bone_pose_scale(i,p.basis.get_scale())
