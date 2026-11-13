extends RefCounted
# Binary Variant snapshots preserve Basis columns and avoid text-conversion transposition.
const NAMES=["当前版本灯光与烘焙","V8 灯位与烘焙","V12 灯位与烘焙"]
const VERSIONS=["","v8","v12"]
const IDS=["current","v8","v12"]
const ROOT="res://room_kit/legacy_v22/"
var PROFILES:Array=[{}]
var room:Node3D
var baseline_environment:Dictionary={}
var baseline_camera_attributes:Dictionary={}
var baseline_lights:Dictionary={}
var baseline_probe:Dictionary={}
var baseline_lightmap:Dictionary={}
var baseline_gi:LightmapGIData
var baseline_modes:Dictionary={}
var gi_cache:Dictionary={}
var binding_report:Dictionary={}
var active_gi_profile:=-1
var compatibility:Dictionary={}
var effective_quality:Dictionary={}
var baseline_render_settings:Dictionary={}
var alternate_lamps:Dictionary={}

func stored(object:Object) -> Dictionary:
	var result={}
	for p in object.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE):continue
		if str(p.name) in ["script","owner","name","resource_name","resource_path","resource_local_to_scene","process_mode","process_priority","process_physics_priority","physics_interpolation_mode","resource_scene_unique_id"]:continue
		var value=object.get(p.name)
		if typeof(value) in [TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_VECTOR2,TYPE_VECTOR3,TYPE_COLOR,TYPE_TRANSFORM3D]:result[p.name]=value
	return result

func bind(owner_room:Node3D) -> void:
	room=owner_room
	for p in ProjectSettings.get_property_list():
		if str(p.name).begins_with("rendering/"):baseline_render_settings[p.name]=ProjectSettings.get_setting(p.name)
	for version in VERSIONS.slice(1):
		var file=FileAccess.open(ROOT+"lighting_"+version+".bin",FileAccess.READ)
		assert(file!=null,"Missing original lighting snapshot: "+version)
		PROFILES.append(file.get_var())
	if FileAccess.file_exists(ROOT+"compatible_bindings.bin"):
		compatibility=FileAccess.open(ROOT+"compatible_bindings.bin",FileAccess.READ).get_var()
	baseline_environment=stored(room.environment)
	baseline_camera_attributes=stored(room.attributes)
	baseline_probe=stored(room.get_node("RoomReflections"))
	baseline_lightmap=stored(room.lightmap)
	for lamp in room.get_children():
		if lamp is Light3D:baseline_lights[str(lamp.name)]=stored(lamp)
	var rig=Node3D.new();rig.name="OriginalLightTypes";room.add_child(rig)
	for profile in PROFILES.slice(1):
		for key in profile.lights:
			var original=room.get_node_or_null(key);var kind:String=profile.lights[key]["class"]
			if original==null or original.get_class()==kind:continue
			var id=key+"_"+kind
			if alternate_lamps.has(id):continue
			var lamp:Light3D=ClassDB.instantiate(kind);lamp.name=id;rig.add_child(lamp);lamp.hide();alternate_lamps[id]=lamp

func assign(object:Object,properties:Dictionary) -> void:
	if properties.has("fog_mode") and object.get("fog_mode")!=properties.fog_mode:object.set("fog_mode",properties.fog_mode)
	for key in properties:
		if object.get(key)!=properties[key]:object.set(key,properties[key])

func restore() -> void:
	for lamp in alternate_lamps.values():lamp.hide()
	apply_shared_sampling(baseline_render_settings)
	assign(room.environment,baseline_environment)
	assign_camera_values(baseline_camera_attributes)
	assign(room.get_node("RoomReflections"),baseline_probe)
	assign(room.lightmap,baseline_lightmap)
	for key in baseline_lights:assign(room.get_node(key),baseline_lights[key])

func original_lamp(key:String,entry:Dictionary) -> Light3D:
	var lamp=room.get_node_or_null(key) as Light3D
	if lamp==null:return null
	if lamp.get_class()!=entry["class"]:
		lamp.hide();return alternate_lamps[key+"_"+entry["class"]]
	return lamp

func assign_camera_values(properties:Dictionary) -> void:
	# A lighting comparison must not refocus the paused view to the old camera.
	var focus={}
	for key in ["dof_blur_far_enabled","dof_blur_near_enabled","dof_blur_far_distance","dof_blur_near_distance","dof_blur_far_transition","dof_blur_near_transition"]:focus[key]=room.attributes.get(key)
	assign(room.attributes,properties);assign(room.attributes,focus)

func apply_shared_sampling(s:Dictionary) -> void:
	room.get_viewport().use_debanding=s.get("rendering/anti_aliasing/quality/use_debanding",false)
	RenderingServer.sub_surface_scattering_set_quality(int(s.get("rendering/environment/subsurface_scattering/subsurface_scattering_quality",1)))
	RenderingServer.camera_attributes_set_dof_blur_quality(int(s.get("rendering/camera/depth_of_field/depth_of_field_bokeh_quality",2)),bool(s.get("rendering/camera/depth_of_field/depth_of_field_use_jitter",true)))
	for i in 4:room.get_viewport().set("positional_shadow_atlas_quad_%d"%i,int(s.get("rendering/lights_and_shadows/positional_shadow/atlas_quadrant_%d_subdiv"%i,2)))

func sync_baked_shadows() -> void:
	for key in baseline_lights:baseline_lights[key].shadow_enabled=room.get_node(key).shadow_enabled
	baseline_gi=room.lightmap.light_data
	if baseline_gi==null:return
	for mi in room.find_children("*","MeshInstance3D",true,false):baseline_modes[mi.get_instance_id()]=mi.gi_mode
	active_gi_profile=0;gi_cache[0]=baseline_gi

func apply_quality(profile:Dictionary) -> void:
	var s:Dictionary=profile.render_settings
	apply_shared_sampling(s)
	var v:String=profile.version
	var ao:int=int(s.get("rendering/environment/ssao/quality",2))
	var ao_half:bool=s.get("rendering/environment/ssao/half_size",true)
	var ao_target:float=s.get("rendering/environment/ssao/adaptive_target",.5)
	var il:int=int(s.get("rendering/environment/ssil/quality",2))
	var il_half:bool=s.get("rendering/environment/ssil/half_size",true)
	var il_target:float=s.get("rendering/environment/ssil/adaptive_target",.5)
	if v in ["v8","v12"]:ao=4;ao_half=false;ao_target=1.0;il=4;il_half=false;il_target=1.0
	RenderingServer.environment_set_ssao_quality(ao,ao_half,ao_target,2,50,300)
	RenderingServer.environment_set_ssil_quality(il,il_half,il_target,2,50,300)
	RenderingServer.environment_set_ssr_half_size(s.get("rendering/environment/screen_space_reflection/half_size",false))
	var atlas:int=int(s.get("rendering/lights_and_shadows/directional_shadow/size",8192))
	RenderingServer.directional_shadow_atlas_set_size(atlas,bool(s.get("rendering/lights_and_shadows/directional_shadow/16_bits",false)))
	room.get_viewport().positional_shadow_atlas_size=int(s.get("rendering/lights_and_shadows/positional_shadow/atlas_size",8192))
	RenderingServer.directional_soft_shadow_filter_set_quality(int(s.get("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",3)))
	RenderingServer.positional_soft_shadow_filter_set_quality(int(s.get("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality",3)))
	RenderingServer.environment_set_volumetric_fog_volume_size(int(s.get("rendering/environment/volumetric_fog/volume_size",160)),int(s.get("rendering/environment/volumetric_fog/volume_depth",128)))
	room.get_viewport().msaa_3d=int(s.get("rendering/anti_aliasing/quality/msaa_3d",0))
	room.get_viewport().use_taa=bool(s.get("rendering/anti_aliasing/quality/use_taa",true))
	effective_quality={"version":v,"ao":ao,"ao_half":ao_half,"il":il,"il_half":il_half,"shadow_size":atlas,"ssr_steps":profile.environment.ssr_max_steps,"msaa":room.get_viewport().msaa_3d,"fog_size":s.get("rendering/environment/volumetric_fog/volume_size",160),"fog_depth":s.get("rendering/environment/volumetric_fog/volume_depth",128)}

func switch_bake(index:int) -> void:
	if baseline_gi==null or active_gi_profile==index:return
	for id in baseline_modes:
		var node=instance_from_id(id)
		if is_instance_valid(node):node.gi_mode=baseline_modes[id] if index==0 else GeometryInstance3D.GI_MODE_DYNAMIC
	if not gi_cache.has(index):
		var version:String=VERSIONS[index]
		var source:LightmapGIData=load(ROOT+"gi_"+version+".res")
		var copy:LightmapGIData=source.duplicate()
		var users:Array=source.get("user_data");copy.clear_users()
		var accepted:Dictionary=compatibility.get(version,{})
		var skipped=[]
		for i in range(0,users.size(),4):
			var path:String=str(users[i]);var mi=room.lightmap.get_node_or_null(users[i])
			if mi!=null and accepted.has(path) and mi.global_transform.is_equal_approx(accepted[path]):
				copy.add_user(users[i],users[i+1],users[i+2],users[i+3])
			else:skipped.append(path)
		gi_cache[index]=copy;binding_report[version]={"exact_texel_bindings":copy.get_user_count(),"changed_objects_use_original_probes":skipped}
	room.lightmap.light_data=gi_cache[index]
	if index>0:
		for i in room.lightmap.light_data.get_user_count():
			var mi=room.lightmap.get_node_or_null(room.lightmap.light_data.get_user_path(i))
			if mi!=null:mi.gi_mode=GeometryInstance3D.GI_MODE_STATIC
	active_gi_profile=index;room.light_controls.captured_lightmap=false

func apply(index:int,values:Dictionary) -> void:
	switch_bake(index)
	if index==0:return
	var profile:Dictionary=PROFILES[index];var defaults:Dictionary=profile.values
	assign(room.environment,profile.environment)
	assign(room.get_node("RoomReflections"),profile.probe)
	assign(room.lightmap,profile.lightmap)
	apply_quality(profile)
	for key in profile.lights:
		var lamp=original_lamp(key,profile.lights[key])
		if lamp==null:continue
		assign(lamp,profile.lights[key].values)
		if lamp==room.sun:
			lamp.light_energy*=float(values.sun)/float(defaults.sun)
			lamp.light_color=Color(1,.96,.88).lerp(Color(1,.81,.56),float(values.warmth))
			lamp.light_volumetric_fog_energy*=float(values.rays)/float(defaults.rays)
		elif key!="Desk lamp":lamp.light_energy*=float(values.fill)/float(defaults.fill)
	room.environment.tonemap_exposure=values.exposure
	room.environment.ambient_light_energy*=float(values.fill)/float(defaults.fill)
	room.environment.ssil_intensity*=minf(1.0,float(values.bounce)/float(defaults.bounce))
	if float(values.rays)<.001:room.environment.volumetric_fog_density=0

