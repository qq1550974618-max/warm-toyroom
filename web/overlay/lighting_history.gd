extends RefCounted
const NAMES=["当前版本灯光"]
const IDS=["current"]
var PROFILES:Array=[{}]
var room:Node3D
var baseline_environment={}
var baseline_camera_attributes={}
var baseline_lights={}
var baseline_lightmap={}
var baseline_gi:LightmapGIData
func bind(r:Node3D) -> void:
	room=r;baseline_environment=stored(r.environment);baseline_camera_attributes=stored(r.attributes);baseline_lightmap=stored(r.lightmap)
	for lamp in r.get_children():
		if lamp is Light3D:baseline_lights[str(lamp.name)]=stored(lamp)
func restore() -> void:
	assign(room.environment,baseline_environment);assign_camera_values(baseline_camera_attributes);assign(room.lightmap,baseline_lightmap)
	for key in baseline_lights:assign(room.get_node(key),baseline_lights[key])
func sync_baked_shadows() -> void:
	for key in baseline_lights:baseline_lights[key].shadow_enabled=room.get_node(key).shadow_enabled
	baseline_gi=room.lightmap.light_data
func switch_bake(_index:int) -> void:pass
func apply(_index:int,_values:Dictionary) -> void:pass
func original_lamp(key:String,_entry:Dictionary) -> Light3D:return room.get_node_or_null(key)
func stored(object:Object) -> Dictionary:
	var result={}
	for p in object.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE):continue
		if str(p.name) in ["script","owner","name","resource_name","resource_path","resource_local_to_scene","process_mode","process_priority","process_physics_priority","physics_interpolation_mode","resource_scene_unique_id"]:continue
		var value=object.get(p.name)
		if typeof(value) in [TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_VECTOR2,TYPE_VECTOR3,TYPE_COLOR,TYPE_TRANSFORM3D]:result[p.name]=value
	return result

func assign_camera_values(properties:Dictionary) -> void:
	# A lighting comparison must not refocus the paused view to the old camera.
	var focus={}
	for key in ["dof_blur_far_enabled","dof_blur_near_enabled","dof_blur_far_distance","dof_blur_near_distance","dof_blur_far_transition","dof_blur_near_transition"]:focus[key]=room.attributes.get(key)
	assign(room.attributes,properties);assign(room.attributes,focus)

func assign(object:Object,properties:Dictionary) -> void:
	var valid={}
	for p in object.get_property_list():valid[p.name]=true
	for key in properties:
		if valid.has(key) and object.get(key)!=properties[key]:object.set(key,properties[key])
