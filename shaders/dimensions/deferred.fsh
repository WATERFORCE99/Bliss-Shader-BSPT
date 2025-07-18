#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/dither.glsl"

flat in vec3 averageSkyCol_Clouds;
flat in vec3 averageSkyCol;

flat in vec3 lightSourceColor;
flat in vec3 sunColor;
flat in vec3 moonColor;
// flat in vec3 zenithColor;
// flat in vec3 rayleighAborbance; 

flat in vec2 tempOffsets;

flat in float exposure;
flat in float avgBrightness;
flat in float rodExposure;
flat in float avgL2;
flat in float centerDepth;

uniform sampler2D colortex1;
uniform sampler2D colortex4;

uniform float frameTime;
uniform float frameTimeCounter;
uniform int worldTime;
uniform int worldDay;
uniform float rainStrength;
uniform float eyeAltitude;
uniform vec3 sunVec;
uniform vec2 texelSize;
uniform mat4 shadowModelViewI;
uniform float sunElevation;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform ivec2 eyeBrightnessSmooth;
// uniform ivec2 eyeBrightness;
uniform float caveDetection;
uniform int isEyeInWater;
uniform float nightVision;

vec4 lightCol = vec4(lightSourceColor, float(sunElevation > 1e-5)*2-1.);

#include "/lib/Shadow_Params.glsl"
#include "/lib/waterBump.glsl"

#include "/lib/projections.glsl"
#include "/lib/DistantHorizons_projections.glsl"

#include "/lib/scene_controller.glsl"
#include "/lib/ROBOBO_sky.glsl"
#include "/lib/sky_gradient.glsl"
vec3 WsunVec = mat3(gbufferModelViewInverse) * sunVec;

#define DHVLFOG

uniform float near;

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
	return (near * far) / (depth * (near - far) + far);
}

float invLinZ (float lindepth){
	return -((2.0*near/lindepth)-far-near)/(far-near);
}

#ifdef OVERWORLD_SHADER
	// uniform sampler2D colortex12;
	// const bool shadowHardwareFiltering = true;
	uniform sampler2DShadow shadow;

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		uniform sampler2D shadowcolor0;
		uniform sampler2DShadow shadowtex0;
		uniform sampler2DShadow shadowtex1;
	#endif

	#include "/lib/lightning_stuff.glsl"

	#define VL_CLOUDS_DEFERRED

	#include "/lib/climate_settings.glsl"
	#include "/lib/volumetricClouds.glsl"
	#include "/lib/overworld_fog.glsl"
	#include "/lib/aurora.glsl"
#endif

#ifdef NETHER_SHADER
	#include "/lib/nether_fog.glsl"
#endif

#ifdef END_SHADER
	#include "/lib/end_fog.glsl"
#endif

vec3 rodSample(vec2 Xi){
	float r = sqrt(1.0f - Xi.x*Xi.y);
	float phi = TAU * Xi.y;

	return normalize(vec3(cos(phi) * r, sin(phi) * r, Xi.x)).xzy;
}

uniform bool worldTimeChangeCheck;

uniform int hideGUI;

void main() {
/* DRAWBUFFERS:4 */

	gl_FragData[0] = vec4(0.0);

	float mixhistory = 0.06;

	#ifdef OVERWORLD_SHADER

	//////////////////////////////////////////////
	/// --- STORE DAILY WEATHER PARAMETERS --- ///
	//////////////////////////////////////////////

		// the idea is to store the 8 values, coverage + density of 3 cloud layers and 2 fog density values.

		if (gl_FragCoord.x > 1 && gl_FragCoord.x < 4 && gl_FragCoord.y > 1 && gl_FragCoord.y < 4){
			mixhistory = 10.0 * frameTime;

			gl_FragData[0].rgb = writeSceneControllerParameters(gl_FragCoord.xy, parameters.smallCumulus, parameters.largeCumulus, parameters.altostratus, parameters.fog);
		}

	///////////////////////////////
	/// --- STORE COLOR LUT --- ///
	///////////////////////////////

		vec3 AmbientLightTint = vec3(AmbientLight_R, AmbientLight_G, AmbientLight_B);

		// --- the color of the atmosphere + the average color of the atmosphere.
		vec3 skyGroundCol = skyFromTex(vec3(0, -1 ,0), colortex4).rgb;// * clamp(WsunVec.y*2.0,0.2,1.0);

		/// --- Save light values
		if (gl_FragCoord.x < 1. && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1) {
			gl_FragData[0] = vec4(averageSkyCol_Clouds * AmbientLightTint,1.0);
			if(worldTimeChangeCheck) mixhistory = 1.0;
		}
		if (gl_FragCoord.x > 1. && gl_FragCoord.x < 2.  && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1) {
			gl_FragData[0] = vec4((skyGroundCol/150.0) * AmbientLightTint,1.0);
			if(worldTimeChangeCheck) mixhistory = 1.0;
		}
		#ifdef ambientLight_only
			if (gl_FragCoord.x > 6. && gl_FragCoord.x < 7.  && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1)
				gl_FragData[0] = vec4(0.0,0.0,0.0,1.0);

			if (gl_FragCoord.x > 8. && gl_FragCoord.x < 9.  && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1)
				gl_FragData[0] = vec4(0.0,0.0,0.0,1.0);

			if (gl_FragCoord.x > 13. && gl_FragCoord.x < 14.  && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1)
				gl_FragData[0] = vec4(0.0,0.0,0.0,1.0);
		#else
			if (gl_FragCoord.x > 6. && gl_FragCoord.x < 7.  && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1) {
				gl_FragData[0] = vec4(lightSourceColor,1.0);
				if(worldTimeChangeCheck) mixhistory = 1.0;
			}

			if (gl_FragCoord.x > 8. && gl_FragCoord.x < 9.  && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1) {
				gl_FragData[0] = vec4(sunColor,1.0);
				if(worldTimeChangeCheck) mixhistory = 1.0;
			}

			if (gl_FragCoord.x > 9. && gl_FragCoord.x < 10.  && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1) {
				gl_FragData[0] = vec4(moonColor,1.0);
				if(worldTimeChangeCheck) mixhistory = 1.0;
			}
		#endif

		#if defined FLASHLIGHT && defined FLASHLIGHT_BOUNCED_INDIRECT

			// sample center pixel of albedo color, and interpolate it overtime.
			if (gl_FragCoord.x > 15 && gl_FragCoord.x < 16 && gl_FragCoord.y > 2 && gl_FragCoord.y < 3){

				mixhistory = 0.01;

				vec3 data = texelFetch2D(colortex1, ivec2(0.5/texelSize), 0).rgb;
				vec3 decodeAlbedo = vec3(decodeVec2(data.x).x,decodeVec2(data.y).x, decodeVec2(data.z).x);
				vec3 albedo = toLinear(decodeAlbedo);

				albedo = normalize(albedo + 1e-7) * (dot(albedo,vec3(0.21, 0.72, 0.07))*0.5+0.5);

				gl_FragData[0] = vec4(albedo,1.0);
			}
		#endif

////////////////////////////////
/// --- ATMOSPHERE IMAGE --- ///
////////////////////////////////

/// --- Sky only

		if (gl_FragCoord.x > 18. && gl_FragCoord.y > 1. && gl_FragCoord.x < 18+257){
			vec2 p = clamp(floor(gl_FragCoord.xy-vec2(18.,1.))/256.+tempOffsets/256.,0.0,1.0);
			vec3 viewVector = cartToSphere(p);

			vec2 planetSphere = vec2(0.0);
			vec3 sky = vec3(0.0);
			vec3 skyAbsorb = vec3(0.0);

			vec3 mC = vec3(fog_coefficientMieR*1e-6, fog_coefficientMieG*1e-6, fog_coefficientMieB*1e-6);

			sky = calculateAtmosphere((averageSkyCol*4000.0/2.0), viewVector, vec3(0.0,1.0,0.0), WsunVec, -WsunVec, planetSphere, skyAbsorb, 10, blueNoise());

			// fade atmosphere conditions for rain away when you pass above the cloud plane.
			float heightRelativeToClouds = clamp(1.0 - max(eyeAltitude - CloudLayer0_height,0.0) / 200.0 ,0.0,1.0);
			if(rainStrength > 0.0) sky = mix(sky, 3.0 + averageSkyCol*4000 * (skyAbsorb*0.7+0.3), clamp(1.0 - exp(pow(clamp(-viewVector.y+0.9,0.0,1.0),2) * -5.0),0.0,1.0) * heightRelativeToClouds * rainStrength);
	
			#ifdef AEROCHROME_MODE
				sky *= vec3(0.0, 0.18, 0.35);
			#endif

			gl_FragData[0] = vec4(sky / 4000.0 , 1.0);
  
			if(worldTimeChangeCheck) mixhistory = 1.0;
		}

/// --- Sky + clouds + fog 

		if (gl_FragCoord.x > 18.+257. && gl_FragCoord.y > 1. && gl_FragCoord.x < 18+257+257.){
			vec2 p = clamp(floor(gl_FragCoord.xy-vec2(18.+257,1.))/256.+tempOffsets/256.,0.0,1.0);
			vec3 viewVector = cartToSphere(p);

			vec3 viewPos = mat3(gbufferModelView)*viewVector*1024.0;
			float noise = interleaved_gradientNoise_temporal();

			WsunVec = normalize(toWorldSpace(sunPosition));// * (float(sunElevation > 1e-5)*2.0-1.0);
			vec3 WmoonVec = normalize(toWorldSpace(moonPosition));

			if(dot(-WmoonVec, WsunVec) < 0.9999) WmoonVec = -WmoonVec;

			WsunVec = mix(WmoonVec, WsunVec, clamp(float(sunElevation > 1e-5)*2.0-1.0 ,0,1));

			vec3 sky = texelFetch2D(colortex4,ivec2(gl_FragCoord.xy)-ivec2(257,0),0).rgb/150.0;
			sky = mix(averageSkyCol_Clouds * AmbientLightTint * 0.25, sky,  pow(clamp(viewVector.y+1.0,0.0,1.0),5.0));
	
			vec3 suncol = lightSourceColor;

			#ifdef ambientLight_only
				suncol = vec3(0.0);
			#endif

			float cloudPlaneDistance = 0.0;
 			vec4 volumetricClouds = GetVolumetricClouds(viewPos, vec2(noise, 1.0-noise), WsunVec, suncol*2.5, skyGroundCol/30.0, cloudPlaneDistance);

			float atmosphereAlpha = 1.0;
			vec4 volumetricFog = GetVolumetricFog(viewPos, WsunVec, vec2(noise, 1.0-noise), suncol*2.5, skyGroundCol/30.0, averageSkyCol_Clouds*5.0, atmosphereAlpha, volumetricClouds.rgb, cloudPlaneDistance);

			sky = sky * volumetricClouds.a + volumetricClouds.rgb / 5.0;
			sky = sky * volumetricFog.a + volumetricFog.rgb / 5.0;

			gl_FragData[0] = vec4(sky,1.0);

			if(worldTimeChangeCheck) mixhistory = 1.0;
		}
	#endif

	#if defined NETHER_SHADER || defined END_SHADER
		vec2 fogPos = vec2(256.0 - 256.0*0.12,1.0);

		//Sky gradient with clouds
		if (gl_FragCoord.x > (fogPos.x - fogPos.x*0.22) && gl_FragCoord.y > 0.4 && gl_FragCoord.x < 535){
			vec2 p = clamp(floor(gl_FragCoord.xy-fogPos)/256.+tempOffsets/256.,-0.2,1.2);
			vec3 viewVector = cartToSphere(p);
			float noise = interleaved_gradientNoise_temporal();

	 		vec3 BackgroundColor = vec3(0.0);

			vec4 VL_Fog = GetVolumetricFog(mat3(gbufferModelView)*viewVector*256., noise, 1.0-noise);

			BackgroundColor += VL_Fog.rgb + vec3(0.5,0.75,1.0) * nightVision;

	  		gl_FragData[0] = vec4(BackgroundColor*8.0, 1.0);

		}
	#endif

	#ifdef END_SHADER
	/* ---------------------- TIMER ---------------------- */

		float flash = 0.0;
		float maxWaitTime = 5;

		float Timer = texelFetch2D(colortex4, ivec2(3,1), 0).x/150.0;
		Timer -= frameTime;

		if(Timer <= 0.0){
			flash = 1.0;

			Timer = pow(hash11(frameCounter), 5) * maxWaitTime;
		}

		vec2 pixelPos0 = vec2(3,1);
		if (gl_FragCoord.x > pixelPos0.x && gl_FragCoord.x < pixelPos0.x + 1 && gl_FragCoord.y > pixelPos0.y && gl_FragCoord.y < pixelPos0.y + 1){
			mixhistory = 1.0;
			gl_FragData[0] = vec4(Timer, 0.0, 0.0, 1.0);
		}

	/* ---------------------- FLASHING ---------------------- */

		vec2 pixelPos1 = vec2(1,1);
		if (gl_FragCoord.x > pixelPos1.x && gl_FragCoord.x < pixelPos1.x + 1 && gl_FragCoord.y > pixelPos1.y && gl_FragCoord.y < pixelPos1.y + 1){
			mixhistory = clamp(4.0 * frameTime,0.0,1.0);
			gl_FragData[0] = vec4(flash, 0.0, 0.0, 1.0);
		}

	/* ---------------------- POSITION ---------------------- */

		vec2 pixelPos2 = vec2(2,1);
		if (gl_FragCoord.x > pixelPos2.x && gl_FragCoord.x < pixelPos2.x + 1 && gl_FragCoord.y > pixelPos2.y && gl_FragCoord.y < pixelPos2.y + 1){
			mixhistory = clamp(500.0 * frameTime,0.0,1.0);

			vec3 LastPos = (texelFetch2D(colortex4,ivec2(2,1),0).xyz/150.0) * 2.0 - 1.0;
		
			LastPos += (hash31(frameCounter / 50) * 2.0 - 1.0);
			LastPos = LastPos * 0.5 + 0.5;

			if(Timer > maxWaitTime * 0.7 ){ 
				LastPos = vec3(0.0);
			}

			gl_FragData[0] = vec4(LastPos, 1.0);
		}
	#endif

	//Temporally accumulate sky and light values
	vec3 frameHistory = texelFetch2D(colortex4,ivec2(gl_FragCoord.xy),0).rgb;
	vec3 currentFrame = gl_FragData[0].rgb*150.;

	gl_FragData[0].rgb = clamp(mix(frameHistory, currentFrame, clamp(mixhistory,0.0,1.0)),0.0,65000.);

	//Exposure values
	if (gl_FragCoord.x > 10. && gl_FragCoord.x < 11.  && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1)
		gl_FragData[0] = vec4(exposure, avgBrightness, avgL2,1.0);
	if (gl_FragCoord.x > 14. && gl_FragCoord.x < 15.  && gl_FragCoord.y > 19.+18. && gl_FragCoord.y < 19.+18.+1)
		gl_FragData[0] = vec4(rodExposure, centerDepth,0.0, 1.0);
}