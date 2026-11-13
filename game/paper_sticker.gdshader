shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D printed_character : source_color, filter_linear_mipmap;
uniform vec4 artwork_rect=vec4(0.158203125,0.07421875,0.68359375,0.8525390625);
void fragment() {
    vec2 uv=artwork_rect.xy+UV*artwork_rect.zw;
    vec4 ink = texture(printed_character, uv);
    vec2 texel = vec2(0.004);
    float edge = ink.a;
    edge = max(edge, texture(printed_character, uv + vec2(texel.x, 0.0)).a);
    edge = max(edge, texture(printed_character, uv - vec2(texel.x, 0.0)).a);
    edge = max(edge, texture(printed_character, uv + vec2(0.0, texel.y)).a);
    edge = max(edge, texture(printed_character, uv - vec2(0.0, texel.y)).a);
    // Flat printed inks and a thin cut-paper edge have no highlights or normals.
    vec3 color = floor(ink.rgb * 12.0 + 0.5) / 12.0;
    ALBEDO = mix(vec3(0.77, 0.73, 0.62), color * 0.82, smoothstep(0.15,0.8,ink.a));
    ALPHA = edge;
    ALPHA_SCISSOR_THRESHOLD = 0.4;
    ROUGHNESS=1.0;
    SPECULAR=0.0;
}
