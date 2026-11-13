extends RefCounted
static var paper_planes:Array[Plane]=[]

static func paper_contact(point:Vector3) -> Vector4:
	point/=0.80
	# Supporting planes of the actual folded-paper collision hull, including
	# the low keel. A flat wing-height box misses the forelock/keel contact.
	if paper_planes.is_empty():
		var vertices:PackedVector3Array=[]
		for v in [Vector3(.60,.03,0),Vector3(-.53,.03,-.54),Vector3(-.53,.03,.54),Vector3(-.43,-.10,0)]:
			vertices.append(v);vertices.append(v+Vector3.DOWN*.008)
		for i in vertices.size():
			for j in range(i+1,vertices.size()):
				for k in range(j+1,vertices.size()):
					var normal:Vector3=(vertices[j]-vertices[i]).cross(vertices[k]-vertices[i])
					if normal.length_squared()<.00000001:continue
					normal=normal.normalized();var distance:float=normal.dot(vertices[i]);var lo=0.0;var hi=0.0
					for v in vertices:
						var d:float=normal.dot(v)-distance;lo=minf(lo,d);hi=maxf(hi,d)
					if lo<-.00001 and hi>.00001:continue
					if hi>.00001:normal=-normal;distance=-distance
					var plane=Plane(normal,distance);var duplicate=false
					for prior in paper_planes:
						if prior.normal.dot(normal)>.9999 and absf(prior.d-distance)<.00001:duplicate=true;break
					if not duplicate:paper_planes.append(plane)
	var result=Vector4(0,1,0,-INF)
	for plane in paper_planes:
		var d=plane.distance_to(point)
		if d>result.w:result=Vector4(plane.normal.x,plane.normal.y,plane.normal.z,d)
	result.w*=0.80
	return result
