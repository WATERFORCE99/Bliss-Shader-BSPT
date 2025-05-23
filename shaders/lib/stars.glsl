//Original star code : https://www.shadertoy.com/view/Md2SR3 , optimised

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

float stars(vec3 viewPos){

	float stars = max(1.0 - StableStarField(viewPos * 300.0 , 1 - 0.1 * STAR_DENSITY), 0.0);
	return exp(stars * -20.0);
}
