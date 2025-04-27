//Original ripple code : https://www.shadertoy.com/view/ldfyzl , optimised

// Maximum number of cells a ripple can cross.
#define MAX_RADIUS 2

vec3 drawRipples(vec2 uv, float time) {
	vec2 p0 = floor(uv);
	vec2 circles = vec2(0.0);
	for (int j = -MAX_RADIUS; j < MAX_RADIUS; ++j) {
		for (int i = -MAX_RADIUS; i < MAX_RADIUS; ++i) {
			vec2 pi = p0 + vec2(i, j);
			vec2 rand = simpleRand22(pi);
			vec2 p = pi + rand;

			float t = fract(0.6 * time + rand.x);
			vec2 v = p - uv;
			float d = length(v) - (float(MAX_RADIUS) + 1.0) * t;

			float carrier = cos(6.0 * PI * d);
			float x = clamp(3.0 * d + 1.0, - 1.0, 1.0); 
			float energy = 1.0 - x * x * (3.0 - 2.0 * abs(x));
			float decay = (1.0 - t) * (1.0 - t);
			if (decay < 0.04) continue;

			circles += 20.0 * normalize(v) * carrier * energy * decay;
		}
	}
	circles /= float((MAX_RADIUS * 2) * (MAX_RADIUS * 2));

	vec3 n = vec3(circles, sqrt(1.0 - dot(circles, circles)));
	return n;
}