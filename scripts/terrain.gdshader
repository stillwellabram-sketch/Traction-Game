shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D soil_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 routes[2];
varying vec3 terrain_position;
varying vec3 terrain_normal;
void vertex() {
	terrain_position = VERTEX;
	terrain_normal = NORMAL;
}
void fragment() {
	vec3 grain = texture(soil_texture, terrain_position.xz * 0.3).rgb;
	float broad = texture(soil_texture, terrain_position.xz * 0.011).r;
	float rock = smoothstep(0.13, 0.48, 1.0 - normalize(terrain_normal).y);
	vec3 meadow = mix(vec3(0.045, 0.09, 0.016), vec3(0.15, 0.23, 0.055), broad);
	meadow = mix(meadow, vec3(0.14, 0.19, 0.043), COLOR.g * 0.45);
	vec3 mud = mix(vec3(0.065, 0.052, 0.033), vec3(0.20, 0.17, 0.11), broad);
	float lane = 10000.0;
	float along = 0.0;
	for (int i = 0; i < 2; i++) {
		float d = abs(abs(dot(terrain_position.xz, routes[i].xy) - routes[i].z) - routes[i].w);
		if (d < lane) { lane = d; along = dot(terrain_position.xz, vec2(-routes[i].y, routes[i].x)); }
	}
	float rib = 1.0 - smoothstep(0.7, 2.8, abs(mod(along + 6.0, 12.0) - 6.0));
	mud *= mix(0.7, 1.3, rib);
	vec3 ground = mix(meadow, mud, COLOR.r);
	ground = mix(ground, vec3(0.30, 0.29, 0.24), rock * 0.7);
	ALBEDO = ground * (0.65 + grain * 0.75);
	ROUGHNESS = mix(0.98, 0.78, COLOR.r);
	// Detail perturbation in view space avoids a tangent requirement on the height mesh.
	vec3 bump = texture(soil_normal, terrain_position.xz * 0.3).xyz * 2.0 - 1.0;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump.x, 0.0, bump.y, 0.0)).xyz * 0.18);
}
