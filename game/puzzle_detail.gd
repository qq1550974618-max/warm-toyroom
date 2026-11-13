extends RefCounted
# One-time miniature joinery and hardware. Full-size maps and bevel geometry
# are retained; only static decorations sharing a material are batched.
static func apply(p:Node3D) -> void:
	var finish=p.house.finishes
	var walnut=finish.finish("walnut").duplicate()
	walnut.resource_name="V27 fine control walnut"
	walnut.uv1_scale=Vector3.ONE;walnut.albedo_color=Color(.92,.85,.74)
	walnut.normal_scale=.13;walnut.clearcoat_enabled=true;walnut.clearcoat=.10;walnut.clearcoat_roughness=.45
	var brass=finish.finish("alloy").duplicate()
	brass.resource_name="V27 satin brass hardware";brass.roughness=.68;brass.normal_scale=.055
	var dark=finish.finish("dark_metal")
	var cream=finish.finish("paint_cream")
	var meshes=p.find_children("*","MeshInstance3D",true,false)
	meshes.append_array(p.lift_control.find_children("*","MeshInstance3D",true,false))
	for node in meshes:
		var label=str(node.get_meta("authored_detail_label",node.name))
		if label in ["Paired pressure plaque","Remote control base","Switch tabletop","Switch pedestal foot","Switch upright"]:
			wood_uv(node);node.material_override=walnut
	# Lacquered crimson tops keep a subtle clear finish over the wood pores.
	p.red.normal_scale=.085;p.red.roughness=.65;p.red.clearcoat=.20;p.red.clearcoat_roughness=.34
	for cap in p.pressure_caps:
		for x in [-.113*p.BUTTON_SCALE,.113*p.BUTTON_SCALE]:
			fine_box(p,cap,"Fine cap side pinstripe",Vector3(x,.0165,0),Vector3(.002,.001,.202*p.BUTTON_SCALE),cream)
		for z in [-.101*p.BUTTON_SCALE,.101*p.BUTTON_SCALE]:
			fine_box(p,cap,"Fine cap end pinstripe",Vector3(0,.0165,z),Vector3(.226*p.BUTTON_SCALE,.001,.002),cream)
		finish.batch_details(cap)
	# Four proper slotted fasteners and inset edging on each walnut sign.
	for x in [.43,-.11]:
		for dx in [-.104,.104]:
			fine_box(p,p,"Fine plaque vertical inlay",Vector3(x+dx,.54,3.121+p.ROOM_SHIFT),Vector3(.002,.160,.0015),brass)
		for dy in [-.080,.080]:
			fine_box(p,p,"Fine plaque horizontal inlay",Vector3(x,.54+dy,3.121+p.ROOM_SHIFT),Vector3(.208,.002,.0015),brass)
		for dx in [-.104,.104]:
			for dy in [-.080,.080]:
				screw(p,p,Vector3(x+dx,.54+dy,3.119+p.ROOM_SHIFT),Vector3.FORWARD,.004,brass,dark)
	# Switch mounting plate and slotted screws follow the folding pedestal.
	var control=p.lift_control
	fine_box(p,control,"Fine lever travel slot",Vector3(0,.2625,.032),Vector3(.026,.0015,.066),dark)
	for x in [-.10,.10]:
		for z in [-.06,.06]:screw(p,control,Vector3(x,.268,z),Vector3.UP,.005,brass,dark)
	for x in [-.070,.070]:
		var ring=TorusMesh.new();ring.inner_radius=.020;ring.outer_radius=.0245;ring.rings=32;ring.ring_segments=8
		var mi=MeshInstance3D.new();mi.name="Fine recessed lamp bezel";mi.mesh=ring;mi.material_override=brass;mi.position=Vector3(x,.270,-.036);mi.layers=4;mi.set_meta("mini_static_detail",true);control.add_child(mi)
	# Brass ferrule below the cream lever knob, no added collision edges.
	var ferrule=p.cylinder_between(p.lift_lever,Vector3(0,.053,0),Vector3(0,.064,0),.011,brass)
	ferrule.set_meta("mini_static_detail",true)
	finish.batch_details(control);finish.batch_details(p.lift_lever)
	p.set_meta("v27_control_detail",{"full_resolution_maps":true,"batched_static_trim":true,"red_caps":2,"equation":"fish+fish=star"})

static func fine_box(p:Node3D,parent:Node3D,label:String,point:Vector3,size:Vector3,mat:Material) -> MeshInstance3D:
	var mi=p.box(label,point,size,mat,false)
	if mi.get_parent()!=parent:mi.reparent(parent,false)
	mi.set_meta("mini_static_detail",true);return mi

static func screw(p:Node3D,parent:Node3D,point:Vector3,normal:Vector3,radius:float,brass:Material,dark:Material) -> void:
	var head=p.cylinder_between(parent,point-normal*.001,point+normal*.0005,radius,brass);head.set_meta("mini_static_detail",true)
	var size=Vector3(radius*1.35,.0008,radius*.22) if normal==Vector3.UP else Vector3(radius*1.35,radius*.22,.0008)
	fine_box(p,parent,"Fine screw driver slot",point+normal*.0008,size,dark)

static func wood_uv(mi:MeshInstance3D) -> void:
	var a=mi.mesh.surface_get_arrays(0);var bounds=mi.mesh.get_aabb();var vertices=a[Mesh.ARRAY_VERTEX];var normals=a[Mesh.ARRAY_NORMAL];var uv=a[Mesh.ARRAY_TEX_UV]
	for i in vertices.size():
		var v=(vertices[i]-bounds.position)/bounds.size;var axis=normals[i].abs().max_axis_index()
		uv[i]=(Vector2(v.x,v.z) if axis==1 else (Vector2(v.x,v.y) if axis==2 else Vector2(v.z,v.y)))*Vector2(.80,.46)
	a[Mesh.ARRAY_TEX_UV]=uv
	var st=SurfaceTool.new();st.create_from_arrays(a);st.generate_tangents();mi.mesh=st.commit()
