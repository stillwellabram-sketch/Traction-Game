shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grain_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 coat : source_color = vec4(0.28, 0.34, 0.35, 1.0);
uniform float corrosion = 0.35;
uniform float metalness = 0.65;
varying vec3 local_position;
varying vec3 local_normal;
varying mat3 local_to_view;
float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i), hash(i+vec3(1,0,0)), f.x), mix(hash(i+vec3(0,1,0)), hash(i+vec3(1,1,0)), f.x), f.y), mix(mix(hash(i+vec3(0,0,1)), hash(i+vec3(1,0,1)), f.x), mix(hash(i+vec3(0,1,1)), hash(i+vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
	local_to_view = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec3 n = normalize(local_normal);
	vec3 w = pow(abs(n), vec3(5.0)); w /= max(w.x+w.y+w.z, 0.001);
	vec3 p = local_position * 2.0;
	vec3 grain = texture(grain_map, p.zy).rgb*w.x + texture(grain_map, p.xz).rgb*w.y + texture(grain_map, p.xy).rgb*w.z;
	float patches = noise3(local_position*3.0)*0.7 + noise3(local_position*31.0)*0.3;
	float rust = smoothstep(0.68-corrosion*0.48, 0.86-corrosion*0.45, patches)*corrosion;
	vec3 oxidized = mix(vec3(0.13,0.065,0.028), vec3(0.26,0.12,0.052), noise3(local_position*18.0));
	ALBEDO = mix(coat.rgb*(0.65+grain*0.65), oxidized, rust);
	METALLIC = mix(metalness, 0.03, rust);
	ROUGHNESS = mix(0.42+grain.r*0.22, 0.95, rust);
	vec3 nx = texture(normal_map,p.zy).xyz*2.0-1.0;
	vec3 ny = texture(normal_map,p.xz).xyz*2.0-1.0;
	vec3 nz = texture(normal_map,p.xy).xyz*2.0-1.0;
	vec3 bump = normalize(vec3(nx.z*sign(n.x),nx.y,nx.x)*w.x + vec3(ny.x,ny.z*sign(n.y),ny.y)*w.y + vec3(nz.x,nz.y,nz.z*sign(n.z))*w.z);
	NORMAL = normalize(local_to_view * normalize(mix(n,bump,0.25)));
}
