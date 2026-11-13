extends "res://locomotion_modifier.gd"

var phase_samples: Array = []
var maximum_swing_height := 0.0
var reference_pose_frames := 0

func _process_modification_with_delta(delta: float) -> void:
	if actor==null:return
	if actor.state=="train":
		release_feet();return
	if actor.state=="flattened":
		release_feet();get_skeleton().reset_bone_poses();return
	if actor.state=="stunned":
		release_feet();_stun_pose();return
	if actor.state=="roll":
		release_feet()
		# The blue shell is fully opaque here; retain curl solving for both
		# visible transitions, but not for the completely hidden skeleton.
		if actor.roll_weight>=.94 and actor.roll_recovery<0:return
		if actor.roll_time<actor.BALL_CROUCH_TIME:_ball_anticipation()
		else:_ground_ball_pose(actor.roll_weight if actor.roll_recovery>=0 else 1.0)
		return
	if actor.state=="dash":
		release_feet();_curl_pose(actor.roll_weight);return
	if actor.state in ["prepare","air","land"]:
		release_feet();_reference_jump_pose();return
	# A one-frame loss of floor contact over a plank seam must not switch to
	# the unrelated source clip. Match the controller's short ledge grace.
	var gait_support=actor.ground_motion or (actor.state in ["walk","run"] and actor.air_time<=.06)
	if actor.state not in ["walk","run"] or not gait_support or actor.gait_weight<.1:
		super._process_modification_with_delta(delta);return
	if previous_motion_state not in ["walk","run"]:release_feet()
	var skel:=get_skeleton();var hip_id:=skel.find_bone("Hip");var hip:=skel.get_bone_global_pose(hip_id)
	var gait_blend:float=smoothstep(0,1,actor.gait_weight)
	var stance:float=actor.gait_contact_fraction(actor.state=="run")
	var phase:float=actor.gait_phase
	var flight:float=sin(PI*clampf((fposmod(phase,.5)-stance)/(.5-stance),0,1))
	var amplitude:float=actor.gait_body_amplitude(actor.state=="run")
	hip.origin=hip.origin.lerp(skel.get_bone_global_rest(hip_id).origin+Vector3(0,-.060+flight*.028*amplitude,0),gait_blend)
	hip.basis=hip.basis.slerp(Basis(Vector3.BACK,-.10 if actor.state=="run" else -.035)*skel.get_bone_global_rest(hip_id).basis,gait_blend)
	skel.set_bone_global_pose(hip_id,hip)
	_reference_running_upper_body(skel,phase,actor.state=="run")
	var heading:=Basis(Vector3.UP,actor.visual.rotation.y)
	# The phase follows actual distance travelled. Use that same displacement
	# rate for stride prediction: a slide collision can zero velocity for one
	# frame despite the body having travelled, which collapsed both feet inward.
	var stride_length:float=actor.gait_cycle_distance(actor.state=="run")
	var travel:Vector3=heading*Vector3.RIGHT*stride_length*actor.gait_rate
	locked_count=0
	for leg in legs:
		var p:float=fposmod(phase+(0.0 if leg.side=="L" else .5),1.0)
		var rest:=skel.get_bone_global_rest(leg.foot).origin
		var base_world:Vector3=skel.global_transform*Vector3(rest.x,0,rest.z)
		var half_support:float=stance/actor.gait_rate*.5
		var target_world:Vector3
		if p<stance:
			if not leg.locked:
				var candidate:Vector3=base_world+travel*(half_support-p/actor.gait_rate)
				var ground:Variant=_support_ground_at(candidate)
				if ground!=null:
					leg.anchor=Vector3(candidate.x,float(ground)+rest.y*actor.visual_scale,candidate.z)
					leg.locked=true;plant_events[leg.side]+=1
			leg.weight=gait_blend if leg.locked else 0.0
			target_world=leg.anchor if leg.locked else skel.global_transform*rest
			leg.swing_start=target_world
		else:
			leg.locked=false;leg.weight=0.0
			var u:float=(p-stance)/(1-stance)
			if not leg.has("swing_start"):leg.swing_start=skel.global_transform*rest
			# Swing relative to the moving pelvis. Predicting a whole cycle ahead
			# exceeded the short legs' reach and caused clamping instead of a step.
			var landing:Vector3=base_world+travel*half_support
			var ground:Variant=_support_ground_at(landing)
			landing.y=(float(ground) if ground!=null else actor.global_position.y)+rest.y*actor.visual_scale
			target_world=base_world+travel*half_support*lerpf(-1,1,smoothstep(0,1,u))
			target_world.y=landing.y
			var lift:float=sin(PI*u)*(.055 if actor.state=="run" else .042)*actor.motion_scale*amplitude
			target_world.y+=lift;maximum_swing_height=maxf(maximum_swing_height,lift)
		var target:Vector3=skel.global_transform.affine_inverse()*target_world
		target=skel.get_bone_global_pose(leg.foot).origin.lerp(target,gait_blend)
		# Contact duration and pelvis height keep locked feet within the short legs' reach.
		_solve_leg(skel,leg,target)
		if leg.locked:locked_count+=1
		var foot_pose:=skel.get_bone_global_pose(leg.foot)
		foot_pose.basis=skel.get_bone_global_rest(leg.foot).basis
		skel.set_bone_global_pose(leg.foot,foot_pose)
	if phase_samples.size()<1200:
		phase_samples.append({"phase":phase,"state":actor.state,"L":str(skel.global_transform*skel.get_bone_global_pose(legs[0].foot).origin),"R":str(skel.global_transform*skel.get_bone_global_pose(legs[1].foot).origin),"speed":travel.length()})
	previous_motion_state=actor.state

func _support_ground_at(point:Vector3) -> Variant:
	var ground:Variant=_ground_at(point+Vector3.UP*.06)
	# A sole spans the fine floorboard seams. A single centre ray sometimes hit
	# the subfloor 3.5 cm below, abruptly lowering a swinging foot for one frame.
	# Preserve real stair heights while sharing the body's support across seams.
	if ground!=null and actor.is_on_floor() and absf(float(ground)-actor.global_position.y)<.04:
		return maxf(float(ground),actor.global_position.y)
	return ground

func _reference_running_upper_body(skel:Skeleton3D,phase:float,running:bool) -> void:
	# Short bent elbows, counter-rotating shoulders and a stable head. The leg
	# solver below still owns world-space stance anchors and alternating feet.
	var amplitude:float=actor.gait_body_amplitude(running)
	var wave=sin(TAU*phase)*amplitude;var amount:float=actor.gait_weight
	_bend(skel,"Spine01",Vector3.UP,.055*wave*amount)
	_bend(skel,"Spine02",Vector3.BACK,(-.055 if running else -.025)*amount)
	_bend(skel,"Head",Vector3.UP,-.035*wave*amount)
	_bend(skel,"Head",Vector3.BACK,(.055 if running else .025)*amount)
	for side in ["L","R"]:
		var z:float=-1 if side=="L" else 1
		var swing=wave*z
		var current=skel.get_bone_global_pose(skel.find_bone(side+"_Hand")).origin
		var target=Vector3(.13+swing*(.060 if running else .045),.315+.018*cos(TAU*phase*z)*amplitude,z*.15)
		_chain(skel,side+"_Upperarm",side+"_Forearm",side+"_Hand",current.lerp(target,amount*.82),Vector3(-.3,-.5,z))
	reference_pose_frames+=1

func _reference_jump_pose() -> void:
	var skel=get_skeleton();var original:Array[Transform3D]=[]
	for i in skel.get_bone_count():original.append(skel.get_bone_pose(i))
	# Reconstruct only the main limbs; skirt/hair secondary motion stays live.
	for bone in ["Hip","Waist","Spine01","Spine02","NeckTwist01","Head","L_Thigh","L_Calf","L_Foot","R_Thigh","R_Calf","R_Foot","L_Upperarm","L_Forearm","L_Hand","R_Upperarm","R_Forearm","R_Hand"]:
		var index=skel.find_bone(bone)
		if index>=0:skel.reset_bone_pose(index)
	var hip_id=skel.find_bone("Hip");var hip=skel.get_bone_global_pose(hip_id)
	var weight=1.0
	if actor.state=="prepare" or actor.state=="land":
		var u=clampf((.065-actor.jump_timer)/.065,0,1) if actor.state=="prepare" else clampf(1-actor.jump_timer/.13,0,1)
		var compression=sin(PI*u) if actor.state=="land" else smoothstep(0,1,u)
		hip.origin.y-=.045*compression;skel.set_bone_global_pose(hip_id,hip)
		_bend(skel,"Spine01",Vector3.BACK,-.13*compression)
		_bend(skel,"Head",Vector3.BACK,.09*compression)
		for side in ["L","R"]:
			var z:float=-1 if side=="L" else 1
			_chain(skel,side+"_Upperarm",side+"_Forearm",side+"_Hand",Vector3(-.02,.30,z*.16),Vector3(-.5,-.5,z))
			_chain(skel,side+"_Thigh",side+"_Calf",side+"_Foot",skel.get_bone_global_rest(skel.find_bone(side+"_Foot")).origin,Vector3.RIGHT)
		weight=.82 if actor.state=="prepare" else sin(PI*u)*.85
	else:
		var rising=clampf(actor.velocity.y/actor.jump_velocity,0,1)
		var falling=smoothstep(0,3.5,maxf(0,-actor.velocity.y))
		var settle=smoothstep(0,.13,actor.air_time)
		hip.origin.y-=.035*settle;skel.set_bone_global_pose(hip_id,hip)
		_bend(skel,"Waist",Vector3.BACK,.08*settle-.09*falling)
		_bend(skel,"Spine01",Vector3.BACK,-.055)
		_bend(skel,"Head",Vector3.BACK,-.035+.06*falling)
		for side in ["L","R"]:
			var z:float=-1 if side=="L" else 1
			var tucked=Vector3(.13,.14,z*.082)
			var landing=skel.get_bone_global_rest(skel.find_bone(side+"_Foot")).origin+Vector3(.035,.012,0)
			_chain(skel,side+"_Thigh",side+"_Calf",side+"_Foot",tucked.lerp(landing,falling),Vector3(1,.4,z*.15))
			var hand=Vector3(.18-.10*falling,.365+.035*(1-rising),z*lerpf(.15,.23,1-rising))
			_chain(skel,side+"_Upperarm",side+"_Forearm",side+"_Hand",hand,Vector3(0,-.3,z))
			_bend(skel,side+"_Foot",Vector3.BACK,-.16*(1-falling))
		weight=smoothstep(0,.10,actor.air_time)*.86
	for i in skel.get_bone_count():
		var pose=original[i].interpolate_with(skel.get_bone_pose(i),weight)
		skel.set_bone_pose_position(i,pose.origin);skel.set_bone_pose_rotation(i,pose.basis.get_rotation_quaternion());skel.set_bone_pose_scale(i,pose.basis.get_scale())
	reference_pose_frames+=1

func _bend(skel:Skeleton3D,bone_name:String,axis:Vector3,angle:float) -> void:
	var i:=skel.find_bone(bone_name)
	if i<0:return
	var pose:=skel.get_bone_global_pose(i);pose.basis=Basis(axis,angle)*pose.basis;skel.set_bone_global_pose(i,pose)

func _chain(skel:Skeleton3D,a:String,b:String,c:String,target:Vector3,pole:Vector3) -> void:
	var ia:=skel.find_bone(a);var ib:=skel.find_bone(b);var ic:=skel.find_bone(c)
	var pa:=skel.get_bone_global_pose(ia);var pb:=skel.get_bone_global_pose(ib);var pc:=skel.get_bone_global_pose(ic)
	var upper:=pa.origin.distance_to(pb.origin);var lower:=pb.origin.distance_to(pc.origin)
	var v:=target-pa.origin
	if not v.is_finite() or v.length_squared()<.000001 or upper<.001 or lower<.001:return
	var distance:=clampf(v.length(),absf(upper-lower)+.001,upper+lower-.001);var axis:=v.normalized()
	var bend:Vector3=pole-axis*pole.dot(axis)
	if bend.length_squared()<.000001:bend=axis.cross(Vector3.RIGHT)
	if bend.length_squared()<.000001:bend=axis.cross(Vector3.UP)
	bend=bend.normalized()
	var along:float=(upper*upper-lower*lower+distance*distance)/(2*distance)
	var knee:Vector3=pa.origin+axis*along+bend*sqrt(maxf(upper*upper-along*along,0))
	pa.basis=Basis(Quaternion((pb.origin-pa.origin).normalized(),(knee-pa.origin).normalized()))*pa.basis;skel.set_bone_global_pose(ia,pa)
	pb=skel.get_bone_global_pose(ib);pc=skel.get_bone_global_pose(ic)
	var end=pa.origin+axis*distance
	if (end-pb.origin).length_squared()<.000001:return
	pb.basis=Basis(Quaternion((pc.origin-pb.origin).normalized(),(end-pb.origin).normalized()))*pb.basis;skel.set_bone_global_pose(ib,pb)

func _curl_pose(weight:float) -> void:
	var skel:=get_skeleton();var before:Array[Transform3D]=[]
	for i in skel.get_bone_count():before.append(skel.get_bone_pose(i))
	skel.reset_bone_poses()
	var hip_id:=skel.find_bone("Hip");var hip:=skel.get_bone_global_pose(hip_id);hip.origin.y=.35;skel.set_bone_global_pose(hip_id,hip)
	for pair in [["Waist",-.55],["Spine01",-.30],["Spine02",-.25],["NeckTwist01",-.20],["Head",.25]]:_bend(skel,pair[0],Vector3.BACK,pair[1])
	for side in ["L","R"]:
		var z:float=-1 if side=="L" else 1
		_chain(skel,side+"_Thigh",side+"_Calf",side+"_Foot",Vector3(.19,.38,z*.065),Vector3.UP)
		_chain(skel,side+"_Upperarm",side+"_Forearm",side+"_Hand",Vector3(.23,.43,z*.12),Vector3(0,-.2,z))
		_bend(skel,side+"_Foot",Vector3.BACK,-.7)
	for chain in actor.chibi_config.hair_chains:
		for bone in chain.bones.slice(1,3):_bend(skel,bone,Vector3.BACK,-.55)
	for i in range(1,9):
		_bend(skel,"Skirt_%02d_02"%i,Vector3.BACK,-.35)
	_bend(skel,"Tail_01",Vector3.BACK,-.6)
	for i in skel.get_bone_count():
		var tucked:=skel.get_bone_pose(i);var blended:Transform3D=before[i].interpolate_with(tucked,weight)
		skel.set_bone_pose_position(i,blended.origin);skel.set_bone_pose_rotation(i,blended.basis.get_rotation_quaternion());skel.set_bone_pose_scale(i,blended.basis.get_scale())

func _stun_pose() -> void:
	var skel:=get_skeleton();skel.reset_bone_poses()
	var t:float=actor.stun_time;var recover:float=smoothstep(actor.stun_duration,actor.stun_duration+.38,t)
	_bend(skel,"Waist",Vector3.BACK,.12*(1-recover)-.45*sin(recover*PI))
	_bend(skel,"Head",Vector3.RIGHT,.08*sin(t*5)*(1-recover))
	for side in ["L","R"]:
		var sign_z:float=-1 if side=="L" else 1
		_chain(skel,side+"_Upperarm",side+"_Forearm",side+"_Hand",Vector3(.09,.29,sign_z*lerpf(.27,.16,recover)),Vector3(0,0,sign_z))
		_chain(skel,side+"_Thigh",side+"_Calf",side+"_Foot",Vector3(.10,.09+recover*.06,sign_z*.065),Vector3(.9,.2,0))
	# Loose limbs settle after impact; the mesh remains the original animated doll.
	if t<.25:_ground_ball_pose(1-smoothstep(.045,.25,t))

func _ball_anticipation() -> void:
	# The original head-to-knee curl is visible before the blue shell appears.
	_ground_ball_pose(smoothstep(0,actor.BALL_CROUCH_TIME,actor.roll_time))

func _ground_ball_pose(weight:float) -> void:
	var skel:=get_skeleton();var before:Array[Transform3D]=[]
	for i in skel.get_bone_count():before.append(skel.get_bone_pose(i))
	skel.reset_bone_poses()
	var hip_id:=skel.find_bone("Hip");var hip:=skel.get_bone_global_pose(hip_id);hip.origin=Vector3(.02,.30,0);skel.set_bone_global_pose(hip_id,hip)
	# Bring the head down to the knees, then wrap the limbs and long hair around
	# the same centre. This is a separate compact pose from the unchanged air roll.
	for pair in [["Waist",-1.15],["Spine01",-.30],["Spine02",-.20],["NeckTwist01",.10],["Head",.25]]:_bend(skel,pair[0],Vector3.BACK,pair[1])
	for side in ["L","R"]:
		var z:float=-1 if side=="L" else 1
		_chain(skel,side+"_Thigh",side+"_Calf",side+"_Foot",Vector3(.17,.39,z*.060),Vector3(.3,1,0))
		_chain(skel,side+"_Upperarm",side+"_Forearm",side+"_Hand",Vector3(.20,.43,z*.125),Vector3(.3,-.8,z*.3))
		_bend(skel,side+"_Foot",Vector3.BACK,-.9)
	for chain in actor.chibi_config.hair_chains:
		var long_hair:bool=chain.kind=="hair"
		_bend(skel,chain.bones[0],Vector3.BACK,.25 if long_hair else .10)
		for bone in chain.bones.slice(1):_bend(skel,bone,Vector3.BACK,.45 if long_hair else .20)
	for i in range(1,9):_bend(skel,"Skirt_%02d_02"%i,Vector3.BACK,-.35)
	_bend(skel,"Tail_01",Vector3.RIGHT,.90);_bend(skel,"Tail_01",Vector3.BACK,-.60)
	for i in skel.get_bone_count():
		var pose:Transform3D=before[i].interpolate_with(skel.get_bone_pose(i),weight)
		skel.set_bone_pose_position(i,pose.origin);skel.set_bone_pose_rotation(i,pose.basis.get_rotation_quaternion());skel.set_bone_pose_scale(i,pose.basis.get_scale())

func _aim_direction(skel:Skeleton3D,bone:String,child:String,direction:Vector3) -> void:
	var i:=skel.find_bone(bone);var c:=skel.find_bone(child)
	var pose:=skel.get_bone_global_pose(i);var rest_direction:=skel.get_bone_global_pose(c).origin-pose.origin
	pose.basis=Basis(Quaternion(rest_direction.normalized(),direction.normalized()))*pose.basis
	skel.set_bone_global_pose(i,pose)
