extends SkeletonModifier3D

var head_drop_m := 0.016
var applied_drop_m := 0.0
var head_back_m := 0.012
var applied_back_m := 0.0

func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	var head := skel.find_bone("Head")
	var neck := skel.find_bone("NeckTwist01")
	if head < 0 or neck < 0: return
	var pose := skel.get_bone_global_pose(head)
	var axis := pose.origin - skel.get_bone_global_pose(neck).origin
	applied_drop_m = clampf(head_drop_m, 0, axis.length() * 0.65)
	# Follow the current neck direction, including lying-down poses. The head
	# keeps its scale and basis; its attached hair and headpiece move together.
	if applied_drop_m > 0: pose.origin -= axis.normalized() * applied_drop_m
	var neck_pose := skel.get_bone_global_pose(neck)
	var neck_rest := skel.get_bone_global_rest(neck)
	var forward := (neck_pose.basis * neck_rest.basis.inverse() * Vector3.RIGHT).normalized()
	applied_back_m = clampf(head_back_m, 0.0, 0.012)
	pose.origin -= forward * applied_back_m
	skel.set_bone_global_pose(head, pose)
