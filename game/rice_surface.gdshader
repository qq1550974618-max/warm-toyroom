shader_type spatial;
render_mode cull_back;
uniform float fill_amount : hint_range(0.0, 1.0) = 1.0;
void vertex() {
    // INSTANCE_CUSTOM stores the grain centre in bowl space. Move each grain
    // intact as the surface descends; do not squash the grain mesh itself.
    vec3 p = INSTANCE_CUSTOM.xyz;
    float radial_scale = mix(0.57, 1.0, sqrt(fill_amount));
    float radius = length(p.xz) / 0.445;
    float dome = sqrt(max(0.0, 1.0 - radius * radius));
    vec3 next_p = vec3(p.x * radial_scale,
        0.103 + 0.203 * fill_amount + 0.095 * fill_amount * dome + INSTANCE_CUSTOM.w,
        p.z * radial_scale);
    VERTEX += (inverse(MODEL_MATRIX) * vec4(next_p - p, 0.0)).xyz;
}
void fragment() {
    ALBEDO = vec3(0.98, 0.97, 0.93) * COLOR.rgb;
    ROUGHNESS = 0.42;
    SPECULAR = 0.26;
    SSS_STRENGTH = 0.18;
}
