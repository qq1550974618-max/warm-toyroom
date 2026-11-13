shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D paper_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_point;
void vertex(){world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
	// Separate page leaves at physical scale; derivatives prevent distant shimmer.
	float h=world_point.y*520.0;
	float ripple=sin(world_point.x*41.0+world_point.z*23.0)*0.09;
	float aa=max(fwidth(h),0.02);
	float band=1.0-smoothstep(0.08-aa,0.08+aa,abs(fract(h+ripple)-0.5));
	band=mix(band,0.16,clamp(aa,0.0,1.0));
	vec3 fiber=texture(paper_map,world_point.xz*4.0).rgb;
	float irregular=0.025*sin(floor(h)*8.17);
	ALBEDO=vec3(0.83,0.79,0.68)*mix(vec3(1.0),fiber,0.27)*(1.0-band*0.19+irregular);
	ROUGHNESS=0.91;SPECULAR=0.13;
}
