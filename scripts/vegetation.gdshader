shader_type spatial;
render_mode cull_disabled;
varying vec4 tint;
void vertex() {
	tint = COLOR;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.3 + world.x * 0.3 + world.z * 0.2);
	VERTEX.x += sway * VERTEX.y * 0.07;
}
void fragment() {
	ALBEDO = tint.rgb;
	ROUGHNESS = 1.0;
	BACKLIGHT = tint.rgb * 0.3;
}
