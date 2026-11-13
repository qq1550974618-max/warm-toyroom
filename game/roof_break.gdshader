shader_type spatial;
uniform sampler2D plaster_color : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D plaster_roughness : filter_linear_mipmap_anisotropic;
uniform vec4 wall_color : source_color;
uniform vec2 hole_center;
varying vec3 world_position;
void vertex(){ world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	vec2 p=world_position.xz-hole_center;
	float a=atan(p.y,p.x);
	float edge=.43+.025*sin(a*11.0)+.016*sin(a*19.0);
	if(max(abs(p.x),abs(p.y))<edge)discard;
	vec2 uv=world_position.xz*1.25;
	ALBEDO=texture(plaster_color,uv).rgb*wall_color.rgb;
	ROUGHNESS=texture(plaster_roughness,uv).r;
	SPECULAR=.12;
}
