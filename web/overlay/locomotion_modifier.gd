extends SkeletonModifier3D

# Runs after the animation mixer, before secondary hair motion.
# The anchors live in world space; animation never moves the CharacterBody.
var actor: CharacterBody3D
var head_camera: Camera3D
var foot_lock_enabled := true
var legs: Array[Dictionary] = []
var lock_samples := 0
var maximum_anchor_error := 0.0
var plant_events := {"L": 0, "R": 0}
var last_facing := 1
var head_turn := 0.0
var locked_count := 0
var maximum_pelvis_adjustment := 0.0
var maximum_error_context := {}
var pelvis_drop_this_frame := 0.0
var reach_releases := 0
var previous_motion_state := ""
var idle_settle_remaining := 0.0
var running_reach_releases := 0
var running_pelvis_drop := 0.0
var inward_style_weight := 0.0
var inward_toe_degrees := 8.0
var maximum_step_pelvis_drop := 0.055
var previous_owner_position := Vector3.ZERO
var contact_frame_motion := Vector3.ZERO

func initialize(owner_actor: CharacterBody3D, view_camera: Camera3D) -> void:
	actor = owner_actor
	previous_owner_position = actor.global_position
	head_camera = view_camera
	var skel := get_skeleton()
	for side in ["L", "R"]:
		var foot := skel.find_bone(side + "_Foot")
		legs.append({"side": side, "hip": skel.find_bone(side + "_Thigh"),
			"knee": skel.find_bone(side + "_Calf"), "foot": foot,
			"rest_y": skel.get_bone_global_rest(foot).origin.y,
			"locked": false, "anchor": Vector3.ZERO, "weight": 0.0,
			"last_animated_y": 1.0})
	modification_processed.connect(_measure_final_anchors)

func release_feet() -> void:
	if actor != null: previous_owner_position = actor.global_position
	for leg in legs:
		leg.locked = false
		leg.weight = 0.0

func _process_modification_with_delta(delta: float) -> void:
	if actor == null or legs.is_empty(): return
	var owner_motion := actor.global_position - previous_owner_position
	previous_owner_position = actor.global_position
	contact_frame_motion = Vector3.ZERO
	# Planted anchors remain in world space, including at the new half scale.
	if actor.state != previous_motion_state:
		if actor.state == "idle":
			# Let the idle blend recover its authored stance before planting.
			# Otherwise a trailing running contact freezes the feet mid-stride.
			release_feet()
			idle_settle_remaining = 0.26
		previous_motion_state = actor.state
	idle_settle_remaining = maxf(0.0, idle_settle_remaining - delta)
	if actor.state=="dead":
		release_feet()
		return
	var skel := get_skeleton()
	inward_style_weight = move_toward(inward_style_weight, 1.0 if actor.state in ["idle", "run"] else 0.0, delta * 8.0)
	inward_toe_degrees = move_toward(inward_toe_degrees, 8.0 if actor.state == "idle" else 6.0, delta * 24.0)
	_apply_inward_pose(skel)
	if actor.facing != last_facing:
		release_feet()
		last_facing = actor.facing
	locked_count = 0
	pelvis_drop_this_frame = 0.0
	for leg in legs:
		leg["target"] = null
		var ankle_pose := skel.get_bone_global_pose(leg.foot)
		var animated_world := skel.global_transform * ankle_pose.origin
		var model_scale: float = float(actor.visual_scale) if "visual_scale" in actor else 1.0
		var relative_height: float = snappedf((animated_world.y - actor.global_position.y)/model_scale, 0.0001)
		var may_lock: bool = foot_lock_enabled and actor.is_on_floor() and actor.ground_motion and actor.turning_amount < 0.04 and idle_settle_remaining <= 0.0
		var rising: bool = relative_height > float(leg.last_animated_y) + 0.0005
		if leg.locked and (not may_lock or relative_height > float(leg.rest_y) + 0.024 or (rising and relative_height > float(leg.rest_y) + 0.017)):
			leg.locked = false
		if not leg.locked and may_lock and relative_height < float(leg.rest_y) + 0.013:
			var ground: Variant = _ground_at(animated_world)
			if ground != null:
				leg.anchor = Vector3(animated_world.x, float(ground) + float(leg.rest_y)*model_scale, animated_world.z)
				leg.locked = true
				plant_events[leg.side] += 1
		leg.weight = move_toward(float(leg.weight), 1.0 if leg.locked else 0.0, delta * 22.0)
		if leg.weight > 0.001:
			# Release overly distant contacts rather than stretching the leg.
			if animated_world.distance_to(leg.anchor) > 0.18*model_scale:
				leg.locked = false
				leg.weight = 0.0
			else:
				var target_world: Vector3 = animated_world.lerp(leg.anchor, leg.weight)
				var target := (skel.global_transform.affine_inverse() * target_world).snapped(Vector3.ONE * 0.0001)
				leg.target = target
		if leg.locked: locked_count += 1
		leg.last_animated_y = relative_height
	# Inspect both animated feet before moving the shared pelvis. Lowering it
	# inside the contact-detection loop falsely plants the other swinging foot.
	var required_drop := 0.0
	for leg in legs:
		if leg.target == null: continue
		var correction := _required_pelvis_drop(skel, leg, leg.target)
		if actor.state == "run" and correction > 0.025:
			# A departing running foot should release, rather than pull the body
			# downward by ten centimeters to keep a stale anchor reachable.
			leg.locked = false
			leg.weight = 0.0
			leg.target = null
			running_reach_releases += 1
			continue
		required_drop = maxf(required_drop, correction)
	if actor.state == "run":
		# Recover from a released contact continuously rather than snapping the
		# entire skeleton back upward on the next frame.
		# Reach must be satisfied immediately for a planted foot; only the
		# recovery upward is eased. Easing downward drops valid contacts.
		running_pelvis_drop = maxf(required_drop, move_toward(running_pelvis_drop, required_drop, delta * 0.18))
		required_drop = running_pelvis_drop
	else:
		running_pelvis_drop = move_toward(running_pelvis_drop, 0.0, delta * 0.18)
		required_drop = maxf(required_drop, running_pelvis_drop)
	_apply_pelvis_drop(skel, required_drop)
	locked_count = 0
	for leg in legs:
		if leg.target != null: _solve_leg(skel, leg, leg.target)
		if leg.locked: locked_count += 1
	_aim_head(skel, delta)

func _ground_at(point: Vector3) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.25, point - Vector3.UP * 0.22, 69)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() and hit.normal.y > 0.75 else null

func _inward_angle(side: String) -> float:
	return deg_to_rad(inward_toe_degrees) * inward_style_weight * (1.0 if side == "L" else -1.0)

func _apply_inward_pose(skel: Skeleton3D) -> void:
	if inward_style_weight <= 0.0001: return
	for leg in legs:
		var hip_pose := skel.get_bone_global_pose(leg.hip)
		var knee_pose := skel.get_bone_global_pose(leg.knee)
		var foot_pose := skel.get_bone_global_pose(leg.foot)
		# A tiny inward knee-plane turn complements the toe angle while keeping
		# ankle position, limb lengths, gait timing and world-space anchors intact.
		var axis := (foot_pose.origin - hip_pose.origin).normalized()
		var knee_angle := deg_to_rad(2.0) * inward_style_weight * (1.0 if leg.side == "L" else -1.0)
		var turn := Basis(axis, knee_angle)
		hip_pose.basis = turn * hip_pose.basis
		skel.set_bone_global_pose(leg.hip, hip_pose)
		var updated_knee := skel.get_bone_global_pose(leg.knee)
		updated_knee.basis = turn * knee_pose.basis
		skel.set_bone_global_pose(leg.knee, updated_knee)
		# Restore the exact original ankle location, then change only shoe yaw.
		var foot_rest := skel.get_bone_global_rest(leg.foot)
		var toe_rest := skel.get_bone_global_rest(skel.find_bone(str(leg.side) + "_ToeBase"))
		var toe_local := foot_rest.basis.inverse() * (toe_rest.origin - foot_rest.origin)
		var toe := foot_pose.basis * toe_local
		var current_angle := atan2(toe.z, toe.x)
		var desired_angle := deg_to_rad(inward_toe_degrees) * (1.0 if leg.side == "L" else -1.0)
		var correction := -wrapf(desired_angle - current_angle, -PI, PI) * inward_style_weight
		foot_pose.basis = Basis(Vector3.UP, correction) * foot_pose.basis
		skel.set_bone_global_pose(leg.foot, foot_pose)

func _required_pelvis_drop(skel: Skeleton3D, leg: Dictionary, target: Vector3) -> float:
	var start := skel.get_bone_global_pose(leg.hip).origin
	var knee := skel.get_bone_global_pose(leg.knee).origin
	var ankle := skel.get_bone_global_pose(leg.foot).origin
	var reach := start.distance_to(knee) + knee.distance_to(ankle) - 0.001
	var horizontal_sq := Vector2(start.x-target.x,start.z-target.z).length_squared()
	var max_vertical := sqrt(maxf(reach*reach-horizontal_sq,0.001))
	# One foot can remain on the lower tread while the controller has already
	# stepped upward. Share a bounded pelvis offset across both leg solves.
	return clampf(start.y-target.y-max_vertical,0.0,maximum_step_pelvis_drop)

func _apply_pelvis_drop(skel: Skeleton3D, correction: float) -> void:
	if correction > 0.0:
		var hip := skel.find_bone("Hip")
		var pose := skel.get_bone_global_pose(hip)
		pose.origin.y -= correction
		skel.set_bone_global_pose(hip,pose)
		pelvis_drop_this_frame += correction
		maximum_pelvis_adjustment = maxf(maximum_pelvis_adjustment,pelvis_drop_this_frame)

func _solve_leg(skel: Skeleton3D, leg: Dictionary, target: Vector3) -> void:
	var hip_pose := skel.get_bone_global_pose(leg.hip)
	var knee_pose := skel.get_bone_global_pose(leg.knee)
	var ankle_pose := skel.get_bone_global_pose(leg.foot)
	var start := hip_pose.origin
	var upper := start.distance_to(knee_pose.origin)
	var lower := knee_pose.origin.distance_to(ankle_pose.origin)
	if start.distance_to(target)>upper+lower-0.0001:
		# Release an unreachable contact, but still solve to the nearest reachable
		# position. Returning here exposed the unrelated source clip for one frame
		# at toe-off, making the foot jump forward and snap back on the next frame.
		leg.locked=false; leg.weight=0.0; reach_releases+=1
		target=start+(target-start).normalized()*(upper+lower-0.0001)
	var axis := (target - start).normalized()
	var distance := clampf(start.distance_to(target), absf(upper - lower) + 0.001, upper + lower - 0.0001)
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(upper * upper - along * along, 0.0))
	var bend := knee_pose.origin - start
	bend -= axis * bend.dot(axis)
	if bend.length_squared() < 0.000001: bend = Vector3.RIGHT - axis * Vector3.RIGHT.dot(axis)
	bend = bend.normalized()
	var knee_target := start + axis * along + bend * height
	var rotation := Quaternion((knee_pose.origin - start).normalized(), (knee_target - start).normalized())
	hip_pose.basis = Basis(rotation) * hip_pose.basis
	skel.set_bone_global_pose(leg.hip, hip_pose)
	knee_pose = skel.get_bone_global_pose(leg.knee)
	var updated_ankle := skel.get_bone_global_pose(leg.foot)
	rotation = Quaternion((updated_ankle.origin - knee_pose.origin).normalized(), (target - knee_pose.origin).normalized())
	knee_pose.basis = Basis(rotation) * knee_pose.basis
	skel.set_bone_global_pose(leg.knee, knee_pose)
	updated_ankle = skel.get_bone_global_pose(leg.foot)
	var rest_basis := skel.get_bone_global_rest(leg.foot).basis.orthonormalized()
	var toe:=skel.get_bone_global_rest(skel.find_bone(str(leg.side)+"_ToeBase")).origin-skel.get_bone_global_rest(leg.foot).origin
	rest_basis=Basis(Vector3.UP,atan2(toe.z,toe.x)-_inward_angle(str(leg.side)))*rest_basis
	updated_ankle.basis = updated_ankle.basis.orthonormalized().slerp(rest_basis, float(leg.weight) * 0.8)
	skel.set_bone_global_pose(leg.foot, updated_ankle)

func _aim_head(skel: Skeleton3D, delta: float) -> void:
	if "heading_yaw" in actor and actor.state=="idle": return
	# Idle and movement share the travel heading. The camera has no influence
	# on the eyes; also compensate for small yaw turns in the source clips.
	var head := skel.find_bone("Head")
	var rest := skel.get_bone_global_rest(head)
	var head_pose := skel.get_bone_global_pose(head)
	var forward := (skel.global_basis*head_pose.basis*rest.basis.inverse()*Vector3.RIGHT).normalized()
	var heading := atan2(-forward.z,forward.x)
	var travel_yaw: float = actor.heading_yaw if "heading_yaw" in actor else (0.0 if actor.facing>0 else -PI)
	var desired := clampf(wrapf(travel_yaw-heading,-PI,PI),-1.15,1.15)
	head_turn = lerpf(head_turn, desired, 1.0 - exp(-delta * 7.0))
	for item in [["NeckTwist01", 0.22], ["Head", 0.78]]:
		var index := skel.find_bone(item[0])
		if index < 0: continue
		var pose := skel.get_bone_global_pose(index)
		pose.basis = Basis(Vector3.UP, head_turn * float(item[1])) * pose.basis
		skel.set_bone_global_pose(index, pose)

func _measure_final_anchors() -> void:
	var skel := get_skeleton()
	for leg in legs:
		if leg.locked and leg.weight > 0.99:
			var final_world := skel.global_transform * skel.get_bone_global_pose(leg.foot).origin
			var error:=final_world.distance_to(leg.anchor)
			if error>maximum_anchor_error:
				var hip: Vector3=skel.get_bone_global_pose(leg.hip).origin
				var knee: Vector3=skel.get_bone_global_pose(leg.knee).origin
				var foot: Vector3=skel.get_bone_global_pose(leg.foot).origin
				var target: Vector3=skel.global_transform.affine_inverse()*Vector3(leg.anchor)
				maximum_error_context={"state":actor.state,"side":leg.side,"error":error,"actor":str(actor.position),"hip_to_target":hip.distance_to(target),"leg_reach":hip.distance_to(knee)+knee.distance_to(foot),"anchor":str(leg.anchor),"actual":str(final_world),"pelvis_lowering":maximum_pelvis_adjustment}
				maximum_anchor_error=error
			lock_samples += 1
