uniform int moonPhase;

const float sunAngularSize = 0.533333;
const float moonAngularSize = 0.516667;

// Sky coefficients and heights

const float sky_planetRadius = 6731e3;
const float sky_atmosphereHeight = 140e3;

const vec2 sky_scaleHeights = vec2(85e2, 12e2);

const vec3 ozoneAbsorption = vec3(2.0e-6, 5.8e-6, 0.2e-6);
const vec3 rayleighBeta = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const vec3 sky_coefficientRayleigh = vec3(sky_coefficientRayleighR, sky_coefficientRayleighG, sky_coefficientRayleighB) * rayleighBeta + ozoneAbsorption;

const float mieBeta = 2.1e-5;
const vec3 sky_coefficientMie = vec3(sky_coefficientMieR, sky_coefficientMieG, sky_coefficientMieB) * mieBeta;

const vec3 sky_coefficientOzone = vec3(4.9799463143e-10, 3.0842607592e-10, -9.1714404502e-12);
const vec2 sky_inverseScaleHeights = 1.44269502 / sky_scaleHeights;
const vec2 sky_scaledPlanetRadius = sky_planetRadius * sky_inverseScaleHeights;
const float sky_atmosphereRadius = sky_planetRadius + sky_atmosphereHeight;
const float sky_atmosphereRadiusSquared = sky_atmosphereRadius * sky_atmosphereRadius;

#define sky_coefficientsScattering mat2x3(sky_coefficientRayleigh, sky_coefficientMie)
const mat3 sky_coefficientsAttenuation = mat3(sky_coefficientRayleigh , sky_coefficientMie, sky_coefficientOzone); // commonly called the extinction coefficient

#ifdef MOONPHASE_BASED_MOONLIGHT
	float moonlightbrightness = abs(4-moonPhase)/4.0;
#else
	float moonlightbrightness = 1.0;
#endif

#if colortype == 1
	#define sunColorBase vec3(sunColorR, sunColorG, sunColorB) * sun_illuminance
	#define moonColorBase vec3(moonColorR,moonColorG,moonColorB) * moon_illuminance * moonlightbrightness
#else
	#define sunColorBase blackbody(Sun_temp) * sun_illuminance
	#define moonColorBase blackbody(Moon_temp) * moon_illuminance * moonlightbrightness
#endif

float sky_rayleighPhase(float cosTheta) {
	const float rayleighFactor = 3.0 * rPI / 16.0;
	return rayleighFactor * (1.0 + cosTheta * cosTheta);
}

float sky_miePhase(float cosTheta, const float g) {
	float gg = g * g;
	float denom = 1.0 + gg - 2.0 * g * cosTheta;
	if (denom <= 0.0) return 0.0;
	float num = (1.0 - gg) * (1.0 + cosTheta * cosTheta);
	return (3.0  * rPI / 8.0) * num / ((2.0 + gg) * pow(denom, 1.5));
}

vec2 sky_phase(float cosTheta, const float g) {
	return vec2(sky_rayleighPhase(cosTheta), sky_miePhase(cosTheta, g));
}

vec3 sky_density(float centerDistance) {
	vec2 rayleighMie = exp(sky_scaledPlanetRadius - centerDistance * sky_inverseScaleHeights);

	// Ozone distribution curve by Sergeant Sarcasm - https://www.desmos.com/calculator/j0wozszdwa
	float ozone = exp(-max(0.0, (35000.0 - centerDistance) - sky_planetRadius) / 5000.0) * exp(-max(0.0, (centerDistance - 35000.0) - sky_planetRadius) / 15000.0);
	return vec3(rayleighMie, ozone);
}

vec3 sky_airmass(vec3 position, vec3 direction, float rayLength, const float steps) {
	float stepSize  = rayLength * (1.0 / steps);
	vec3  increment = direction * stepSize;
	position += increment * 0.5;

	vec3 airmass = vec3(0.0);
	for (int i = 0; i < steps; ++i, position += increment) {
		airmass += sky_density(length(position));
	}
	return airmass * stepSize;
}

vec3 sky_airmass(vec3 position, vec3 direction, const float steps) {
	float rayLength = dot(position, direction);
	rayLength = rayLength * rayLength + sky_atmosphereRadiusSquared - dot(position, position);
	if (rayLength < 0.0) return vec3(0.0);
	rayLength = sqrt(rayLength) - dot(position, direction);

	return sky_airmass(position, direction, rayLength, steps);
}

vec3 sky_opticalDepth(vec3 position, vec3 direction, const float steps) {
	return sky_coefficientsAttenuation * sky_airmass(position, direction, steps);
}

vec3 sky_transmittance(vec3 position, vec3 direction, const float steps) {
	return exp(-sky_opticalDepth(position, direction, steps) * rLOG2);
}

vec3 calculateAtmosphere(vec3 background, vec3 viewVector, vec3 upVector, vec3 sunVector, vec3 moonVector, out vec2 pid, out vec3 transmittance, const int iSteps, float noise) {
	const int jSteps = 6;

	// darken the ground in the sky.
	#ifdef SKY_GROUND
		float planetGround = exp(-100 * pow(max(-viewVector.y*5 + 0.1,0.0),2));
	#else
		float planetGround = pow(clamp(viewVector.y+1.0,0.0,1.0),2);
	#endif
	
	float GroundDarkening = max(planetGround * 0.75 + 0.25, sunVector.y);

	vec3 viewPos = (sky_planetRadius + eyeAltitude) * upVector;

	vec2 aid = rsi(viewPos, viewVector, sky_atmosphereRadius);
	if (aid.y < 0.0) {transmittance = vec3(1.0); return vec3(0.0);}

	pid = rsi(viewPos, viewVector, sky_planetRadius * 0.998);
	bool planetIntersected = pid.y >= 0.0;

	vec2 sd = vec2((planetIntersected && pid.x < 0.0) ? pid.y : max(aid.x, 0.0), (planetIntersected && pid.x > 0.0) ? pid.x : aid.y);

	float stepSize  = (sd.y - sd.x) * (1.0 / iSteps);
	vec3  increment = viewVector * stepSize;
	vec3  position  = viewVector * sd.x + viewPos;
	position += increment * (0.34*noise);

	vec2 phaseSun = sky_phase(dot(viewVector, sunVector), 0.76);
	vec2 phaseMoon = sky_phase(dot(viewVector, moonVector), 0.76);

	vec3 scatteringSun = vec3(0.0);
	vec3 scatteringMoon = vec3(0.0);
	vec3 scatteringAmbient = vec3(0.0);

	transmittance = vec3(1.0);

	for (int i = 0; i < iSteps; ++i, position += increment) {
		vec3 density = sky_density(length(position));
		if (density.y > 1e35) break;
		vec3 stepAirmass = density * stepSize;
		vec3 stepOpticalDepth = sky_coefficientsAttenuation * stepAirmass;

		vec3 stepTransmittance = exp2(-stepOpticalDepth * rLOG2);
		vec3 stepTransmittedFraction = clamp01((stepTransmittance - 1.0) / -stepOpticalDepth);
		vec3 stepScatteringVisible = transmittance * stepTransmittedFraction * GroundDarkening;

		vec3 sunTrans = sky_transmittance(position, sunVector, jSteps);
		vec3 moonTrans = sky_transmittance(position, moonVector, jSteps);
        
		scatteringSun += rayleighBeta * (stepAirmass.x * phaseSun.x) * stepScatteringVisible * sunTrans;
		scatteringSun += vec3(mieBeta) * (stepAirmass.y * phaseSun.y) * stepScatteringVisible * sunTrans;
        
		scatteringMoon += rayleighBeta * (stepAirmass.x * phaseMoon.x) * stepScatteringVisible * moonTrans;
		scatteringMoon += vec3(mieBeta) * (stepAirmass.y * phaseMoon.y) * stepScatteringVisible * moonTrans;

		scatteringAmbient += sky_coefficientsScattering * stepAirmass.xy * stepScatteringVisible;

		transmittance *= stepTransmittance;
	}

	vec3 scattering = scatteringAmbient * background + scatteringSun * sunColorBase * planetGround + scatteringMoon * moonColorBase * planetGround * 0.5;

	return scattering;
}