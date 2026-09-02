shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.5, 0.0, 0.0, 1.0);
uniform float radius : hint_range(0.0, 1.0) = 0.7;
uniform float softness : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec2 uv = UV;
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(uv, center);

	// Vignette edge darkening
	float vignette = smoothstep(radius, radius + softness, dist);

	// Pulse effect based on time
	float pulse = sin(TIME * 3.0) * 0.15 + 0.85;

	// Apply red vignette scaled by intensity
	float alpha = vignette * intensity * pulse;
	COLOR = vec4(vignette_color.rgb, alpha);
}
