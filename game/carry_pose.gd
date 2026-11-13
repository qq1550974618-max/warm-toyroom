extends SkeletonModifier3D

var actor:CharacterBody3D
var interaction:Node
var samples:=0
var maximum_hand_motion:=0.0
var maximum_crouch_foot_error:=0.0
var last_grip_errors:Array=[]
var head_surface:=PackedVector3Array()
var crown_surface:=PackedVector3Array()
var head_tilt:=0.0
var maximum_head_tilt:=0.0
var head_clearance_before:=1.0
var head_clearance_after:=1.0
var maximum_arm_length_ratio:=1.0
const HEAD_MARGIN:=.012
const MAX_HEAD_TILT:=.72

func reset_transient_pose() -> void:
	if interaction!=null and not is_instance_valid(interaction.held):head_tilt=0.0

func _ready() -> void:
	var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/carry_head_surface.json"))
	for point in profile.head_local_points:head_surface.append(Vector3(point[0],point[1],point[2]))
	var crown:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/carry_crown_surface.json"))
	for point in crown.head_local_points:crown_surface.append(Vector3(point[0],point[1],point[2]))

func _process_modification_with_delta(delta:float) -> void:
	if interaction==null:return
	if interaction.arm_weight>.001:_apply_carry_pose()
	_update_head_clearance(delta)

func _apply_carry_pose() -> void:
	var skel:=get_skeleton();var before:Array[Transform3D]=[]
	var crouch_feet:Array[Vector3]=[]
	for i in skel.get_bone_count():before.append(skel.get_bone_pose(i))
	if interaction.phase in ["reach","lift"]:
		# Crouch to the floor while restoring both foot targets in skeleton space.
		for leg in actor.locomotion.legs:crouch_feet.append(skel.get_bone_global_pose(leg.foot).origin)
		var hip_id:=skel.find_bone("Hip");var hip:=skel.get_bone_global_pose(hip_id)
		hip.origin+=Vector3(.04,-.11,0)*clampf(interaction.body_bend/.25,0,1);skel.set_bone_global_pose(hip_id,hip)
		for i in actor.locomotion.legs.size():actor.locomotion._solve_leg(skel,actor.locomotion.legs[i],crouch_feet[i])
	actor.locomotion._bend(skel,"Spine01",Vector3.BACK,-interaction.body_bend)
	var heading:=Basis(Vector3.UP,actor.visual.rotation.y)
	var kind=interaction.held.get_meta("kind","") if is_instance_valid(interaction.held) else ""
	for side in ["L","R"]:
		var sign_z:float=-1 if side=="L" else 1
		if kind in ["plane","marble"]:
			# A small shoulder shrug accompanies the arm lift.
			var clavicle=skel.find_bone(side+"_Clavicle");var clav=skel.get_bone_global_pose(clavicle)
			clav.origin+=Vector3(.025,.065,sign_z*.02) if kind=="plane" else Vector3(.024,.035,0)
			skel.set_bone_global_pose(clavicle,clav)
		var offset:Vector3=interaction.grip_local;offset.z*=sign_z
		var target:Vector3=skel.global_transform.affine_inverse()*(interaction.arm_target+heading*offset)
		var hand:=skel.find_bone(side+"_Hand");var from:Vector3=skel.get_bone_global_pose(hand).origin
		if kind=="plane":
			# The short original arms lift naturally in front of the temples.
			# The paper comes to the raised pose; never elongate arms to reach it.
			var shoulder=skel.get_bone_global_pose(skel.find_bone(side+"_Upperarm")).origin
			var elbow=skel.get_bone_global_pose(skel.find_bone(side+"_Forearm")).origin
			var wrist=skel.get_bone_global_pose(hand).origin
			var reach=shoulder.distance_to(elbow)+elbow.distance_to(wrist)
			var raised=shoulder+Vector3(.74,.65,sign_z*.18).normalized()*reach*.97
			target=raised
		elif kind=="marble":_fit_reach(skel,side,target,1.12)
		_solve_arm(skel,side,target,Vector3(-.25,.1,sign_z*2) if kind=="plane" else Vector3(-.1,-.5,sign_z))
		maximum_hand_motion=maxf(maximum_hand_motion,from.distance_to(skel.get_bone_global_pose(hand).origin)*actor.visual_scale)
	for i in skel.get_bone_count():
		var pose:Transform3D=before[i].interpolate_with(skel.get_bone_pose(i),interaction.arm_weight)
		skel.set_bone_pose_position(i,pose.origin);skel.set_bone_pose_rotation(i,pose.basis.get_rotation_quaternion());skel.set_bone_pose_scale(i,pose.basis.get_scale())
	for i in crouch_feet.size():
		var leg:Dictionary=actor.locomotion.legs[i];actor.locomotion._solve_leg(skel,leg,crouch_feet[i])
		maximum_crouch_foot_error=maxf(maximum_crouch_foot_error,skel.get_bone_global_pose(leg.foot).origin.distance_to(crouch_feet[i])*actor.visual_scale)
	# SkeletonModifier poses are restored after skinning. Measure contact here,
	# while these are the actual poses sent to the rendered skinned mesh.
	last_grip_errors.clear()
	for side in ["L","R"]:
		var offset:Vector3=interaction.grip_local;offset.z*=(-1 if side=="L" else 1)
		var actual:Vector3=skel.global_transform*skel.get_bone_global_pose(skel.find_bone(side+"_Hand")).origin
		last_grip_errors.append(actual.distance_to(interaction.arm_target+heading*offset))
		if kind=="plane":
			var shoulder=skel.get_bone_global_pose(skel.find_bone(side+"_Upperarm")).origin
			var elbow=skel.get_bone_global_pose(skel.find_bone(side+"_Forearm")).origin
			var wrist=skel.get_bone_global_pose(skel.find_bone(side+"_Hand")).origin
			var original_upper:float=before[skel.find_bone(side+"_Forearm")].origin.length()
			var original_lower:float=before[skel.find_bone(side+"_Hand")].origin.length()
			maximum_arm_length_ratio=maxf(maximum_arm_length_ratio,(shoulder.distance_to(elbow)+elbow.distance_to(wrist))/maxf(.001,original_upper+original_lower))
	samples+=1

func _update_head_clearance(delta:float) -> void:
	var skel:=get_skeleton();var neck_id:=skel.find_bone("NeckTwist01");var head_id:=skel.find_bone("Head")
	var head:=skel.get_bone_global_pose(head_id);var neck:=skel.get_bone_global_pose(neck_id)
	var needed:=0.0;var anticipated:=0.0
	if is_instance_valid(interaction.held) and interaction.phase in ["reach","lift","hold","throw"]:
		var prop:Transform3D=interaction.held.global_transform
		head_clearance_before=_clearance(skel,head,prop)
		needed=_required_tilt(skel,head,neck.origin,prop)
		# Begin leaning before the lift reaches the face, rather than reacting after contact.
		if interaction.phase in ["reach","lift"]:
			var frame:=Basis(Vector3.UP,actor.visual.rotation.y)
			var goal:=Transform3D(frame*interaction.held_basis,actor.global_position+frame*interaction.carry_offset)
			var ahead:float=maxf(0,interaction.phase_time-.25) if interaction.phase=="reach" else interaction.phase_time+.12
			prop=interaction.lift_start.interpolate_with(goal,smoothstep(0,.38,ahead))
			if interaction.held.get_meta("kind","")=="plane":
				prop=preload("res://plane_lift.gd").sample(interaction.lift_start,goal,actor.global_position,frame,clampf(ahead/.78,0,1)).transform
			anticipated=_required_tilt(skel,head,neck.origin,prop)
	var target:=maxf(needed,anticipated)
	if is_instance_valid(interaction.held) and interaction.held.get_meta("kind","")=="marble":
		target=maxf(target,.20*interaction.arm_weight)
	head_tilt=maxf(needed,move_toward(head_tilt,target,delta*(4.8 if target>head_tilt else 1.8)))
	if actor.state in ["roll","dash","stunned","flattened","dead","victory"]:head_tilt=0
	if head_tilt>.0001:
		# +Z rotation lifts the chin of this +X-facing rig; neck and head share the bend.
		neck.origin+=Vector3(-.045,0,0)*(head_tilt/MAX_HEAD_TILT);skel.set_bone_global_pose(neck_id,neck)
		actor.locomotion._bend(skel,"NeckTwist01",Vector3.BACK,head_tilt*.35)
		actor.locomotion._bend(skel,"Head",Vector3.BACK,head_tilt*.65)
	maximum_head_tilt=maxf(maximum_head_tilt,head_tilt)
	head_clearance_after=_clearance(skel,skel.get_bone_global_pose(head_id),interaction.held.global_transform) if is_instance_valid(interaction.held) else 1.0

func _tilted_head(head:Transform3D,neck:Vector3,angle:float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK,angle)*head.basis,neck+Basis(Vector3.BACK,angle*.35)*(head.origin-neck)+Vector3(-.045,0,0)*(angle/MAX_HEAD_TILT))

func _required_tilt(skel:Skeleton3D,head:Transform3D,neck:Vector3,prop:Transform3D) -> float:
	if _clearance(skel,head,prop)>=HEAD_MARGIN:return 0
	var low:=0.0;var high:=MAX_HEAD_TILT
	for i in 6:
		var angle:float=(low+high)*.5
		if _clearance(skel,_tilted_head(head,neck,angle),prop)<HEAD_MARGIN:low=angle
		else:high=angle
	return high

func _clearance(skel:Skeleton3D,head:Transform3D,prop:Transform3D) -> float:
	var head_to_prop:=prop.affine_inverse()*skel.global_transform*head
	var minimum:=INF;var kind:String=interaction.held.get_meta("kind")
	var pencil:Dictionary=interaction.held.get_meta("carry_capsule",{})
	var surface_points:PackedVector3Array=crown_surface if kind=="plane" else head_surface
	for vertex in surface_points:
		var point:=head_to_prop*vertex;var distance:float
		if kind=="marble":distance=point.length()-.098
		elif kind=="plane":
			distance=preload("res://carry_geometry.gd").paper_contact(point).w
		elif kind=="chicken":
			var d=point.abs()-Vector3(.117,.195,.147)
			distance=d.max(Vector3.ZERO).length()+minf(maxf(d.x,maxf(d.y,d.z)),0.0)
		elif kind=="reel":
			# Actual spool profile: narrow yarn and two wide wooden rims.
			distance=minf(_cylinder_distance(point,.13,.125),minf(_cylinder_distance(point-Vector3.UP*.145,.19,.015),_cylinder_distance(point+Vector3.UP*.145,.19,.015)))
		else:
			distance=absf(point.y)-float(pencil.half_height)
			for plane in pencil.planes:distance=maxf(distance,point.x*plane.x+point.z*plane.y-plane.z)
		minimum=minf(minimum,distance)
	return minimum

func _cylinder_distance(point:Vector3,radius:float,half_height:float) -> float:
	var d:=Vector2(Vector2(point.x,point.z).length()-radius,absf(point.y)-half_height)
	return Vector2(maxf(d.x,0),maxf(d.y,0)).length()+minf(maxf(d.x,d.y),0)

func _solve_arm(skel:Skeleton3D,side:String,target:Vector3,pole:Vector3) -> void:
	var ia:=skel.find_bone(side+"_Upperarm");var ib:=skel.find_bone(side+"_Forearm");var ic:=skel.find_bone(side+"_Hand")
	var a:=skel.get_bone_global_pose(ia);var b:=skel.get_bone_global_pose(ib);var c:=skel.get_bone_global_pose(ic)
	var upper:=a.origin.distance_to(b.origin);var lower:=b.origin.distance_to(c.origin)
	var offset:=target-a.origin
	if not offset.is_finite() or offset.length_squared()<.000001 or upper<.001 or lower<.001:return
	var axis:=offset.normalized();var distance:=clampf(offset.length(),absf(upper-lower)+.001,upper+lower-.001)
	var bend:=pole-axis*pole.dot(axis)
	if bend.length_squared()<.000001:bend=axis.cross(Vector3.RIGHT)
	if bend.length_squared()<.000001:bend=axis.cross(Vector3.UP)
	bend=bend.normalized()
	var along:float=(upper*upper-lower*lower+distance*distance)/(2*distance)
	var elbow:=a.origin+axis*along+bend*sqrt(maxf(upper*upper-along*along,0))
	a.basis=Basis(Quaternion((b.origin-a.origin).normalized(),(elbow-a.origin).normalized()))*a.basis;skel.set_bone_global_pose(ia,a)
	b=skel.get_bone_global_pose(ib);c=skel.get_bone_global_pose(ic)
	var end:Vector3=a.origin+axis*distance
	if (end-b.origin).length_squared()<.000001:return
	b.basis=Basis(Quaternion((c.origin-b.origin).normalized(),(end-b.origin).normalized()))*b.basis;skel.set_bone_global_pose(ib,b)

func _fit_reach(skel:Skeleton3D,side:String,target:Vector3,maximum:float) -> void:
	var ia=skel.find_bone(side+"_Upperarm");var ib=skel.find_bone(side+"_Forearm");var ic=skel.find_bone(side+"_Hand")
	var a=skel.get_bone_global_pose(ia);var b=skel.get_bone_global_pose(ib);var c=skel.get_bone_global_pose(ic)
	var upper=b.origin-a.origin;var lower=c.origin-b.origin
	var factor=clampf(target.distance_to(a.origin)*1.08/maxf(.001,upper.length()+lower.length()),1,maximum)
	# A small reach allowance for low-held props; overhead arms never use this.
	b.origin=a.origin+upper*factor;c.origin=b.origin+lower*factor
	skel.set_bone_global_pose(ib,b);skel.set_bone_global_pose(ic,c)
