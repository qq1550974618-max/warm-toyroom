extends RefCounted
# Captured from the actual V24.1 release with its current rig, Micro Warm
# preset, extreme quality and default sliders. Retains current geometry.
var profile:Dictionary={}
func apply(controls) -> void:
	if profile.is_empty():
		profile=FileAccess.open("res://assets/lighting_v30/v24_1_micro_warm.bin",FileAccess.READ).get_var()
	var room=controls.room;var h=controls.history
	h.switch_bake(0)
	h.assign(room.environment,profile.environment)
	h.assign_camera_values(profile.camera_attributes)
	h.assign(room.get_node("RoomReflections"),profile.probe)
	h.assign(room.lightmap,profile.lightmap)
	for key in profile.lights:
		var lamp=room.get_node_or_null(key)
		if lamp is Light3D:h.assign(lamp,profile.lights[key].values)
	if room.lightmap.light_data!=null:
		var data:LightmapGIData=room.lightmap.light_data
		RenderingServer.lightmap_set_baked_exposure_normalization(data.get_rid(),float(data.get("probe_data").get("baked_exposure",1.0)))
	controls.apply_render_quality()
