// Hue generate thanks to Builderb0y.
vec3 smoothHue(float h) {
	vec3 phaseShift = vec3(0.0, 1.0, 2.0) * (TAU / 3.0);
	vec3 cosine = cos(h * TAU - phaseShift);
	return sqrt(normalize((cosine * 0.5 + 0.5) * (cosine * 0.5 + 0.5)));
}

vec3 drawRainbow(vec3 viewPos, vec3 playerPos, float dither) {

	vec3 sunDir = normalize(WsunVec);
	float rainbowAng = (sign(sunDir.x) > 0.0) ? 130.0 : -130.0;
	float theta = radians(rainbowAng);

	float VdotL = dot(playerPos, sunDir);
	float rainbowWidth = 0.05;
	float rainbowCoord = clamp((VdotL - cos(theta + rainbowWidth)) / (cos(theta - rainbowWidth) - cos(theta + rainbowWidth)), 0.0, 1.0);

	vec3 rainbow = vec3(0.0);
	if (rainbowCoord > 0.0) {
		float rainbowFactor = pow(rainbowCoord * (1.0 - rainbowCoord) * 12.0, 2.0);

		float rainbowDist = smoothstep(0.0, 1.0, length(viewPos) / max(farPlane, 128.0));
		float horizonFade = clamp(sunDir.y * 5.0, 0.0, 1.0);
		float elevationFade = smoothstep(0.3, 0.4, sunDir.y);

		float afterRain = RAINBOW == 1 ? wetness * (1.0 - rainStrength) : 1.0;

		rainbowFactor *= rainbowDist * horizonFade * elevationFade * afterRain;

		vec3 colorBand = smoothHue(rainbowCoord * 0.95 + 0.05);
        
		colorBand *= vec3(1.5, 0.8, 1.2);
		rainbow = colorBand * rainbowFactor * 0.02;
	}
	return rainbow;
}