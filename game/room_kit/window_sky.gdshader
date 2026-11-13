shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
void fragment(){
	vec3 upper=vec3(.62,.75,.86);vec3 lower=vec3(1.0,.93,.77);
	vec3 sky=mix(upper,lower,smoothstep(.12,.98,UV.y));
	float cloud=sin(UV.x*8.0+sin(UV.y*5.0))*sin(UV.y*10.0+UV.x*2.0);
	ALBEDO=sky*(1.35+cloud*.018);
}
