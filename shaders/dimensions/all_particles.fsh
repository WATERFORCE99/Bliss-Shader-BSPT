#include "/lib/settings.glsl"
#include "/lib/util.glsl"

#ifdef IS_LPV_ENABLED
	#extension GL_EXT_shader_image_load_store: enable
	#extension GL_ARB_shading_language_packing: enable
#endif

#include "/lib/res_params.glsl"

in vec4 lmtexcoord;
in vec4 color;

#ifdef LINES
	flat in int SELECTION_BOX;
#endif

#ifdef OVERWORLD_SHADER
	const bool shadowHardwareFiltering = true;
	uniform sampler2DShadow shadow;
	
	#ifdef TRANSLUCENT_COLORED_SHADOWS
		uniform sampler2D shadowcolor0;
		uniform sampler2DShadow shadowtex0;
		uniform sampler2DShadow shadowtex1;
	#endif

	flat in vec3 WsunVec;

	flat in vec3 averageSkyCol_Clouds;
	flat in vec4 lightCol;
#endif

uniform int renderStage;
uniform int isEyeInWater;

uniform sampler2D texture;
uniform sampler2D colortex4;
uniform sampler2D noisetex;

#ifdef IS_LPV_ENABLED
	uniform usampler1D texBlockData;
	uniform sampler3D texLpv1;
	uniform sampler3D texLpv2;
#endif

uniform int frameCounter;
uniform float frameTimeCounter;
#include "/lib/Shadow_Params.glsl"

uniform vec2 texelSize;

uniform ivec2 eyeBrightnessSmooth;
uniform float rainStrength;
uniform float waterEnteredAltitude;
uniform float nightVision;

flat in float HELD_ITEM_BRIGHTNESS;

#include "/lib/projections.glsl"

#ifdef OVERWORLD_SHADER
	uniform int worldDay;
	uniform int worldTime;

	#include "/lib/scene_controller.glsl"
	#define CLOUDSHADOWSONLY
	#include "/lib/volumetricClouds.glsl"
#endif

#ifdef IS_LPV_ENABLED
	uniform int heldItemId;
	uniform int heldItemId2;

	#include "/lib/hsv.glsl"
	#include "/lib/lpv_common.glsl"
	#include "/lib/lpv_render.glsl"
#endif

#include "/lib/diffuse_lighting.glsl"
#include "/lib/sky_gradient.glsl"

uniform int framemod8;
#include "/lib/TAA_jitter.glsl"

//Mie phase function
float phaseg(float x, float g){
	float gg = g * g;
	return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14;
}

// #undef BASIC_SHADOW_FILTER
#ifdef OVERWORLD_SHADER
	float ComputeShadowMap(inout vec3 directLightColor, vec3 playerPos, float maxDistFade){

		// if(maxDistFade <= 0.0) return 1.0;

		// setup shadow projection
		vec3 projectedShadowPosition = toShadowSpaceProjected(playerPos);

		// un-distort
		float distortFactor = 1.0;
		#ifdef DISTORT_SHADOWMAP
			distortFactor = calcDistort(projectedShadowPosition.xy);
			projectedShadowPosition.xy *= distortFactor;
		#endif

		// hamburger
		projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5);

		#ifdef LPV_SHADOWS
			projectedShadowPosition.xy *= 0.8;
		#endif

		float shadowmap = 0.0;
		vec3 translucentTint = vec3(0.0);

		#ifdef TRANSLUCENT_COLORED_SHADOWS

			// determine when opaque shadows are overlapping translucent shadows by getting the difference of opaque depth and translucent depth
			float shadowDepthDiff = pow(clamp((shadow2D(shadowtex1, projectedShadowPosition).x - projectedShadowPosition.z) * 2.0,0.0,1.0),2.0);

			// get opaque shadow data to get opaque data from translucent shadows.
			float opaqueShadow = shadow2D(shadowtex0, projectedShadowPosition).x;
			shadowmap += max(opaqueShadow, shadowDepthDiff);

			// get translucent shadow data
			vec4 translucentShadow = texture2D(shadowcolor0, projectedShadowPosition.xy);

			// this curve simply looked the nicest. it has no other meaning.
			float shadowAlpha = pow(1.0 - pow(translucentShadow.a,5.0),0.2);

			// normalize the color to remove luminance, and keep the hue. remove all opaque color.
			// mulitply shadow alpha to shadow color, but only on surfaces facing the lightsource. this is a tradeoff to protect subsurface scattering's colored shadow tint from shadow bias on the back of the caster.
			translucentShadow.rgb = max(normalize(translucentShadow.rgb + 0.0001), max(opaqueShadow, 1.0-shadowAlpha)) * shadowAlpha;

			// make it such that full alpha areas that arent in a shadow have a value of 1.0 instead of 0.0
			translucentTint += mix(translucentShadow.rgb, vec3(1.0),  opaqueShadow*shadowDepthDiff);

			// tint the lightsource color with the translucent shadow color
			directLightColor *= mix(vec3(1.0), translucentTint.rgb, maxDistFade);
		#else
			shadowmap += shadow2D(shadow, projectedShadowPosition).x;
		#endif

		return shadowmap;
		// return mix(1.0, shadowmap, maxDistFade);
	}
#endif

#if defined DAMAGE_BLOCK_EFFECT && defined POM
	#extension GL_ARB_shader_texture_lod : enable

	const float MAX_OCCLUSION_DISTANCE = MAX_DIST;
	const float MIX_OCCLUSION_DISTANCE = MAX_DIST*0.9;
	const int MAX_OCCLUSION_POINTS = MAX_ITERATIONS;

	in vec4 vtexcoordam; // .st for add, .pq for mul
	in vec4 vtexcoord;

	vec2 dcdx = dFdx(vtexcoord.st*vtexcoordam.pq)*exp2(Texture_MipMap_Bias);
	vec2 dcdy = dFdy(vtexcoord.st*vtexcoordam.pq)*exp2(Texture_MipMap_Bias);

	const float mincoord = 1.0/4096.0;
	const float maxcoord = 1.0-mincoord;

	uniform sampler2D normals;
	in vec4 tangent;
	in vec4 normalMat;

	vec4 readNormal(in vec2 coord) {
		return texture2DGradARB(normals,fract(coord)*vtexcoordam.pq+vtexcoordam.st,dcdx,dcdy);
	}
	vec4 readTexture(in vec2 coord) {
		return texture2DGradARB(texture,fract(coord)*vtexcoordam.pq+vtexcoordam.st,dcdx,dcdy);
	}
#endif

uniform float near;
// uniform float far;
float ld(float dist) {
	return (2.0 * near) / (far + near - dist * (far - near));
}

vec4 texture2D_POMSwitch(
	sampler2D sampler, 
	vec2 lightmapCoord,
	vec4 dcdxdcdy
) {
	return texture2DGradARB(sampler, lightmapCoord, dcdxdcdy.xy, dcdxdcdy.zw);
}

uniform vec3 eyePosition;

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

#ifdef DAMAGE_BLOCK_EFFECT
	/* RENDERTARGETS:11 */
#else
	/* RENDERTARGETS:2,9,11,7 */
#endif

void main() {
	
#ifdef DAMAGE_BLOCK_EFFECT
	vec2 adjustedTexCoord = lmtexcoord.xy;
	#ifdef POM
		vec3 fragpos = toScreenSpace(gl_FragCoord.xyz*vec3(texelSize/RENDER_SCALE,1.0)-vec3(0.0));
		vec3 worldpos = toWorldSpaceCamera(fragpos);

		vec3 normal = normalMat.xyz;
		vec3 tangent2 = normalize(cross(tangent.rgb,normal)*tangent.w);
		mat3 tbnMatrix = mat3(tangent.x, tangent2.x, normal.x,
							  tangent.y, tangent2.y, normal.y,
							  tangent.z, tangent2.z, normal.z);

		adjustedTexCoord = fract(vtexcoord.st)*vtexcoordam.pq+vtexcoordam.st;
		vec3 viewVector = normalize(tbnMatrix*fragpos);

		float dist = length(fragpos);

		float maxdist = MAX_OCCLUSION_DISTANCE;
		if (dist < maxdist) {

			float depthmap = readNormal(vtexcoord.st).a;
			float used_POM_DEPTH = 1.0;

	 		if (viewVector.z < 0.0 && depthmap < 0.9999 && depthmap > 0.00001) {	

				#ifdef Adaptive_Step_length
					vec3 interval = (viewVector.xyz/-viewVector.z/MAX_OCCLUSION_POINTS * POM_DEPTH) * clamp(1.0-pow(depthmap,2),0.1,1.0);
					used_POM_DEPTH = 1.0;
				#else
					vec3 interval = viewVector.xyz/-viewVector.z/MAX_OCCLUSION_POINTS * POM_DEPTH;
				#endif
				vec3 coord = vec3(vtexcoord.st, 1.0);

				coord += interval * used_POM_DEPTH;

				float sumVec = 0.5;
				for (int loopCount = 0; (loopCount < MAX_OCCLUSION_POINTS) && (1.0 - POM_DEPTH + POM_DEPTH * readNormal(coord.st).a  ) < coord.p  && coord.p >= 0.0; ++loopCount) {
					coord = coord + interval * used_POM_DEPTH; 
					sumVec += used_POM_DEPTH; 
				}

				if (coord.t < mincoord) {
					if (readTexture(vec2(coord.s,mincoord)).a == 0.0) {
						coord.t = mincoord;
						discard;
					}
				}

				adjustedTexCoord = mix(fract(coord.st)*vtexcoordam.pq+vtexcoordam.st, adjustedTexCoord, max(dist-MIX_OCCLUSION_DISTANCE,0.0)/(MAX_OCCLUSION_DISTANCE-MIX_OCCLUSION_DISTANCE));
			}
		}

		vec4 Albedo = texture2D_POMSwitch(texture, adjustedTexCoord.xy, vec4(dcdx,dcdy));
	#else
		vec4 Albedo = texture2D(texture, adjustedTexCoord.xy);
	#endif
	
	Albedo.rgb = toLinear(Albedo.rgb);

	if(dot(Albedo.rgb, vec3(0.33333)) < 1.0/255.0 || Albedo.a < 0.01 ) { discard; return; }
	
	gl_FragData[0] = vec4(encodeVec2(vec2(0.5)), encodeVec2(Albedo.rg), encodeVec2(vec2(Albedo.b,0.02)), 1.0);
#else
	gl_FragData[2] = vec4(0.0);

	#if defined LINES && !defined SELECT_BOX
		if(SELECTION_BOX > 0) discard;
	#endif

	vec2 tempOffset = offsets[framemod8];
	vec3 viewPos = toScreenSpace(gl_FragCoord.xyz*vec3(texelSize/RENDER_SCALE,1.0)-vec3(vec2(tempOffset)*texelSize*0.5,0.0));
	vec3 feetPlayerPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 feetPlayerPos_normalized = normalize(feetPlayerPos);
	vec3 worldPos = feetPlayerPos + cameraPosition;

	vec4 TEXTURE = texture2D(texture, lmtexcoord.xy)*color;
	
	#ifdef WhiteWorld
		TEXTURE.rgb = vec3(0.5);
	#endif

	vec3 Albedo = toLinear(TEXTURE.rgb);

	vec2 lightmap = clamp(lmtexcoord.zw,0.0,1.0);

	#ifndef OVERWORLD_SHADER
		lightmap.y = 1.0;
	#endif

	#if defined Hand_Held_lights && !defined LPV_ENABLED
		#ifdef IS_IRIS
			vec3 playerCamPos = eyePosition;
		#else
			vec3 playerCamPos = cameraPosition;
		#endif

		if(HELD_ITEM_BRIGHTNESS > 0.0){ 
			float pointLight = clamp(1.0-(length(worldPos-playerCamPos)-1.0)/HANDHELD_LIGHT_RANGE,0.0,1.0);
			lightmap.x = mix(lightmap.x, HELD_ITEM_BRIGHTNESS, pointLight * pointLight);
		}

	#endif

	#ifdef WEATHER
		gl_FragData[1] = vec4(0.0,0.0,0.0,TEXTURE.a); // for bloomy rain and stuff
	#else
		#ifndef LINES
			gl_FragData[0].a = TEXTURE.a;
		#else
			gl_FragData[0].a = color.a;
		#endif
		#ifndef BLOOMY_PARTICLES
			gl_FragData[1].a = 0.0; // for bloomy rain and stuff
		#endif

		gl_FragData[3] = vec4(0.0,0.0,0.0,0.4);

		vec3 Direct_lighting = vec3(0.0);
		vec3 directLightColor = vec3(0.0);

		vec3 Indirect_lighting = vec3(0.0);
		vec3 AmbientLightColor = vec3(0.0);
		vec3 Torch_Color = vec3(TORCH_R,TORCH_G,TORCH_B);
		vec3 MinimumLightColor = vec3(1.0);

		if(lightmap.x >= 0.9) Torch_Color *= LIT_PARTICLE_BRIGHTNESS;

		#ifdef OVERWORLD_SHADER
			directLightColor =  lightCol.rgb/2400.0;
			AmbientLightColor = averageSkyCol_Clouds / 900.0;

			#ifdef USE_CUSTOM_DIFFUSE_LIGHTING_COLORS
				directLightColor = luma(directLightColor) * vec3(DIRECTLIGHT_DIFFUSE_R,DIRECTLIGHT_DIFFUSE_G,DIRECTLIGHT_DIFFUSE_B);
				AmbientLightColor = luma(AmbientLightColor) * vec3(INDIRECTLIGHT_DIFFUSE_R,INDIRECTLIGHT_DIFFUSE_G,INDIRECTLIGHT_DIFFUSE_B);
			#endif

			float Shadows = 1.0;

			vec3 shadowPlayerPos = toWorldSpace(viewPos);

			float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(shadowPlayerPos) / (shadowDistance+16),0.0)*5.0,1.0));
			float shadowMapFalloff2 = smoothstep(0.0, 1.0, min(max(1.0 - length(shadowPlayerPos) / (shadowDistance+11),0.0)*5.0,1.0));

			float LM_shadowMapFallback = min(max(lightmap.y-0.8, 0.0) * 25,1.0);

			Shadows = ComputeShadowMap(directLightColor, shadowPlayerPos, shadowMapFalloff);

			Shadows *= mix(LM_shadowMapFallback, 1.0, shadowMapFalloff2);

			Shadows *= getCloudShadow(worldPos, WsunVec);

			if(isEyeInWater == 1){
	  			float distanceFromWaterSurface = max(-(feetPlayerPos.y + (cameraPosition.y - waterEnteredAltitude)),0.0) ;
				directLightColor *= exp(-vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B) * distanceFromWaterSurface);
			}
			Direct_lighting = directLightColor * Shadows;

			// #ifndef LINES
				// Direct_lighting *= phaseg(clamp(dot(feetPlayerPos_normalized, WsunVec),0.0,1.0), 0.65)*2 + 0.5;
			// #endif

			#ifdef IS_IRIS
				AmbientLightColor *= 2.5;
			#else
				AmbientLightColor *= 0.5;
			#endif
			
			Indirect_lighting = doIndirectLighting(AmbientLightColor, MinimumLightColor, lightmap.y);
		#endif
		
		#ifdef NETHER_SHADER
			Indirect_lighting = volumetricsFromTex(vec3(0.0,1.0,0.0), colortex4, 6).rgb / 1200.0;
		#endif

		#ifdef END_SHADER
			Indirect_lighting = vec3(0.3,0.6,1.0) * 0.1;
		#endif

	///////////////////////// BLOCKLIGHT LIGHTING OR LPV LIGHTING OR FLOODFILL COLORED LIGHTING
		#ifdef IS_LPV_ENABLED
			vec3 lpvPos = GetLpvPosition(feetPlayerPos);
		#else
			const vec3 lpvPos = vec3(0.0);
		#endif

		Indirect_lighting += doBlockLightLighting(vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, feetPlayerPos, lpvPos, mat3(gbufferModelViewInverse)*vec3(0,1,0));

		#ifdef LINES
			gl_FragData[0].rgb = (Indirect_lighting + Direct_lighting) * toLinear(color.rgb);

			#if defined SELECT_BOX && (SELECTION_BOX > 0)
				gl_FragData[0].rgba = vec4(toLinear(vec3(SELECT_BOX_COL_R, SELECT_BOX_COL_G, SELECT_BOX_COL_B)), 1.0);
			#endif

			float LITEMATICA_SCHEMATIC_THING_MASK = 0.0;
			if (renderStage == MC_RENDER_STAGE_NONE){
				LITEMATICA_SCHEMATIC_THING_MASK = 0.1;
				gl_FragData[0] = vec4(toLinear(color.rgb), color.a);
			}
 
			gl_FragData[2] = vec4(encodeVec2(vec2(0.0)), encodeVec2(vec2(0.0)), encodeVec2(vec2(0.0)), encodeVec2(0.0, LITEMATICA_SCHEMATIC_THING_MASK));
		#else
			gl_FragData[0].rgb = (Indirect_lighting + Direct_lighting) * Albedo;
		#endif

		// distance fade targeting the world border...
		if(TEXTURE.a < 0.7 && TEXTURE.a > 0.2) gl_FragData[0] *= clamp(1.0 - length(feetPlayerPos) / 100.0 ,0.0,1.0);

		gl_FragData[0].rgb *= 0.1;
	#endif
#endif
}