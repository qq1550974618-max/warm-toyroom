extends RefCounted
var shader=preload("res://toy_finish.gdshader")
var double_shader:Shader
var character_categories:Dictionary={}
var shared_room_materials:Dictionary={}
func _init() -> void:
	double_shader=Shader.new();double_shader.code=shader.code.replace("specular_schlick_ggx;","specular_schlick_ggx, cull_disabled;")
func finish(m:BaseMaterial3D,rough:float,span:float,spec:float,normal:float,metal:float=0,coat:float=0,fiber:float=0,gilt:float=0,grain:float=0) -> ShaderMaterial:
	var s:=ShaderMaterial.new();s.shader=double_shader if fiber>0 else shader;s.resource_name=m.resource_name
	s.set_shader_parameter("tint",m.albedo_color);s.set_shader_parameter("has_base",m.albedo_texture!=null)
	if m.albedo_texture!=null:s.set_shader_parameter("base_map",m.albedo_texture)
	s.set_shader_parameter("has_bump",m.normal_texture!=null)
	if m.normal_texture!=null:s.set_shader_parameter("bump_map",m.normal_texture)
	s.set_shader_parameter("has_rough",m.roughness_texture!=null)
	if m.roughness_texture!=null:s.set_shader_parameter("rough_map",m.roughness_texture)
	s.set_shader_parameter("roughness_min",rough);s.set_shader_parameter("roughness_span",span);s.set_shader_parameter("specular_amount",spec)
	s.set_shader_parameter("normal_strength",normal);s.set_shader_parameter("metallic_amount",metal);s.set_shader_parameter("coat_amount",coat)
	s.set_shader_parameter("fiber_amount",fiber);s.set_shader_parameter("gilt_amount",gilt);s.set_shader_parameter("grain_amount",grain)
	return s
func room_material(source:BaseMaterial3D) -> Material:
	# Static furnishings and movable props share the same authored finish library.
	if shared_room_materials.is_empty():
		for file in ResourceLoader.list_directory("res://room_kit/materials/"):
			if file.ends_with(".tres"):
				var material=ResourceLoader.load("res://room_kit/materials/"+file)
				if material is BaseMaterial3D:shared_room_materials[material.resource_name]=material
		print("V11_SHARED_MATERIALS count=",shared_room_materials.size())
	if shared_room_materials.has(source.resource_name):return shared_room_materials[source.resource_name]
	var m:BaseMaterial3D=source.duplicate();var n:=m.resource_name.to_lower()
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.diffuse_mode=BaseMaterial3D.DIFFUSE_BURLEY;m.cull_mode=BaseMaterial3D.CULL_BACK
	if "window sky" in n:return m
	m.metallic=0;m.metallic_texture=null;m.normal_enabled=m.normal_texture!=null
	if "oak" in n:
		m.roughness=.56;m.roughness_texture=null;m.metallic_specular=.32;m.normal_scale=.18;m.albedo_color=Color(.96,.96,.96)
	elif "walnut" in n:
		m.roughness=.62;m.roughness_texture=null;m.metallic_specular=.32;m.normal_scale=.20;m.albedo_color=Color(.96,.96,.96)
	elif "plaster" in n:
		m.roughness=.97;m.metallic_specular=.12;m.normal_scale=.13;m.albedo_color=Color(.94,.97,1.0)
	elif "sage" in n:
		m.roughness=.58;m.metallic_specular=.32;m.normal_scale=.13
	elif "lacquer" in n or "toy paint" in n or "painted wood" in n:
		m.roughness=.34;m.metallic_specular=.43;m.normal_scale=.08;m.clearcoat_enabled=true;m.clearcoat=.10;m.clearcoat_roughness=.32
	elif "brass" in n or "gold" in n:
		m.metallic=.72;m.roughness=.36;m.metallic_specular=.5;m.normal_scale=.10
	elif "iron" in n:
		m.metallic=.50;m.roughness=.44;m.metallic_specular=.42
	elif "paper" in n or "page" in n:
		m.roughness=.92;m.metallic_specular=.14;m.normal_scale=.12;m.cull_mode=BaseMaterial3D.CULL_DISABLED
	elif "cotton" in n or "cloth" in n or "wool" in n or "woven" in n or "linen" in n or "felt" in n or "thread" in n:
		m.roughness=.94;m.metallic_specular=.18;m.normal_scale=.30;m.cull_mode=BaseMaterial3D.CULL_DISABLED
	elif "wicker" in n:
		m.roughness=.55;m.metallic_specular=.35;m.normal_scale=.08
	return m
func character(actor:CharacterBody3D) -> void:
	for row in actor.material_rows:
		var m:BaseMaterial3D=row.pbr;m.roughness_texture=null;m.metallic_texture=null;m.albedo_color=row.base_pbr_color
		var part:=int(str(row.mesh.name).split("_")[1]) if str(row.mesh.name).begins_with("QPart_") else -1
		var s:Material;var category:String
		if row.hair or part==58:
			category="painted_resin_hair";s=finish(m,.57,.08,.28,.035,0,0)
		elif part==56 or part in [37,39,32,33]:
			category="soft_vinyl_skin";s=finish(m,.65,.07,.24,.025)
		elif part in [51,52]:
			category="eye_glaze";s=finish(m,.25,.06,.48,.01,0,.20)
		elif part in [20,30,36,38]:
			category="satin_painted_shoes";s=finish(m,.38,.10,.38,.06,0,.12,0,.55)
		else:
			category="woven_costume_and_gilt";s=finish(m,.83,.09,.18,.10,0,0,.023,.62)
		s.shader=double_shader
		row.mesh.set_surface_override_material(row.surface,s);row.mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;row.mesh.layers=2
		character_categories[category]=int(character_categories.get(category,0))+1
