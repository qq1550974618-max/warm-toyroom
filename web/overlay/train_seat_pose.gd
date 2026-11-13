extends SkeletonModifier3D
var train
var actor
func _process_modification_with_delta(_delta:float) -> void:
	if not train.seated:return
	var s=get_skeleton();s.reset_bone_poses()
	actor.locomotion._bend(s,"Spine01",Vector3.BACK,-.06)
	for side in ["L","R"]:
		var sign_z=-1 if side=="L" else 1
		actor.locomotion._chain(s,side+"_Thigh",side+"_Calf",side+"_Foot",Vector3(.22,.08,sign_z*.10),Vector3(1,.2,sign_z*.2))
		actor.locomotion._chain(s,side+"_Upperarm",side+"_Forearm",side+"_Hand",Vector3(.29,.43,sign_z*.10),Vector3(.3,-.2,sign_z))
