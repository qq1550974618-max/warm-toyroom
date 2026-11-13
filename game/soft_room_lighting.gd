extends RefCounted
# Presentation balance inspired by the verified V4 reference photograph.
# Material resources, GI resolution and sampling quality are never changed here.
var room:Node3D
const FILL_ENERGY={
	"Floor warm reflection":.24,
	"Soft room fill":.92,
	"Left wall bounce":.55,
	"Right wall bounce":.42,
	"Cream wall bounce":.48,
	"Broad wall return":.22,
}

func bind(owner_room:Node3D) -> void:
	room=owner_room

func active_lamp(label:String,controls) -> Light3D:
	if controls.reference_index>0:
		var profile:Dictionary=controls.history.PROFILES[controls.reference_index]
		if profile.lights.has(label):return controls.history.original_lamp(label,profile.lights[label])
	return room.get_node_or_null(label) as Light3D

func apply(controls) -> void:
	if controls.preset_index!=0:return
	var v:Dictionary=controls.values
	var fill:float=float(v.fill)*float(v.bounce)
	var e:Environment=room.environment
	# V4 used neutral grading and much more reflected room light. Lift actual
	# illumination rather than a gray screen overlay or washed-out albedo maps.
	e.tonemap_agx_contrast=1.0;e.adjustment_contrast=1.0;e.adjustment_saturation=.96
	e.ambient_light_color=Color(.83,.88,.96);e.ambient_light_energy=.14*fill
	e.glow_intensity=.18;e.glow_bloom=.008;e.glow_hdr_threshold=1.8
	e.volumetric_fog_density=.00065 if float(v.rays)>.001 else 0.0
	e.volumetric_fog_anisotropy=.40;e.volumetric_fog_ambient_inject=.10
	room.sun.light_energy=3.35*float(v.sun)
	room.sun.light_color=Color(1,.97,.91).lerp(Color(1,.845,.64),float(v.warmth))
	room.sun.light_angular_distance=1.65;room.sun.light_specular=.70
	room.sun.light_volumetric_fog_energy=2.0*float(v.rays)
	for label in FILL_ENERGY:
		var lamp:=active_lamp(label,controls)
		if lamp!=null:
			lamp.light_energy=float(FILL_ENERGY[label])*fill
			lamp.light_specular=.05 if label=="Broad wall return" else 0.0
			lamp.light_volumetric_fog_energy=0
	var window:=active_lamp("WindowFill",controls)
	if window!=null:
		window.light_energy=(1.8 if window is SpotLight3D else .90)*fill
		window.light_specular=.22;window.light_size=1.4
		window.light_volumetric_fog_energy=.3*float(v.rays)
