extends RefCounted

static func sample(start:Transform3D,goal:Transform3D,feet:Vector3,frame:Basis,time:float) -> Dictionary:
	# Take the rear edge, raise the paper in front of the face, then slide it
	# overhead. The supporting hands slide underneath instead of crossing the head.
	var outward=Transform3D(start.basis,feet+frame*Vector3(.56,start.origin.y-feet.y+.008,0))
	var cleared=Transform3D(start.basis,feet+frame*Vector3(.56,maxf(.18,outward.origin.y-feet.y),0))
	var raised=Transform3D(goal.basis,feet+frame*Vector3(.56,goal.origin.y-feet.y,0))
	var pose:Transform3D
	if time<.16:pose=start.interpolate_with(outward,smoothstep(0,.16,time))
	elif time<.38:pose=outward.interpolate_with(cleared,smoothstep(.16,.38,time))
	elif time<.76:pose=cleared.interpolate_with(raised,smoothstep(.38,.76,time))
	else:pose=raised.interpolate_with(goal,smoothstep(.76,1,time))
	var local=frame.inverse()*(pose.origin-feet)
	var grip=Vector3(-clampf(local.x-.14,0,.416),lerpf(.012,-.060,smoothstep(.10,.32,local.y)),.055)
	return {"transform":pose,"grip":grip}
