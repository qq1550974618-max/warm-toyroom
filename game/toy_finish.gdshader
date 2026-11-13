shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D base_map:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D bump_map:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D rough_map:filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec4 tint:source_color=vec4(1.0);
uniform bool has_base=false;
uniform bool has_bump=false;
uniform bool has_rough=false;
uniform float roughness_min=.6;
uniform float roughness_span=.15;
uniform float normal_strength=.1;
uniform float specular_amount=.3;
uniform float metallic_amount=0.0;
uniform float coat_amount=0.0;
uniform float coat_roughness=.35;
uniform float fiber_amount=0.0;
uniform float grain_amount=0.0;
uniform float gilt_amount=0.0;
uniform float micro_scale=220.0;
varying vec3 local_point;
float hash31(vec3 p){p=fract(p*.1031);p+=dot(p,p.yzx+33.33);return fract((p.x+p.y)*p.z);}
float noise3(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(mix(hash31(i),hash31(i+vec3(1,0,0)),f.x),mix(hash31(i+vec3(0,1,0)),hash31(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash31(i+vec3(0,0,1)),hash31(i+vec3(1,0,1)),f.x),mix(hash31(i+vec3(0,1,1)),hash31(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){local_point=VERTEX;}
void fragment(){
 vec3 c=tint.rgb;if(has_base)c*=texture(base_map,UV).rgb;
 // The imported PBR maps already contain the fine surface variation. Keep the
 // extra modulation analytic, so 2K pixels do not each evaluate two 3D noises.
 float n=.5,slow=.5+.25*sin(local_point.x*6.1+sin(local_point.z*3.7)+local_point.y*5.3);
 float fibers=sin(local_point.x*micro_scale*3.14159)*sin(local_point.y*micro_scale*3.14159);
 float anti_alias=1.0-smoothstep(.10,.65,length(fwidth(local_point*micro_scale)));
 float variation=1.0+fiber_amount*fibers*anti_alias+grain_amount*(slow-.5);
 ALBEDO=c*variation;
 float r=has_rough?texture(rough_map,UV).g:slow;
 float gilt=smoothstep(.035,.14,c.r-c.b)*smoothstep(.014,.08,c.g-c.b)*gilt_amount;
 ROUGHNESS=clamp(mix(roughness_min+roughness_span*r,.36,gilt)+.014*(n-.5),.18,.98);
 METALLIC=mix(metallic_amount,.64,gilt);SPECULAR=specular_amount;
 CLEARCOAT=coat_amount;CLEARCOAT_ROUGHNESS=coat_roughness;
 if(has_bump){NORMAL_MAP=texture(bump_map,UV).rgb;NORMAL_MAP_DEPTH=normal_strength;}
 else if(fiber_amount>0.0){
  vec2 weave=UV*90.0;
  float fade=1.0-smoothstep(.15,.7,length(fwidth(weave)));
  NORMAL_MAP=normalize(vec3(cos(weave.x*6.283)*.12*fade,cos(weave.y*6.283)*.12*fade,1.0))*.5+.5;
  NORMAL_MAP_DEPTH=.55;
 }
 RIM=fiber_amount*.7;RIM_TINT=.65;
}
