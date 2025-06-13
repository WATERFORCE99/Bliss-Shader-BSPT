//Original star code : https://www.shadertoy.com/view/Md2SR3 , optimised
//Original shooting star code : https://www.shadertoy.com/view/ttVXDy

///////////////////////////// STAR FIELD /////////////////////////////////

// Convert Noise2d() into a "star field" by stomping everthing below fThreshhold to zero.
float NoisyStarField(in vec3 vSamplePos, float fThreshhold){
	float StarVal = hash13(vSamplePos);
	StarVal = clamp(StarVal/(1.0 - fThreshhold) - fThreshhold/(1.0 - fThreshhold), 0.0, 1.0);

	return StarVal;
}

// Stabilize NoisyStarField() by only sampling at integer values.
float StableStarField( in vec3 vSamplePos, float fThreshhold ){
	// Linear interpolation between four samples.
	// Note: This approach has some visual artifacts.
	// There must be a better way to "anti alias" the star field.
	float fractX = fract(vSamplePos.x);
	float fractY = fract(vSamplePos.y);
	vec3 floorSample = floor(vSamplePos.xyz);

	float v1 = NoisyStarField(floorSample, fThreshhold);
	float v2 = NoisyStarField(floorSample + vec3(0.0, 1.0, 0.0), fThreshhold);
	float v3 = NoisyStarField(floorSample + vec3(1.0, 0.0, 0.0), fThreshhold);
	float v4 = NoisyStarField(floorSample + vec3(1.0, 1.0, 0.0), fThreshhold);

	float StarVal = v1 * (1.0 - fractX) * (1.0 - fractY)
				+ v2 * (1.0 - fractX ) * fractY
				+ v3 * fractX * (1.0 - fractY)
				+ v4 * fractX * fractY;

	return StarVal;
}

float drawStars(vec3 viewPos){
	float stars = max(1.0 - StableStarField(viewPos * 300.0 , 1 - 0.1 * STAR_DENSITY), 0.0);
	return exp(stars * -20.0);
}

///////////////////////////// SHOOTING STAR /////////////////////////////////

float distLine(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p-a;
	vec2 ba = b-a;
	float t = clamp(dot(pa, ba)/ dot(ba, ba), 0.0, 1.0);
	return length(pa - ba*t);
}

float drawLine(vec2 p, vec2 a, vec2 b) {
	float d = distLine(p, a, b);
	float m = smoothstep(SHOOTING_STARS_TRAIL_WIDTH * 0.01, 0.00001, d);
	float d2 = length(a - b);
	m *= smoothstep(1.0, 0.5, d2) + smoothstep(0.04, 0.03, abs(d2 - 0.75));
	return m;
}

float shootingStar(vec2 uv) {
	vec2 gv = fract(uv) - 0.5;
	vec2 id = floor(uv);

	float h = hash21(id);
  
	if (h > SHOOTING_STARS_FREQUENCY * 0.01) return 0.0;

	float line = drawLine(gv, vec2(0.0, h), vec2(SHOOTING_STARS_TRAIL_LENGTH, h));
	float trail = smoothstep(SHOOTING_STARS_TRAIL_LENGTH * 1.2, 0.0, gv.x);

	return line * trail;
}

vec3 drawShootingStars(vec3 viewPos) {
	vec2 uv = viewPos.xz / viewPos.y;
	float t = frameTimeCounter * SHOOTING_STARS_SPEED;
	uv += vec2(t, 0.0);

	float stars = shootingStar(uv) * SHOOTING_STARS_TRAIL_VISIBILITY;

	return vec3(clamp(stars, 0.0, 1.0));
}