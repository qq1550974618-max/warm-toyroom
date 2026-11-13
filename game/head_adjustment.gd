extends SkeletonModifier3D
# User-directed additive offset after the existing locomotion and carry pose.
# Do not auto-correct the requested position; the user judges its appearance.
# SkeletonModifier restores the input pose after skinning: no accumulated drift.
var actor:CharacterBody3D
const FIXED_OFFSET_MM=Vector3(0,5,0)
var offset_mm:=FIXED_OFFSET_MM
var last_input:=Vector3.ZERO
var last_output:=Vector3.ZERO
var sample_count:=0
var head_id:=-1
func _ready() -> void:head_id=get_skeleton().find_bone("Head")
func set_offset(_value:Vector3) -> void:
	offset_mm=FIXED_OFFSET_MM
func _process_modification_with_delta(_delta:float) -> void:
	var skeleton:=get_skeleton()
	if head_id<0:return
	var pose:=skeleton.get_bone_global_pose(head_id);last_input=pose.origin
	if not actor.state in ["roll","dash","flattened","dead"]:
		pose.origin+=offset_mm*.001/maxf(.01,actor.visual_scale)
		skeleton.set_bone_global_pose(head_id,pose)
	last_output=pose.origin;sample_count+=1
