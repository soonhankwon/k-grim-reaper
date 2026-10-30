shader_type canvas_item;
render_mode unshaded;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;

float noise(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    vec4 tex = texture(TEXTURE, UV) * COLOR;
    vec2 pixel = floor(UV * vec2(76.0, 72.0));
    float n = noise(pixel);
    float spread = dissolve * 1.8 - 0.25 - (1.0 - UV.y) * 0.25;
    float edge = smoothstep(spread - 0.10, spread + 0.06, n);
    vec3 ink = vec3(0.06, 0.08, 0.10);
    float stain = (1.0 - smoothstep(spread - 0.04, spread + 0.23, n));
    COLOR = vec4(mix(tex.rgb, ink, stain), tex.a * edge);
}
