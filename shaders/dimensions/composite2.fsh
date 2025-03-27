#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/dither.glsl"

#define EXCLUDE_WRITE_TO_LUT

flat in vec4 lightCol;
flat in vec3 averageSkyCol;
flat in vec3 averageSkyCol_Clouds;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

#ifdef DISTANT_HORIZONS
	uniform sampler2D dhDepthTex;
	uniform sampler2D dhDepthTex1;
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex10;

flat in vec3 WsunVec;
uniform vec3 sunVec;
uniform float sunElevation;

// uniform float far;
uniform float near;

#ifdef VIVECRAFT
 	uniform bool vivecraftIsVR;
 	uniform vec3 vivecraftRelativeMainHandPos;
 	uniform vec3 vivecraftRelativeOffHandPos;
 	uniform mat4 vivecraftRelativeMainHandRot;
 	uniform mat4 vivecraftRelativeOffHandRot;
 #endif

uniform float frameTimeCounter;

// in vec2 texcoord;
uniform vec2 texelSize;
flat in vec2 TAA_Offset;

uniform int isEyeInWater;
uniform float rainStrength;
uniform ivec2 eyeBrightnessSmooth;
uniform float eyeAltitude;
uniform float caveDetection;

// uniform int dhRenderDistance;
#define DHVLFOG

#include "/lib/tonemaps.glsl"
#include "/lib/color_dither.glsl"
#include "/lib/projections.glsl"
#include "/lib/res_params.glsl"
#include "/lib/sky_gradient.glsl"
#include "/lib/Shadow_Params.glsl"
#include "/lib/waterBump.glsl"

#include "/lib/DistantHorizons_projections.glsl"

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
	return (near * far) / (depth * (near - far) + far);
}

#define IS_LPV_ENABLED

#if defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED
	flat in float exposure;

	#extension GL_ARB_shader_image_load_store: enable
	#extension GL_ARB_shading_language_packing: enable

	uniform usampler1D texBlockData;
	uniform sampler3D texLpv1;
	uniform sampler3D texLpv2;

	#include "/lib/hsv.glsl"
	#include "/lib/lpv_common.glsl"
	#include "/lib/lpv_render.glsl"
#endif

float invLinZ (float lindepth){
	return -((2.0*near/lindepth)-far-near)/(far-near);
}

#ifdef OVERWORLD_SHADER
	const bool shadowHardwareFiltering = true;
	uniform sampler2DShadow shadow;

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		uniform sampler2D shadowcolor0;
		uniform sampler2DShadow shadowtex0;
		uniform sampler2DShadow shadowtex1;
	#endif

	flat in vec3 refractedSunVec;

	flat in vec4 dailyWeatherParams0;
	flat in vec4 dailyWeatherParams1;

	// uniform int dhRenderDistance;
	#define TIMEOFDAYFOG
	// #define CLOUDS_INTERSECT_TERRAIN

	#include "/lib/lightning_stuff.glsl"
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

void waterVolumetrics_notoverworld(inout vec3 inColor, vec3 rayStart, vec3 rayEnd, float estEndDepth, float estSunDepth, float rayLength, float dither, vec3 waterCoefs, vec3 scatterCoef, vec3 ambient){
	inColor *= exp(-rayLength * waterCoefs);	//No need to take the integrated value
	
	int spCount = rayMarchSampleCount;
	vec3 start = toShadowSpaceProjected(toWorldSpace(rayStart));
	vec3 end = toShadowSpaceProjected(toWorldSpace(rayEnd));
	vec3 dV = (end-start);
	//limit ray length at 32 blocks for performance and reducing integration error
	//you can't see above this anyway
	float maxZ = min(rayLength,12.0)/(1e-8+rayLength);
	dV *= maxZ;

	rayLength *= maxZ;
	
	float dY = normalize(mat3(gbufferModelViewInverse) * rayEnd).y * rayLength;
	estEndDepth *= maxZ;
	estSunDepth *= maxZ;

	vec3 wpos = toWorldSpace(rayStart);
	vec3 dVWorld = (wpos-gbufferModelViewInverse[3].xyz);

	vec3 absorbance = vec3(1.0);
	vec3 vL = vec3(0.0);

	float expFactor = 11.0;
	for (int i=0;i<spCount;i++) {
		float d = (pow(expFactor, float(i+dither)/float(spCount))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
		float dd = pow(expFactor, float(i+dither)/float(spCount)) * log(expFactor) / float(spCount)/(expFactor-1.0);
		vec3 spPos = start.xyz + dV*d;

		vec3 progressW = start.xyz+cameraPosition+dVWorld;

		vec3 ambientMul = exp(-max(estEndDepth * d,0.0) * waterCoefs);
		vec3 Indirectlight = ambientMul*ambient;

		vec3 light = Indirectlight * scatterCoef;

		vL += (light - light * exp(-waterCoefs * dd * rayLength)) / waterCoefs * absorbance;
		absorbance *= exp(-dd * rayLength * waterCoefs);
	}
	inColor += vL;
}

uniform float waterEnteredAltitude;

vec4 waterVolumetrics(vec3 rayStart, vec3 rayEnd, float rayLength, vec2 dither, vec3 waterCoefs, vec3 scatterCoef, vec3 ambient, vec3 lightSource, float VdotL){
	int spCount = 8;

	vec3 start = toShadowSpaceProjected(toWorldSpace(rayStart));
	vec3 end = toShadowSpaceProjected(toWorldSpace(rayEnd));
	vec3 dV = (end-start);

	//limit ray length at 32 blocks for performance and reducing integration error
	//you can't see above this anyway
	float maxZ = min(rayLength,32.0)/(1e-8+rayLength);
	
	dV *= maxZ;
	rayLength *= maxZ;

	vec3 dVWorld = mat3(gbufferModelViewInverse) * (rayEnd - rayStart) * maxZ;

	vec3 absorbance = vec3(1.0);
	vec3 vL = vec3(0.0);
	
	#ifdef OVERWORLD_SHADER
		float lowlightlevel  = clamp(eyeBrightnessSmooth.y/240.0,0.1,1.0);
		float phase = fogPhase(VdotL) * 5.0;
	#else
		float lowlightlevel  = 1.0;
		float phase = 0.0;
	#endif

 	float thing = -normalize(dVWorld).y;
 	thing = clamp(thing + 0.333,0.0,1.0);
 	thing = pow(1.0-pow(1.0-thing,2.0),2.0);
 
 	thing *= 15.0;
  
	float expFactor = 11.0;
	for (int i=0;i<spCount;i++) {
		float d = (pow(expFactor, float(i+dither.x)/float(spCount))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);		// exponential step position (0-1)
		float dd = pow(expFactor, float(i+dither.y)/float(spCount)) * log(expFactor) / float(spCount)/(expFactor-1.0);	//step length (derivative)
		
		vec3 progressW = gbufferModelViewInverse[3].xyz + cameraPosition + d*dVWorld;
		
		float distanceFromWaterSurface = max(-(progressW.y - waterEnteredAltitude),0.0);

		vec3 sh = vec3(1.0);
		#ifdef OVERWORLD_SHADER
			vec3 spPos = start.xyz + dV*d;

			//project into biased shadowmap space
			#ifdef DISTORT_SHADOWMAP
				float distortFactor = calcDistort(spPos.xy);
			#else
				float distortFactor = 1.0;
			#endif

			vec3 pos = vec3(spPos.xy*distortFactor, spPos.z);
			if (abs(pos.x) < 1.0-0.5/2048. && abs(pos.y) < 1.0-0.5/2048){
				pos = pos*vec3(0.5,0.5,0.5/6.0)+0.5;

				#ifdef LPV_SHADOWS
					pos.xy *= 0.8;
				#endif

				// sh = shadow2D( shadow, pos).x;

				#ifdef TRANSLUCENT_COLORED_SHADOWS
					sh = vec3(shadow2D(shadowtex0, pos).x);

					if(shadow2D(shadowtex1, pos).x > pos.z && sh.x < 1.0){
						vec4 translucentShadow = texture2D(shadowcolor0, pos.xy);
						if(translucentShadow.a < 0.9) sh = normalize(translucentShadow.rgb+0.0001);
					}
				#else
					sh = vec3(shadow2D(shadow, pos).x);
				#endif
			}

			sh *= GetCloudShadow(progressW, WsunVec * lightCol.a);

		#endif

		float bubble = exp2(-10.0 * clamp(1.0 - length(d*dVWorld) / 16.0, 0.0,1.0));
		float caustics = max(max(waterCaustics(progressW, WsunVec), phase*0.5) * mix(0.5, 1.5, bubble), phase) ;

		vec3 sunAbsorbance = exp(-waterCoefs * (distanceFromWaterSurface/abs(WsunVec.y)));
		vec3 WaterAbsorbance = exp(-waterCoefs * (distanceFromWaterSurface + thing));

		vec3 Directlight = lightSource * sh * phase * caustics * sunAbsorbance;
		vec3 Indirectlight = ambient * WaterAbsorbance;

		vec3 light = (Indirectlight + Directlight) * scatterCoef;
		
		vec3 volumeCoeff = exp(-waterCoefs * length(dd*dVWorld));
		vL += (light - light * volumeCoeff) / waterCoefs * absorbance;
		absorbance *= volumeCoeff;
	}
	return vec4(vL, dot(absorbance,vec3(0.335)));
}

vec4 blueNoise(vec2 coord){
	return texelFetch2D(colortex6, ivec2(coord)%512 , 0) ;
}

float fogPhase2(float lightPoint){
	float linear = 1.0 - clamp(lightPoint*0.5+0.5,0.0,1.0);
	float linear2 = 1.0 - clamp(lightPoint,0.0,1.0);

	float exponential = exp2(pow(linear,0.3) * -15.0 ) * 1.5;
	exponential += sqrt(exp2(sqrt(linear) * -12.5));

	return exponential;
}

uniform int framemod8;
#include "/lib/TAA_jitter.glsl"

float convertHandDepth(float depth) {
	float ndcDepth = depth * 2.0 - 1.0;
	ndcDepth /= MC_HAND_DEPTH;
	return ndcDepth * 0.5 + 0.5;
}

vec3 alterCoords(in vec3 coords, bool lighting){
	float theDistance = length(coords + (lighting ? vec3(0.0) : cameraPosition));

	coords.x = coords.x*3;
	coords.y = coords.y;
	coords.z = coords.z*3;

	return coords;
 }

vec4 raymarchTest(
	in vec3 viewPosition,
	in vec2 dither
){
	
	vec3 color = vec3(0.0);
	float totalAbsorbance = 1.0;
	float expFactor = 16.0;

	float minHeight = 250.0;
	float maxHeight = minHeight + 100.0;
	
	#ifdef DISTANT_HORIZONS
		float maxdist = dhFarPlane - 16.0;
	#else
		float maxdist = far*4;
	#endif

   	float referenceDistance = length(viewPosition) < maxdist ? length(viewPosition) - 1.0 : 100000000.0;

	int SAMPLECOUNT = 8;

	//project pixel position into projected shadowmap space
	vec3 wpos =  toWorldSpace(viewPosition);
	vec3 dVWorld = wpos - gbufferModelViewInverse[3].xyz;
	vec3 dVWorldN = normalize(dVWorld);

	// dVWorld *= dVWorldN/abs(dVWorldN.y);
	// float maxLength = min(length(dVWorld), 16 * 8)/length(dVWorld);
	// dVWorld *= maxLength;

	// float cloudRange = max(minHeight - cameraPosition.y,0.0);
	float cloudRange = max(minHeight - cameraPosition.y, 0.0);

	vec3 rayDirection = dVWorldN.xyz * ((maxHeight - minHeight) / length(alterCoords(dVWorldN, false)) / SAMPLECOUNT);
	
	// float cloudRange = mix(max(cameraPosition.y - maxHeight,0.0), max(minHeight - cameraPosition.y,0.0), clamp(rayDirection.y,0.0,1.0));

	vec3 rayProgress = rayDirection + cameraPosition + (rayDirection / length(alterCoords(rayDirection, false))) * 200.0;

	float dL = length(rayDirection);
	
	// vec3 rayDirection = dVWorldN.xyz * ((maxHeight - minHeight) / abs(dVWorldN.y) / SAMPLECOUNT);
	// float flip = mix(max(cameraPosition.y - maxHeight,0.0), max(minHeight - cameraPosition.y,0.0), clamp(rayDirection.y,0.0,1.0));
	// vec3 rayProgress = rayDirection*dither.x + cameraPosition + (rayDirection / abs(rayDirection.y)) *flip;
	// float dL = length(rayDirection);

	for (int i = 0; i < SAMPLECOUNT; i++) {
		if(length(rayProgress - cameraPosition) > referenceDistance) break;

		float d = (pow(expFactor, float(i + dither.x)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
		float dd = pow(expFactor, float(i + dither.y)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);
		
		float theDistance = length(alterCoords(rayProgress-cameraPosition, true));

		float fogDensity = min(max(texture2D(noisetex, rayProgress.xz/2048).b-0.5,0.0)*2.0,1.0) * clamp((minHeight+50) - theDistance, 0.0, clamp(theDistance-minHeight,0,1));

		float fogVolumeCoeff = exp(-fogDensity*dd*dL);

		// vec3 lighting = vec3(1.0) * (1.0-clamp((minHeight-50) - theDistance,0,1));

		vec3 lighting = vec3(1.0) * clamp(minHeight - theDistance/1.2,0,1);

		color += (lighting - lighting * fogVolumeCoeff) * totalAbsorbance;

		totalAbsorbance *= fogVolumeCoeff;

		rayProgress += rayDirection;
	}
	return vec4(color, totalAbsorbance);
}

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {

	/* RENDERTARGETS:0 */

	float noise_2 = blueNoise();
	float noise_1 = max(1.0 - R2_dither(),0.0015);
	// float noise_2 = interleaved_gradientNoise_temporal();
	vec2 bnoise = blueNoise(gl_FragCoord.xy).rg;

	int seed = (frameCounter*5)%40000;
	vec2 r2_sequence = R2_samples(seed).xy;
	vec2 BN = fract(r2_sequence + bnoise);

	// vec2 tc = floor(gl_FragCoord.xy)/VL_RENDER_RESOLUTION*texelSize + texelSize*0.5;
	vec2 tc = (gl_FragCoord.xy - 0.5)/VL_RENDER_RESOLUTION*texelSize;

	bool iswater = texture2D(colortex7,tc).a > 0.99;

	float depth = texelFetch2D(depthtex0, ivec2(tc/texelSize),0).x;

	float z0 = depth < 0.56 ? convertHandDepth(depth) : depth;

	float DH_z0 = 0.0;
	#ifdef DISTANT_HORIZONS
		DH_z0 = texelFetch2D(dhDepthTex, ivec2(tc/texelSize),0).x;
	#endif

	vec3 viewPos0 = toScreenSpace_DH(tc/RENDER_SCALE, z0, DH_z0);
	vec3 viewPos0_water = toScreenSpace(vec3(tc/RENDER_SCALE, z0));
	vec3 playerPos = toWorldSpace(viewPos0);
	vec3 playerPos_normalized = normalize(playerPos);

	vec3 waterEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
	vec3 dirtEpsilon = vec3(Dirt_Absorb_R, Dirt_Absorb_G, Dirt_Absorb_B);
	vec3 totEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
	vec3 scatterCoef = Dirt_Amount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / 3.14;

	vec3 directLightColor = lightCol.rgb / 2400.0;
	vec3 indirectLightColor = averageSkyCol / 1200.0;
	vec3 indirectLightColor_dynamic = averageSkyCol_Clouds / 1200.0;
	float cloudPlaneDistance = 0.0;

	#ifdef OVERWORLD_SHADER
		vec4 VolumetricClouds = GetVolumetricClouds(viewPos0, BN, WsunVec, directLightColor + aurDirect, indirectLightColor + aurIndirect, cloudPlaneDistance);

		#ifdef CAVE_FOG
  	  		float skyhole = pow(clamp(1.0-pow(max(playerPos_normalized.y - 0.6,0.0)*5.0,2.0),0.0,1.0),2)* caveDetection;
			VolumetricClouds.rgb *= 1.0-skyhole;
			VolumetricClouds.a = mix(VolumetricClouds.a, 1.0,  skyhole);
		#endif

		float atmosphereAlpha = 1.0;

		vec3 sceneColor = texelFetch2D(colortex3,ivec2(tc/texelSize),0).rgb * VolumetricClouds.a + VolumetricClouds.rgb;
		vec4 VolumetricFog = GetVolumetricFog(viewPos0, WsunVec, BN, directLightColor, indirectLightColor, indirectLightColor_dynamic, atmosphereAlpha, VolumetricClouds.rgb, cloudPlaneDistance);
		VolumetricFog = vec4(VolumetricClouds.rgb * VolumetricFog.a  + VolumetricFog.rgb, VolumetricFog.a*VolumetricClouds.a);
	#else
		vec4 VolumetricFog = GetVolumetricFog(viewPos0, BN.x, BN.y);
	#endif

	if (isEyeInWater == 1){
		vec4 underWaterFog =  waterVolumetrics(vec3(0.0), viewPos0_water, length(viewPos0_water), BN, totEpsilon, scatterCoef, indirectLightColor_dynamic, directLightColor , dot(normalize(viewPos0_water), normalize(sunVec* lightCol.a )));

		VolumetricFog = vec4(underWaterFog.rgb, 1.0);
	}

	// VolumetricFog = raymarchTest(viewPos0, BN);

	gl_FragData[0] = clamp(VolumetricFog, 0.0, 65000.0);
}