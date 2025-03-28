vec3 RgbToHsv(const in vec3 c) {
	const vec4 K = vec4(0.0, -1.0, 2.0, -3.0) / 3.0;
	const float e = 1.0e-10;

	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 HsvToRgb(const in vec3 c) {
	const vec4 K = vec4(3.0, 2.0, 1.0, 9.0) / 3.0;

	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
