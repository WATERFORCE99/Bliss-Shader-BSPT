#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/util.glsl"

// uniform int dhRenderDistance;
uniform float frameTimeCounter;
#include "/lib/Shadow_Params.glsl"

flat out vec3 averageSkyCol_Clouds;
flat out vec3 averageSkyCol;

flat out vec3 sunColor;
flat out vec3 moonColor;
flat out vec3 lightSourceColor;
flat out vec3 zenithColor;

flat out vec2 tempOffsets;

flat out float exposure;
flat out float avgBrightness;
flat out float rodExposure;
flat out float avgL2;
flat out float centerDepth;

#include "/lib/scene_controller.glsl"

uniform int hideGUI;

uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec2 texelSize;
uniform float sunElevation;
uniform float eyeAltitude;
uniform float near;
// uniform float far;
uniform float frameTime;
uniform int frameCounter;
// uniform float rainStrength;

#include "/lib/sky_gradient.glsl"
#include "/lib/ROBOBO_sky.glsl"
#include "/lib/climate_settings.glsl"
#include "/lib/aurora.glsl"

vec3 rodSample(vec2 Xi) {
	float r = sqrt(1.0f - Xi.x*Xi.y);
	float phi = 2 * 3.14159265359 * Xi.y;

	return normalize(vec3(cos(phi) * r, sin(phi) * r, Xi.x)).xzy;
}

float tanh(float x) {
	return (exp(x) - exp(-x))/(exp(x) + exp(-x));
}

float ld(float depth) {
	return (2.0 * near) / (far + near - depth * (far - near)); // (-depth * (far - near)) = (2.0 * near)/ld - far - near
}

uniform float nightVision;

void getWeatherParams(
	inout vec4 weatherParams0,
	inout vec4 weatherParams1,

	float layer0_coverage,
	float layer1_coverage,
	float layer2_coverage,
	float uniformFog_density,

	float layer0_density,
	float layer1_density,
	float layer2_density,
	float cloudyFog_density
){
	weatherParams0 = vec4(layer0_coverage, layer1_coverage, layer2_coverage, uniformFog_density);
	weatherParams1 = vec4(layer0_density, layer1_density, layer2_density, cloudyFog_density);
}

void main() {

	gl_Position = ftransform()*0.5+0.5;
	gl_Position.xy = gl_Position.xy*vec2(18.+258*2,258.)*texelSize;
	gl_Position.xy = gl_Position.xy*2.-1.0;

	#ifdef OVERWORLD_SHADER
		vec3 sunVec = normalize(mat3(gbufferModelViewInverse) * sunPosition);

///////////////////////////////////
/// --- AMBIENT LIGHT STUFF --- ///
///////////////////////////////////

		averageSkyCol_Clouds = vec3(0.0);
		averageSkyCol = vec3(0.0);

		vec2 sample3x3[9] = vec2[](
			vec2(-1.0, -0.3),
			vec2( 0.0,  0.0),
			vec2( 1.0, -0.3),

			vec2(-1.0, -0.5),
			vec2( 0.0, -0.5),
			vec2( 1.0, -0.5),

			vec2(-1.0, -1.0),
			vec2( 0.0, -1.0),
			vec2( 1.0, -1.0)
   		);

		// sample in a 3x3 pattern to get a good area for average color
	
		int maxIT = 9;
		// int maxIT = 20;
		for (int i = 0; i < maxIT; i++) {
			vec3 pos = vec3(0.0,1.0,0.0);
			pos.xy += normalize(sample3x3[i]) * vec2(0.3183,0.9000);

			averageSkyCol_Clouds += 1.5 * (skyCloudsFromTex(pos,colortex4).rgb/maxIT/150.0);
			averageSkyCol += 1.5 * (skyFromTex(pos,colortex4).rgb/maxIT/150.0);
   		}
	
		// maximum control of color and luminance
		// vec3 minimumlight =  vec3(0.5,0.75,1.0) * nightVision;
		// averageSkyCol_Clouds = max(normalize(averageSkyCol_Clouds) * min(luma(averageSkyCol_Clouds) * 3.0,2.5) * (1.0-rainStrength*0.7), minimumlight);

		vec3 minimumlight = MIN_LIGHT_AMOUNT * vec3(0.01) + nightVision * 0.05;
		averageSkyCol_Clouds = max(normalize(averageSkyCol_Clouds + 1e-6) * min(luma(averageSkyCol_Clouds) * 3.0,2.5),0.0);
		averageSkyCol = max(averageSkyCol * PLANET_GROUND_BRIGHTNESS,0.0) + minimumlight;

		#ifdef USE_CUSTOM_SKY_GROUND_LIGHTING_COLORS
			averageSkyCol = luma(averageSkyCol) * vec3(SKY_GROUND_R,SKY_GROUND_G,SKY_GROUND_B);
		#endif

////////////////////////////////////////
/// --- SUNLIGHT/MOONLIGHT STUFF --- ///
////////////////////////////////////////

		vec2 planetSphere = vec2(0.0);
		vec3 skyAbsorb = vec3(0.0);

		float sunVis = clamp(sunElevation,0.0,0.05)/0.05*clamp(sunElevation,0.0,0.05)/0.05;
		float moonVis = clamp(-sunElevation,0.0,0.05)/0.05*clamp(-sunElevation,0.0,0.05)/0.05;

		sunColor = calculateAtmosphere(vec3(0.0), sunVec, vec3(0.0,1.0,0.0), sunVec, -sunVec, planetSphere, skyAbsorb, 25,0.0);
		sunColor = sunColorBase/4000.0 * skyAbsorb * vec3(1-0.1 * Evening, 1-0.85 * Evening, 1-0.8 * Evening);
		moonColor = moonColorBase/4000.0;

		// lightSourceColor = sunVis >= 1e-5 ? sunColor * sunVis : moonColor * moonVis;
		lightSourceColor = sunColor * sunVis + moonColor * moonVis;

		#ifdef TWILIGHT_FOREST_FLAG
			lightSourceColor = vec3(0.0);
			moonColor = vec3(0.0);
		#endif

///////////////////////////////////////////
 /// --- SCENE CONTROLLER PARAMETERS --- ///
 ///////////////////////////////////////////

		parameters.smallCumulus = vec2(CloudLayer0_coverage, CloudLayer0_density);
		parameters.largeCumulus = vec2(CloudLayer1_coverage, CloudLayer1_density);
		parameters.altostratus = vec2(CloudLayer2_coverage, CloudLayer2_density);
		parameters.fog = vec2(1.0, 1.0);

		#ifdef Daily_Weather
			#ifdef CHOOSE_RANDOM_WEATHER_PROFILE
				int dayCounter = int(clamp(hash11(float(mod(worldDay, 1000))) * 10.0, 0,10));
			#else
				int dayCounter = int(mod(worldDay, 10));
			#endif

			//----------- cloud coverage
			vec3 weatherProfile_cloudCoverage[10] = vec3[](
				vec3(DAY0_l0_coverage, DAY0_l1_coverage, DAY0_l2_coverage),
				vec3(DAY1_l0_coverage, DAY1_l1_coverage, DAY1_l2_coverage),
				vec3(DAY2_l0_coverage, DAY2_l1_coverage, DAY2_l2_coverage),
				vec3(DAY3_l0_coverage, DAY3_l1_coverage, DAY3_l2_coverage),
				vec3(DAY4_l0_coverage, DAY4_l1_coverage, DAY4_l2_coverage),
				vec3(DAY5_l0_coverage, DAY5_l1_coverage, DAY5_l2_coverage),
				vec3(DAY6_l0_coverage, DAY6_l1_coverage, DAY6_l2_coverage),
				vec3(DAY7_l0_coverage, DAY7_l1_coverage, DAY7_l2_coverage),
				vec3(DAY8_l0_coverage, DAY8_l1_coverage, DAY8_l2_coverage),
				vec3(DAY9_l0_coverage, DAY9_l1_coverage, DAY9_l2_coverage)
			);

			//----------- cloud density
			vec3 weatherProfile_cloudDensity[10] = vec3[](
				vec3(DAY0_l0_density, DAY0_l1_density, DAY0_l2_density),
				vec3(DAY1_l0_density, DAY1_l1_density, DAY1_l2_density),
				vec3(DAY2_l0_density, DAY2_l1_density, DAY2_l2_density),
				vec3(DAY3_l0_density, DAY3_l1_density, DAY3_l2_density),
				vec3(DAY4_l0_density, DAY4_l1_density, DAY4_l2_density),
				vec3(DAY5_l0_density, DAY5_l1_density, DAY5_l2_density),
				vec3(DAY6_l0_density, DAY6_l1_density, DAY6_l2_density),
				vec3(DAY7_l0_density, DAY7_l1_density, DAY7_l2_density),
				vec3(DAY8_l0_density, DAY8_l1_density, DAY8_l2_density),
				vec3(DAY9_l0_density, DAY9_l1_density, DAY9_l2_density)
			);

			for (int i = 0; i < 10; i++) {
				weatherProfile_cloudCoverage[i] *= vec3(CloudLayer0_coverage, CloudLayer1_coverage, CloudLayer2_coverage);
				weatherProfile_cloudDensity[i] *= vec3(CloudLayer0_density, CloudLayer1_density, CloudLayer2_density);
			}

			vec3 getWeatherProfile_coverage = weatherProfile_cloudCoverage[dayCounter];
			vec3 getWeatherProfile_density = weatherProfile_cloudDensity[dayCounter];

			parameters.smallCumulus = vec2(getWeatherProfile_coverage.x, getWeatherProfile_density.x);
			parameters.largeCumulus = vec2(getWeatherProfile_coverage.y, getWeatherProfile_density.y);
			parameters.altostratus =  vec2(getWeatherProfile_coverage.z, getWeatherProfile_density.z);

			//----------- fog density
			vec2 weatherProfile_fogDensity[10] = vec2[](
				vec2(DAY0_ufog_density, DAY0_cfog_density),
				vec2(DAY1_ufog_density, DAY1_cfog_density),
				vec2(DAY2_ufog_density, DAY2_cfog_density),
				vec2(DAY3_ufog_density, DAY3_cfog_density),
				vec2(DAY4_ufog_density, DAY4_cfog_density),
				vec2(DAY5_ufog_density, DAY5_cfog_density),
				vec2(DAY6_ufog_density, DAY6_cfog_density),
				vec2(DAY7_ufog_density, DAY7_cfog_density),
				vec2(DAY8_ufog_density, DAY8_cfog_density),
				vec2(DAY9_ufog_density, DAY9_cfog_density)
			);

			parameters.fog = weatherProfile_fogDensity[dayCounter];
		#endif
	#endif

//////////////////////////////
/// --- EXPOSURE STUFF --- ///
//////////////////////////////

	float avgLuma = 0.0;
	float m2 = 0.0;
	int n=100;
	vec2 clampedRes = max(1.0/texelSize,vec2(1920.0,1080.));
	float avgExp = 0.0;
	float avgB = 0.0;
	vec2 resScale = vec2(1920.,1080.)/clampedRes;
	const int maxITexp = 50;
	float w = 0.0;
	for (int i = 0; i < maxITexp; i++){
		vec2 ij = R2_samples((frameCounter%2000)*maxITexp+i);
		vec2 tc = 0.5 + (ij-0.5) * 0.7;
		vec3 sp = texture2D(colortex6, tc/16. * resScale+vec2(0.375*resScale.x+4.5*texelSize.x,.0)).rgb;
		avgExp += log(sqrt(luma(sp)));
		avgB += log(min(dot(sp,vec3(0.07,0.22,0.71)),8e-2));
	}

	avgExp = exp(avgExp/maxITexp);
	avgB = exp(avgB/maxITexp);

	avgBrightness = clamp(mix(avgExp,texelFetch2D(colortex4,ivec2(10,37),0).g,0.95),0.00003051757,65000.0);

	float L = max(avgBrightness,1e-8);
	float keyVal = 1.03-2.0/(log(L*4000/150.*8./3.0+1.0)/log(10.0)+2.0);
	float expFunc = 0.5+0.5*tanh(log(L));
	
	// float targetExposure = 1.0/log(L+1.05);
	float targetExposure = (EXPOSURE_DARKENING * 0.35)/log(L+1.0 + EXPOSURE_BRIGHTENING * 0.05);
	// float targetExposure = 0.18/log2(L*2.5+1.045)*0.62; // choc original

	avgL2 = clamp(mix(avgB,texelFetch2D(colortex4,ivec2(10,37),0).b,0.985),0.00003051757,65000.0);
	float targetrodExposure = max(0.012/log2(avgL2+1.002)-0.1,0.0)*1.2;

	exposure = max(targetExposure, 0.0);

	float currCenterDepth = ld(texture2D(depthtex2, vec2(0.5)*RENDER_SCALE).r);
	centerDepth = mix(sqrt(texelFetch2D(colortex4,ivec2(14,37),0).g/65000.0), currCenterDepth, clamp(DoF_Adaptation_Speed*exp(-0.016/frameTime+1.0)/(6.0+currCenterDepth*far),0.0,1.0));
	centerDepth = centerDepth * centerDepth * 65000.0;

	rodExposure = targetrodExposure;

	#ifndef AUTO_EXPOSURE
	 	exposure = Manual_exposure_value;
	 	rodExposure = clamp(log(Manual_exposure_value*2.0+1.0)-0.1,0.0,2.0);
	#endif
}