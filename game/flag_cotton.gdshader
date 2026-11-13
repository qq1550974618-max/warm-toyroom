shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 tint : source_color=vec4(0.4,0.5,0.45,1.0);
uniform sampler2D cloth_albedo : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D cloth_normal : hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D cloth_roughness : hint_default_white,filter_linear_mipmap_anisotropic,repeat_enable;
void fragment(){
	vec2 uv=UV;
	float edge=min(uv.y,min(uv.x-uv.y*.5,1.0-uv.y*.5-uv.x));
	float aa=max(fwidth(edge),.0005);
	float hem=1.0-smoothstep(.020-aa,.020+aa,edge);
	float line=1.0-smoothstep(.0015-aa,.0015+aa,abs(edge-.013));
	float along=uv.y<.03?uv.x:uv.y;
	float thread=line*(1.0-smoothstep(.35,.50,fract(along*48.0)));
	vec3 cloth=texture(cloth_albedo,uv).rgb;
	ALBEDO=tint.rgb*cloth*(1.0-hem*.045)+tint.rgb*thread*.13;
	NORMAL_MAP=texture(cloth_normal,uv).rgb;NORMAL_MAP_DEPTH=.48;
	ROUGHNESS=texture(cloth_roughness,uv).r;SPECULAR=.13;
	BACKLIGHT=tint.rgb*.025;
}
