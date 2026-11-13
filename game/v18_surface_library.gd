extends RefCounted

const MAPS="res://room_kit/textures/v18/"
var cache:Dictionary={}
var stats:Dictionary={}

func _init() -> void:
	# The authored resources are the editable source of truth in normal play.
	# Regeneration is an explicit offline authoring action, never a frame-time job.
	if OS.get_cmdline_user_args().has("--v18-author-materials"):return
	var manifest_path="res://room_kit/materials/v18/manifest.json"
	if not FileAccess.file_exists(manifest_path):return
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:return
	for key in manifest:
		var material=load(str(manifest[key]))
		if material is StandardMaterial3D:cache[key]=material

func base(source:Material) -> StandardMaterial3D:
	var m:StandardMaterial3D
	if source is StandardMaterial3D:m=source.duplicate()
	else:
		m=StandardMaterial3D.new()
		if source is ShaderMaterial:
			var tint=source.get_shader_parameter("tint")
			if tint is Color:m.albedo_color=tint
			var texture=source.get_shader_parameter("base_map")
			if texture is Texture2D:m.albedo_texture=texture
	m.resource_name=source.resource_name
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func maps(m:StandardMaterial3D,family:String,bump:float,replace_albedo:bool=true) -> void:
	if replace_albedo:m.albedo_texture=load(MAPS+family+"_albedo.png")
	m.normal_enabled=true;m.normal_texture=load(MAPS+family+"_normal.png");m.normal_scale=bump
	m.roughness=1.0;m.roughness_texture=load(MAPS+family+"_roughness.png");m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.set_meta("v18_surface_family",family)

func refine(source:Material,context:String="") -> Material:
	if source==null:return null
	if source.has_meta("v26_finish"):return source
	var name=source.resource_name
	if name=="" and context.begins_with("iron_"):name=context
	if cache.has(name):return cache[name]
	var n=name.to_lower();var family="";var bump=.15
	if "wicker honey" in n:family="split_rattan";bump=.28
	elif "brass" in n or "bearingsteel" in n or "blackened iron" in n or n.begins_with("iron_") or "ferrule" in n:family="worked_metal";bump=.12
	elif "door sage" in n or "door warm ivory" in n or "v15_" in n and "paint" in n or "buttonred" in n:family="painted_wood";bump=.22
	elif "warm uncoated paper" in n:family="cotton_paper";bump=.20
	elif "desk woven cover" in n or "book cloth" in n:family="bookcloth";bump=.28
	elif "porcelain" in n or "cobaltglaze" in n:family="porcelain_glaze";bump=.08
	elif "basketball pebbled" in n:family="basketball_rubber";bump=.55
	elif "endgrain" in n:family="cut_endgrain";bump=.28
	elif "honeyoak" in n:family="finished_oak";bump=.25
	elif n=="walnut / open grain":family="finished_walnut";bump=.26
	elif "frame pale ash" in n:family="split_rattan";bump=.18
	if family=="":return source
	var m=base(source);m.resource_name="V18 "+name
	if family in ["finished_oak","finished_walnut"]:
		m.albedo_texture=load("res://room_kit/textures/v16/furniture_walnut_albedo.png")
		m.normal_enabled=true;m.normal_texture=load("res://room_kit/textures/v16/furniture_walnut_normal.png");m.normal_scale=bump
		m.roughness=1.0;m.roughness_texture=load("res://room_kit/textures/v16/furniture_walnut_roughness.png")
		m.albedo_color=Color(1.14,1.11,1.01);m.metallic_specular=.28;m.set_meta("v18_surface_family",family)
		m.uv1_scale=Vector3.ONE;m.uv1_triplanar=false;m.uv1_world_triplanar=false
		if family=="finished_walnut":
			# Retain the photographed pores and irregular growth rings; remapped
			# board UVs remove the previous stretched/blotchy appearance.
			m.albedo_texture=load("res://assets/toy_room_v5_wood_table_worn_Diffuse.jpg")
			m.normal_texture=load("res://assets/toy_room_v5_wood_table_worn_nor_gl.jpg")
			m.roughness_texture=load("res://room_kit/textures/v11/cabinet_wax_roughness.png")
			m.albedo_color=Color(1.25,1.16,1.02);m.normal_scale=.18;m.metallic_specular=.23
	else:maps(m,family,bump)
	if family=="worked_metal":
		m.metallic=.88;m.metallic_specular=.5
		m.anisotropy_enabled=true;m.anisotropy=.22
		m.clearcoat_enabled=false
		if "blackened" in n:m.roughness=.95;m.metallic=.65
		if n.begins_with("iron_"):m.uv1_scale=Vector3(2,2,2)
	elif family=="split_rattan":
		m.metallic=0;m.metallic_specular=.22;m.clearcoat_enabled=false
		m.uv1_scale=Vector3(1,1,1)
	elif family=="bookcloth":
		m.metallic=0;m.metallic_specular=.20;m.clearcoat_enabled=false
		m.uv1_scale=Vector3(1.6,1.6,1.6);m.normal_scale=.45;m.rim_enabled=true;m.rim=.035;m.rim_tint=.8
	elif family=="painted_wood":
		m.metallic=0;m.metallic_specular=.29;m.clearcoat_enabled=true;m.clearcoat=.07;m.clearcoat_roughness=.48
		m.uv1_scale=Vector3(2,2,2)
	elif family=="porcelain_glaze":
		m.metallic=0;m.metallic_specular=.40;m.clearcoat_enabled=true;m.clearcoat=.12;m.clearcoat_roughness=.22
		m.uv1_scale=Vector3(2,2,2)
	elif family=="cotton_paper":
		m.metallic=0;m.metallic_specular=.12;m.uv1_scale=Vector3(2,2,2)
	elif family=="basketball_rubber":m.metallic_specular=.23;m.uv1_scale=Vector3(1,1,1)
	cache[name]=m
	return m

func apply(game:Node) -> void:
	for mi in game.find_children("*","MeshInstance3D",true,false):
		if mi.get_meta("v12_pencil_style",false):continue
		if mi.mesh==null:continue
		var path=str(game.get_path_to(mi));var context=""
		if "IronBall" in path:
			context="iron_seam" if mi.mesh is TorusMesh else "iron_sphere"
		# Whole-mesh overrides outrank surface overrides. Replace at the active
		# layer, otherwise the assignment would be counted but never rendered.
		if mi.material_override!=null:
			var original=mi.material_override;var replacement=refine(original,context)
			if replacement!=null and replacement!=original:
				mi.material_override=replacement
				var family=str(replacement.get_meta("v18_surface_family",""));stats[family]=int(stats.get(family,0))+1
			continue
		for i in mi.mesh.get_surface_count():
			var old=mi.get_active_material(i);var next=refine(old,context)
			if next!=null and next!=old:
				mi.set_surface_override_material(i,next)
				var family=str(next.get_meta("v18_surface_family",""));stats[family]=int(stats.get(family,0))+1
	game.set_meta("v18_surface_stats",stats)
	print("V18_SURFACE_LIBRARY ",JSON.stringify(stats)," shared_materials=",cache.size())
	if OS.get_cmdline_user_args().has("--v18-author-materials"):
		DirAccess.make_dir_recursive_absolute("res://room_kit/materials/v18")
		var manifest={}
		for key in cache:
			var file="res://room_kit/materials/v18/"+str(key).validate_filename().replace(" ","_")+".tres"
			ResourceSaver.save(cache[key],file);manifest[key]=file
		FileAccess.open("res://room_kit/materials/v18/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t"))
