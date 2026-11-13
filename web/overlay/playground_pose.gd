extends SkeletonModifier3D
var actor
var applied_frames=0
func _process_modification_with_delta(_delta:float) -> void:
	if actor==null or actor.pose_mode=="":return
	var s=get_skeleton();var t:float=actor.pose_time
	var mode:String=actor.pose_mode
	if mode=="press":
		var weight=sin(PI*clampf(t/.52,0,1))
		actor.locomotion._bend(s,"Spine01",Vector3.BACK,-.18*weight)
		var target=s.global_transform.affine_inverse()*actor.press_target
		var hand=s.get_bone_global_pose(s.find_bone("R_Hand")).origin
		actor.locomotion._chain(s,"R_Upperarm","R_Forearm","R_Hand",hand.lerp(target,weight),Vector3(0,-.4,1))
	elif mode=="eat":
		s.reset_bone_poses()
		actor.locomotion._bend(s,"Spine01",Vector3.BACK,-.08)
		actor.locomotion._bend(s,"Head",Vector3.BACK,.12+sin(t*28)*.08)
		actor.locomotion._bend(s,"Tail_01",Vector3.RIGHT,.20*sin(t*11))
		actor.locomotion._bend(s,"Tail_02",Vector3.RIGHT,.22*sin(t*11-1.1))
		for i in range(1,7):
			actor.locomotion._bend(s,"Hair_%02d_02"%i,Vector3.RIGHT,.13*sin(t*11-i*.35))
		for side in ["L","R"]:
			var sign_z=-1.0 if side=="L" else 1.0
			var phase=t*20+(0 if side=="L" else PI)
			actor.locomotion._chain(s,side+"_Upperarm",side+"_Forearm",side+"_Hand",Vector3(.25+.07*sin(phase),.51+.05*cos(phase),sign_z*.14),Vector3(0,-1,sign_z))
			actor.locomotion._chain(s,side+"_Thigh",side+"_Calf",side+"_Foot",Vector3(-.025+.018*sin(phase),.045+.035*(.5+.5*cos(phase)),sign_z*.105),Vector3(.5,0,sign_z))
	elif mode=="launch" or mode=="meal_jump":
		# Reference: tucked feet forward, hands gathered at takeoff, then arms
		# opening as the doll sails upwards. Continuous anticipation and settle.
		var opening=smoothstep(.10,.46,t)
		var flutter=sin(t*11)*.025*smoothstep(.3,.65,t)
		actor.locomotion._bend(s,"Waist",Vector3.BACK,.13*opening)
		actor.locomotion._bend(s,"Spine01",Vector3.BACK,-.055+.035*sin(t*6))
		actor.locomotion._bend(s,"Head",Vector3.BACK,-.09*opening)
		for side in ["L","R"]:
			var sign_z=-1.0 if side=="L" else 1.0
			var hand=Vector3(lerpf(.19,.07,opening),.36+.08*opening+flutter*sign_z,sign_z*lerpf(.14,.23,opening))
			actor.locomotion._chain(s,side+"_Upperarm",side+"_Forearm",side+"_Hand",hand,Vector3(0,.2,sign_z))
			actor.locomotion._chain(s,side+"_Thigh",side+"_Calf",side+"_Foot",Vector3(.14,.17+flutter*.4,sign_z*.09),Vector3(1,.35,sign_z*.2))
			actor.locomotion._bend(s,side+"_Foot",Vector3.BACK,-.18)
	elif mode=="dive":
		actor.locomotion._bend(s,"Spine01",Vector3.BACK,-.17)
		for side in ["L","R"]:
			var sign_z=-1.0 if side=="L" else 1.0
			actor.locomotion._chain(s,side+"_Upperarm",side+"_Forearm",side+"_Hand",Vector3(-.07,.46,sign_z*.14),Vector3(-.5,0,sign_z))
	applied_frames+=1
