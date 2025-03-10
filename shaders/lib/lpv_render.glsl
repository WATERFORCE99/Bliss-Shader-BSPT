float lpvCurve(float values) {
	#ifdef VANILLA_LIGHTMAP_MASK
		return sqrt(values);
	#else
		return values*values;
	#endif
}

vec4 SampleLpvLinear(const in vec3 lpvPos) {
	vec3 texcoord = lpvPos / LpvSize3;

	vec4 lpvSample = (frameCounter % 2) == 0
		? textureLod(texLpv1, texcoord, 0)
		: textureLod(texLpv2, texcoord, 0);

	vec3 hsv = RgbToHsv(lpvSample.rgb);
	hsv.z = lpvCurve(hsv.b) * LpvBlockSkyRange.x;
	lpvSample.rgb = HsvToRgb(hsv);
    
	lpvSample.rgb = clamp(lpvSample.rgb/15.0,0.0,1.0);

	return lpvSample;
}

vec3 GetLpvBlockLight(const in vec4 lpvSample) {
	return lpvSample.rgb * (LPV_BLOCKLIGHT_SCALE/15.0);
}

float GetLpvSkyLight(const in vec4 lpvSample) {
	float skyLight = clamp(lpvSample.a, 0.0, 1.0);
	return skyLight*skyLight;
}

vec3 LPV_FOG_ILLUMINATION(in vec3 playerPos, float dd, float dL){
	vec3 color = vec3(0.0);

	vec3 lpvPos = GetLpvPosition(playerPos);

        float fadeLength = 10.0; // in blocks
        vec3 cubicRadius = clamp(	min(((LpvSize3-1.0) - lpvPos)/fadeLength, lpvPos/fadeLength) ,0.0,1.0);
        float LpvFadeF = cubicRadius.x*cubicRadius.y*cubicRadius.z;

	if(LpvFadeF > 0.0){
		vec3 lighting = SampleLpvLinear(lpvPos).rgb * (LPV_VL_FOG_ILLUMINATION_BRIGHTNESS/100.0);
		float density = exp(-5.0 * (1.0-length(lighting.xyz)))  * LpvFadeF;

		color = lighting - lighting * exp(-density*dd*dL);
	}
	return color;
}