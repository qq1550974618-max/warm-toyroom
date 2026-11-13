extends RefCounted
# Shared finishes for the new miniature set only. Texture resolution and the
# original scene's materials are never reduced. All geometry is built at load.
var cache:Dictionary={}
func finish(kind:String) -> StandardMaterial3D:
	if cache.has(kind):return cache[kind]
	var m=StandardMaterial3D.new()
	m.resource_name="Miniature finish / "+kind;m.set_meta("v26_finish",kind)
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.metallic_specular=.30
	match kind:
		"walnut","endgrain","floor":
			m.albedo_texture=load("res://assets/toy_room_v5_wood_table_worn_Diffuse.jpg")
			m.normal_enabled=true;m.normal_texture=load("res://assets/toy_room_v5_wood_table_worn_nor_gl.jpg");m.normal_scale=.16
			m.roughness_texture=load("res://room_kit/textures/v11/cabinet_wax_roughness.png");m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.albedo_color=Color(1.25,1.18,1.06);m.roughness=1.0;m.metallic_specular=.30
			m.uv1_scale=Vector3(.48,.22,1);m.clearcoat_enabled=false
			if kind=="floor":
				m.albedo_texture=load("res://assets/toy_room_v5_wood_floor_worn_Diffuse.jpg")
				m.normal_texture=load("res://assets/toy_room_v5_wood_floor_worn_nor_gl.jpg")
				m.roughness_texture=load("res://assets/toy_room_v5_wood_floor_worn_Rough.png")
				m.uv1_scale=Vector3.ONE;m.albedo_color=Color(.92,.87,.77);m.normal_scale=.13
			if kind=="endgrain":_maps(m,"v18","cut_endgrain",.18);m.uv1_scale=Vector3.ONE;m.albedo_color=Color(.73,.49,.27)
		"cotton","ivory","thread","felt":
			_maps(m,"v11","cotton_twill",.21)
			m.albedo_color=Color(.27,.43,.42) if kind in ["cotton","felt"] else Color(.91,.85,.72)
			m.uv1_scale=Vector3(4,4,4);m.roughness=1;m.metallic_specular=.13
			m.rim_enabled=true;m.rim=.035;m.rim_tint=.85
			if kind=="felt":m.uv1_scale=Vector3(6,6,6);m.normal_scale=.13
			if kind=="thread":_maps(m,"v16","cord_fibres",.22);m.uv1_scale=Vector3(3,1,1)
		"paint_teal","paint_rust","paint_cream","hazard_yellow":
			_maps(m,"v18","painted_wood",.12);m.uv1_scale=Vector3(2.4,2.4,2.4)
			m.albedo_color={"paint_teal":Color(.19,.33,.31),"paint_rust":Color(.44,.15,.075),"paint_cream":Color(.80,.72,.55),"hazard_yellow":Color(.98,.65,.065)}[kind]
			m.roughness=.70;m.clearcoat_enabled=true;m.clearcoat=.14;m.clearcoat_roughness=.4
		"alloy","dark_metal":
			_maps(m,"v18","worked_metal",.075);m.uv1_scale=Vector3(2,2,2)
			m.albedo_color=Color(.70,.53,.28) if kind=="alloy" else Color(.15,.17,.18)
			m.metallic=.83;m.roughness=.85;m.metallic_specular=.50;m.anisotropy_enabled=true;m.anisotropy=.18
		"rubber":
			_maps(m,"v16","rubber",.20);m.albedo_color=Color(.24,.39,.37);m.roughness=1;m.metallic_specular=.20;m.uv1_scale=Vector3(3,3,3)
		"porcelain":
			_maps(m,"v18","porcelain_glaze",.055);m.albedo_color=Color(.94,.90,.80);m.roughness=.78;m.metallic_specular=.43
			m.clearcoat_enabled=true;m.clearcoat=.24;m.clearcoat_roughness=.18
		"paper":
			_maps(m,"v18","cotton_paper",.14);m.albedo_color=Color(.94,.88,.73);m.metallic_specular=.13;m.uv1_scale=Vector3(3,3,3)
		"book_teal","book_rust":
			_maps(m,"v18","bookcloth",.22);m.albedo_color=Color(.21,.36,.35) if kind=="book_teal" else Color(.48,.16,.085)
			m.uv1_scale=Vector3(3,3,3);m.metallic_specular=.32;m.roughness=.80;m.clearcoat_enabled=true;m.clearcoat=.08;m.clearcoat_roughness=.48
		"cheese":
			_maps(m,"v18","porcelain_glaze",.03);m.albedo_color=Color(.96,.64,.18);m.roughness=.95;m.metallic_specular=.22
		"resin":
			_maps(m,"v18","porcelain_glaze",.025,false);m.albedo_color=Color(.014,.018,.021);m.roughness=.48;m.metallic_specular=.5;m.clearcoat_enabled=true;m.clearcoat=.32;m.clearcoat_roughness=.13
		"chalk":
			_maps(m,"v18","cotton_paper",.24);m.albedo_color=Color(.28,.47,.58);m.metallic_specular=.12
	cache[kind]=m
	return m
func _maps(m:StandardMaterial3D,version:String,family:String,bump:float,albedo:bool=true):
	var path="res://room_kit/textures/"+version+"/"+family
	if albedo:m.albedo_texture=load(path+"_albedo.png")
	m.normal_enabled=true;m.normal_texture=load(path+"_normal.png");m.normal_scale=bump
	m.roughness_texture=load(path+"_roughness.png");m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
func plank_uv(mesh:ArrayMesh,width:float,length:float) -> ArrayMesh:
	# Each miniature board uses one photographed board-width. Long grain follows
	# the actual geometry, rather than stamping many tiny floorboards onto it.
	var a=mesh.surface_get_arrays(0);var v=a[Mesh.ARRAY_VERTEX];var uv=a[Mesh.ARRAY_TEX_UV]
	for i in v.size():uv[i]=Vector2((v[i].z+length*.5)/length*.80,(v[i].x+width*.5)/width*.052+.004)
	a[Mesh.ARRAY_TEX_UV]=uv
	var st=SurfaceTool.new();st.create_from_arrays(a);st.generate_tangents();return st.commit()
func lathe(profile:Array[Vector2],segments:int=64) -> ArrayMesh:
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(profile.size()-1):
		var slope=(profile[j+1]-profile[j]).normalized()
		for i in segments:
			for c in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i+1,j+1),Vector2i(i,j),Vector2i(i+1,j+1),Vector2i(i,j+1)]:
				var a=TAU*c.x/segments;var p=profile[c.y]
				st.set_normal(Vector3(slope.y*cos(a),-slope.x,slope.y*sin(a)).normalized());st.set_uv(Vector2(c.x/float(segments),c.y/float(profile.size()-1)))
				st.add_vertex(Vector3(p.x*cos(a),p.y,p.x*sin(a)))
	st.index();st.generate_tangents();return st.commit()
func cushion(size:Vector3) -> ArrayMesh:
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 24:
		for i in 64:
			for c in [Vector2i(i,j),Vector2i(i,j+1),Vector2i(i+1,j+1),Vector2i(i,j),Vector2i(i+1,j+1),Vector2i(i+1,j)]:
				var a=TAU*c.x/64;var b=PI*c.y/24;var p=_cushion_point(a,b,size)
				var da=_cushion_point(a+.001,b,size)-_cushion_point(a-.001,b,size)
				var db=_cushion_point(a,clampf(b+.001,0,PI),size)-_cushion_point(a,clampf(b-.001,0,PI),size)
				var n=db.cross(da).normalized()
				if n.length_squared()<.1:n=Vector3.UP if b<PI*.5 else Vector3.DOWN
				st.set_normal(n);st.set_uv(Vector2(a/TAU,b/PI));st.add_vertex(p)
	st.index();st.generate_tangents();return st.commit()
func _cushion_point(a:float,b:float,size:Vector3) -> Vector3:
	var r=pow(maxf(0,sin(b)),.48)
	return Vector3(signf(cos(a))*pow(absf(cos(a)),.50)*size.x*.5*r,cos(b)*size.y*.5,signf(sin(a))*pow(absf(sin(a)),.50)*size.z*.5*r)
func batch_details(parent:Node3D) -> void:
	# Preserve every triangle and the full material maps; only consolidate static
	# repeated trim into a few draw submissions. Never touches interactive nodes.
	var groups={}
	for mi in parent.get_children():
		if not mi is MeshInstance3D or not mi.get_meta("mini_static_detail",false):continue
		var mat=mi.material_override
		if not groups.has(mat):groups[mat]=[]
		groups[mat].append(mi)
	for mat in groups:
		var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi in groups[mat]:
			for si in mi.mesh.get_surface_count():st.append_from(mi.mesh,si,mi.transform)
			parent.remove_child(mi);mi.queue_free()
		st.index();var merged=MeshInstance3D.new();merged.name="Fine trim / "+mat.get_meta("v26_finish","woven");merged.mesh=st.commit();merged.material_override=mat;merged.layers=4;merged.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;parent.add_child(merged)
