extends RefCounted
# A single continuous surface replaces the two coplanar slabs at the doorway.
# Keep the footprint, top height, material maps and texture density unchanged.
static func build(parent:Node3D,material:Material) -> MeshInstance3D:
	var outline=PackedVector2Array([
		Vector2(-.575,0),Vector2(.575,0),Vector2(.575,3.22),
		Vector2(.69,3.22),Vector2(.69,4.66),Vector2(-1.09,4.66),
		Vector2(-1.09,3.22),Vector2(-.575,3.22)])
	var indices=Geometry2D.triangulate_polygon(outline)
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for top in [true,false]:
		var y=-.006 if top else -.096
		var normal=Vector3.UP if top else Vector3.DOWN
		for i in range(0,indices.size(),3):
			var tri=[outline[indices[i]],outline[indices[i+1]],outline[indices[i+2]]]
			# Godot's front face is clockwise. With x/z coordinates the original
			# counter-clockwise polygon already faces up on the top surface.
			if not top:tri.reverse()
			for p in tri:
				st.set_normal(normal);st.set_uv(Vector2(p.x+.575,3.34-p.y)*2.0)
				st.add_vertex(Vector3(p.x,y,p.y))
	for i in outline.size():
		var a=outline[i];var b=outline[(i+1)%outline.size()]
		var normal=Vector3(b.y-a.y,0,a.x-b.x).normalized()
		var points=[Vector3(a.x,-.006,a.y),Vector3(a.x,-.096,a.y),Vector3(b.x,-.096,b.y),Vector3(b.x,-.006,b.y)]
		for index in [0,1,2,0,2,3]:
			var v=points[index]
			st.set_normal(normal);st.set_uv(Vector2(Vector2(v.x,v.z).distance_to(a),v.y+.096)*2.0);st.add_vertex(v)
	st.index();st.generate_tangents()
	var mi=MeshInstance3D.new();mi.name="Continuous puzzle floor";mi.mesh=st.commit()
	mi.material_override=material;mi.layers=4;mi.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	mi.set_meta("authored_detail_label","Continuous puzzle floor");parent.add_child(mi)
	return mi
