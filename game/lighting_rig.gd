extends RefCounted

# Shared by the playable room and the offline bake stage.
func setup(r:Node3D) -> void:
	var e:=Environment.new()
	r.environment=e
	e.background_mode=Environment.BG_COLOR;e.background_color=Color(.10,.075,.045)
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.78,.84,.94);e.ambient_light_energy=.025
	e.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode=Environment.TONE_MAPPER_AGX;e.tonemap_exposure=1.05;e.tonemap_agx_contrast=1.15
	e.ssao_enabled=true;e.ssao_radius=.16;e.ssao_intensity=.78;e.ssao_power=1.0;e.ssao_detail=.80;e.ssao_sharpness=.94
	e.ssil_enabled=true;e.ssil_radius=.65;e.ssil_intensity=.32;e.ssil_normal_rejection=.85
	e.ssr_enabled=true;e.ssr_max_steps=192;e.ssr_depth_tolerance=.12;e.ssr_fade_in=.18;e.ssr_fade_out=2.4
	e.volumetric_fog_enabled=true;e.volumetric_fog_density=.00042;e.volumetric_fog_albedo=Color(.94,.90,.82)
	e.volumetric_fog_length=22;e.volumetric_fog_detail_spread=2.4;e.volumetric_fog_anisotropy=.55
	e.volumetric_fog_ambient_inject=.025;e.volumetric_fog_gi_inject=.2;e.volumetric_fog_temporal_reprojection_amount=.92
	e.glow_enabled=true;e.glow_intensity=.18;e.glow_bloom=.006;e.glow_hdr_threshold=1.8
	e.adjustment_enabled=true;e.adjustment_saturation=.94;e.adjustment_contrast=1.015
	var world:=WorldEnvironment.new();world.name="RoomEnvironment";world.environment=e;r.add_child(world)
	var s:=DirectionalLight3D.new();s.name="WindowSun";r.add_child(s);r.sun=s
	s.position=Vector3(-5.5,8.6,-11.2);s.look_at(Vector3(2.9,0,3.9));s.light_color=Color(1,.86,.66)
	s.light_energy=5.2;s.light_indirect_energy=1.0;s.light_angular_distance=.85;s.shadow_enabled=true
	s.shadow_bias=.025;s.shadow_normal_bias=.35;s.directional_shadow_max_distance=28;s.directional_shadow_blend_splits=true
	s.directional_shadow_split_1=.07;s.directional_shadow_split_2=.20;s.directional_shadow_split_3=.50
	s.shadow_contact_shadows_allow=true;s.light_volumetric_fog_energy=6.5;s.light_bake_mode=Light3D.BAKE_DYNAMIC
	# Window-shaped area emitter, rather than a broad spot or unshadowed room flood.
	var w:=AreaLight3D.new();w.name="WindowFill";r.add_child(w);w.position=Vector3(-2.52,4.48,-7.05)
	w.look_at(Vector3(-1.3,3.3,1));w.area_size=Vector2(4.55,3.6);w.area_range=17;w.area_attenuation=1.25
	w.area_normalize_energy=false;w.light_color=Color(.80,.88,1);w.light_energy=.68;w.light_size=1.25
	w.shadow_enabled=true;w.shadow_bias=.03;w.shadow_normal_bias=.35;w.light_specular=.55;w.light_volumetric_fog_energy=.5
	w.light_bake_mode=Light3D.BAKE_DYNAMIC
	r._omni("Floor warm reflection",Vector3(.6,.5,.8),Color(1,.86,.65),.035,6)
	r._omni("Soft room fill",Vector3(-1,2.7,3.8),Color(.82,.88,1),.07,12)
	r._omni("Left wall bounce",Vector3(-5,3,-1),Color(1,.87,.67),.07,9)
	r._omni("Right wall bounce",Vector3(5,2.8,-1),Color(.78,.86,1),.055,9)
	r._omni("Cream wall bounce",Vector3(2.8,3.8,3.8),Color(1,.91,.75),.10,12)
	r._omni("Desk lamp",Vector3(6.58,5.36,-6.48),Color(1,.54,.24),.80,3.4)
	var return_light:=DirectionalLight3D.new();return_light.name="Broad wall return";r.add_child(return_light)
	return_light.position=Vector3(2,5,5);return_light.look_at(Vector3(-1,0,-2));return_light.light_color=Color(.87,.90,1)
	return_light.light_energy=.10;return_light.light_specular=.05;return_light.light_bake_mode=Light3D.BAKE_DISABLED;return_light.light_volumetric_fog_energy=0
	var probe:=ReflectionProbe.new();probe.name="RoomReflections";probe.size=Vector3(17,8.2,16);probe.position=Vector3(0,3.7,-.4)
	probe.interior=true;probe.box_projection=true;probe.intensity=.70;probe.ambient_mode=ReflectionProbe.AMBIENT_DISABLED;probe.cull_mask=1
	probe.enable_shadows=true;probe.mesh_lod_threshold=.5;r.add_child(probe)
	r.gi=VoxelGI.new();r.gi.name="WarmBounceGI";r.gi.size=Vector3(17.4,9,17.6);r.gi.position=Vector3(0,4.1,-.2);r.gi.subdiv=VoxelGI.SUBDIV_256;r.add_child(r.gi)
	r.lightmap=LightmapGI.new();r.lightmap.name="BakedRoomLight";r.lightmap.directional=true;r.lightmap.interior=false
	r.lightmap.quality=LightmapGI.BAKE_QUALITY_HIGH;r.lightmap.bounces=6;r.lightmap.bounce_indirect_energy=1.0
	r.lightmap.max_texture_size=2048;r.lightmap.texel_scale=1.25;r.lightmap.generate_probes_subdiv=LightmapGI.GENERATE_PROBES_SUBDIV_8
	r.lightmap.environment_mode=LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR;r.lightmap.environment_custom_color=Color(.70,.80,1)
	r.lightmap.environment_custom_energy=.32;r.lightmap.specular_intensity=.55;r.lightmap.denoiser_strength=.045;r.add_child(r.lightmap)
