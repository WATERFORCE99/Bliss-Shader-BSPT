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

flat out vec2 tempOffsets;

flat out float exposure;
flat out float avgBrightness;
flat out float rodExposure;
flat out float avgL2;
flat out float centerDepth;

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
uniform int worldTime;
uniform int worldDay;
uniform float rainStrength;
uniform float nightVision;

#include "/lib/climate_settings.glsl"
#include "/lib/scene_controller.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/sky_gradient.glsl"
#include "/lib/aurora.glsl"

vec3 rodSample(vec2 Xi) {
	float r = sqrt(1.0 - Xi.x * Xi.y);
	float phi = TAU * Xi.y;

	return normalize(vec3(cos(phi) * r, sin(phi) * r, Xi.x)).xzy;
}

float ld(float depth) {
	return (2.0 * near) / (far + near - depth * (far - near)); // (-depth * (far - near)) = (2.0 * near)/ld - far - near
}

void main() {

	gl_Position = ftransform() * 0.5 + 0.5;
	gl_Position.xy = gl_Position.xy * vec2(18.0 + 258.0 * 2.0, 258.0) * texelSize;
	gl_Position.xy = gl_Position.xy * 2.0 - 1.0;

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
		float maxIT = 20.0;
		for (int i = 0; i < int(maxIT); i++) {
			vec2 ij = R2_samples(((i*50+1)%1000)*int(maxIT)+i) ;//* vec2(0.3183,0.9000);
			vec3 pos = normalize(rodSample(ij)) * vec3(1.0,0.5,1.0) + vec3(0.0,0.5,0.0);

			averageSkyCol_Clouds += skyCloudsFromTex(pos,colortex4).rgb/maxIT/150.0;
			averageSkyCol += 1.5 * skyFromTex(pos,colortex4).rgb/maxIT/150.0;
		}

		vec3 minimumlight = MIN_LIGHT_AMOUNT * vec3(0.01) + nightVision * 0.05;

		// luminance based reinhard is useful ouside of tonemapping too.
		averageSkyCol_Clouds = 1.5 * (averageSkyCol_Clouds / (1.0+luma(averageSkyCol_Clouds) * 0.2));

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
		sunColor = sunColorBase/4000.0 * skyAbsorb;
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

		// components are split for readability/user friendliness within this function
		applySceneControllerParameters(
			parameters.smallCumulus.x, parameters.smallCumulus.y, 
			parameters.largeCumulus.x, parameters.largeCumulus.y,
			parameters.altostratus.x, parameters.altostratus.y,
			parameters.fog.x, parameters.fog.y
		);
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

	exposure = max(targetExposure * EXPOSURE_MULTIPLIER, 0.0);

	float currCenterDepth = ld(texture2D(depthtex2, vec2(0.5)*RENDER_SCALE).r);
	centerDepth = mix(sqrt(texelFetch2D(colortex4,ivec2(14,37),0).g/65000.0), currCenterDepth, clamp(DoF_Adaptation_Speed*exp(-0.016/frameTime+1.0)/(6.0+currCenterDepth*far),0.0,1.0));
	centerDepth = centerDepth * centerDepth * 65000.0;

	rodExposure = targetrodExposure;

	#ifndef AUTO_EXPOSURE
	 	exposure = Manual_exposure_value;
	 	rodExposure = clamp(log(Manual_exposure_value*2.0+1.0)-0.1,0.0,2.0);
	#endif
}