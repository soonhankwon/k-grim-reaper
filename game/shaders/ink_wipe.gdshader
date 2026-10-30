shader_type canvas_item;
render_mode unshaded;
uniform float coverage : hint_range(0.0, 1.6) = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
    vec2 centered = (UV - vec2(0.5)) * vec2(1.35, 1.0);
    float grain = hash(floor(UV * vec2(92.0, 52.0)));
    float radius = length(centered) + (grain - 0.5) * 0.07;
    float alpha = coverage <= 0.001 ? 0.0 : 1.0 - smoothstep(coverage - 0.04, coverage + 0.04, radius);
    COLOR = vec4(0.04, 0.055, 0.065, alpha);
}
