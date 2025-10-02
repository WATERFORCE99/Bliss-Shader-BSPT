// Hue generate thanks to Builderb0y.
vec3 smoothHue(float h) {
	vec3 phaseShift = vec3(0.0, 1.0, 2.0) * (TAU / 3.0);
	vec3 cosine = cos(h * TAU - phaseShift);
	return sqrt(normalize((cosine * 0.5 + 0.5) * (cosine * 0.5 + 0.5)));
}

vec3 drawRainbow(vec3 playerPos) {
	float rainbowAmount = RAINBOW == 1 ? wetness * (1.0 - rainStrength) : 1.0;

	#ifdef DISTANT_HORIZONS
		float maxDist = dhFarPlane;
	#else
		float maxDist = 4.0 * far;
	#endif

	float rainbowDist = min(maxDist, RAINBOW_DISTANCE);
	float RdotV = dot(-WsunVec, normalize(playerPos));

	if (isEyeInWater == 0 && rainbowAmount > 0.0) {		
		vec3 colorBand = vec3(0.0);

		float mainCoord = (RdotV - cos(0.75 - RAINBOW_WIDTH)) / (cos(0.75 + RAINBOW_WIDTH) - cos(0.75 - RAINBOW_WIDTH));
		mainCoord = clamp(mainCoord, 0.0, 1.0);

		float mainFactor = pow(mainCoord, 3.0) * pow(1.0 - mainCoord, 0.5);
		vec3 mainColor = smoothHue(-mainCoord) * mainFactor;
		colorBand += mainColor;

		float subCoord = (RdotV - cos(1.0 - RAINBOW_WIDTH * 1.5)) / (cos(1.0 + RAINBOW_WIDTH * 1.5) - cos(1.0 - RAINBOW_WIDTH * 1.5));
		subCoord = clamp(subCoord, 0.0, 1.0);

		float subFactor = pow(subCoord * (1.0 - subCoord), 2.0);
		vec3 subColor = smoothHue(subCoord) * subFactor * 0.2;
		colorBand += subColor;
		colorBand *= RAINBOW_STRENGTH;

		float lengthFactor = smoothstep(rainbowDist * 0.9, rainbowDist * 1.1, length(playerPos));
		float elevationFade = smoothstep(0.025, 0.1, WsunVec.y);
		rainbowAmount *= lengthFactor * elevationFade;

		return colorBand * rainbowAmount;
	}
	return vec3(0.0);
}