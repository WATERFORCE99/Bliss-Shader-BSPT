#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/dither.glsl"

flat in vec3 zMults;

flat in vec2 TAA_Offset;
flat in vec3 WsunVec;

#ifdef OVERWORLD_SHADER
	flat in vec3 skyGroundColor;
#endif

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

#ifdef DISTANT_HORIZONS
	uniform sampler2D dhDepthTex;
	uniform sampler2D dhDepthTex1;
#endif

uniform sampler2D colortex0;
// uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
// uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
// uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
// uniform sampler2D colortex13;
// uniform sampler2D colortex14;
// uniform sampler2D colortex15;

uniform vec2 texelSize;
// uniform float viewHeight;
// uniform float viewWidth;
// uniform vec3 sunVec;
uniform float frameTimeCounter;
uniform float far;
uniform float near;
uniform float farPlane;
uniform int dhRenderDistance;

uniform int hideGUI;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform ivec2 eyeBrightness;
uniform float nightVision;
uniform float rainStrength;
uniform float wetness;
uniform float blindness;
uniform float darknessFactor;
uniform float darknessLightFactor;
uniform float caveDetection;
uniform float waterEnteredAltitude;
uniform float fogEnd;
uniform vec3 fogColor;
uniform float eyeAltitude;

#include "/lib/waterBump.glsl"
#include "/lib/res_params.glsl"

#ifdef OVERWORLD_SHADER
	#include "/lib/climate_settings.glsl"
	#include "/lib/rainbow.glsl"
#endif

#include "/lib/sky_gradient.glsl"
#include "/lib/projections.glsl"
#include "/lib/DistantHorizons_projections.glsl"

vec4 blueNoise(vec2 coord){
	return texelFetch2D(colortex6, ivec2(coord)%512 , 0);
}

vec3 normVec(vec3 vec){
	return vec*inversesqrt(dot(vec,vec));
}

float ld(float depth) {
	return 1.0 / (zMults.y - depth * zMults.z); // (-depth * (far - near)) = (2.0 * near)/ld - far - near
}

float linearize(float dist) {
	return (2.0 * near) / (far + near - dist * (far - near));
}

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
	return (near * far) / (depth * (near - far) + far);
}

vec2 clampUV(in vec2 uv, vec2 texcoord){

	// get the gradient when a refracted axis and non refracted axis go above 1.0 or below 0.0
	// use this gradient to lerp between refracted and non refracted uv
	// the goal of this is to stretch the uv back to normal when the refracted image exposes off screen uv
	// emphasis on *stretch*, as i want the transition to remain looking like refraction, not a sharp cut.

	float vignette = max(uv.x * texcoord.x, 0.0);
	vignette = max(uv.y * texcoord.y, vignette);
	vignette = max((uv.x-1.0) * (texcoord.x-1.0), vignette);
	vignette = max((uv.y-1.0) * (texcoord.y-1.0), vignette);

	vignette *= vignette * vignette * vignette * vignette;

	return clamp(mix(uv, texcoord, vignette), 0.0, 0.9999999);
}

vec3 doRefractionEffect(inout vec2 texcoord, vec2 normal, float linearDistance, bool isReflectiveEntity, bool underwater){
  
	// make the tangent space normals match the directions of the texcoord UV, this greatly improves the refraction effect.
	vec2 UVNormal = vec2(normal.x,-normal.y);
  
	float refractionMult = 0.5 / (1.0 + pow(linearDistance,0.8) * (underwater ? 0.1 : 1.0));
	float diffractionMult = 0.035;
	float smudgeMult = 1.0;
	if(isReflectiveEntity) refractionMult *= 0.5;

	// for diffraction, i wanted to know *when* normals were at an angle, not what the
	float clampValue = 0.2;
	vec2 abberationOffset = (clamp(UVNormal,-clampValue, clampValue)/clampValue) * diffractionMult;

	#ifdef REFRACTION_SMUDGE
		vec2 directionalSmudge = abberationOffset * (blueNoise()-0.5) * smudgeMult;
	#else
		vec2 directionalSmudge = vec2(0.0);
	#endif

	vec2 refractedUV_no_offset = clampUV(texcoord - (UVNormal + directionalSmudge)*refractionMult, texcoord);
	vec2 refractedUV = refractedUV_no_offset;

	#ifdef FAKE_DISPERSION_EFFECT
		refractionMult *= min(decodeVec2(texelFetch2D(colortex11, ivec2(clampUV(texcoord - ((UVNormal + abberationOffset) + directionalSmudge) * refractionMult,texcoord)/texelSize),0).b).g,
		decodeVec2(texelFetch2D(colortex11, ivec2(clampUV(texcoord + ((UVNormal + abberationOffset) + directionalSmudge) * refractionMult,texcoord)/texelSize),0).b).g) > 0.0 ? 1.0 : 0.0;
	#else
		refractionMult *= decodeVec2(texelFetch2D(colortex11, ivec2(refractedUV_no_offset/texelSize),0).b).g > 0.0 ? 1.0 : 0.0;
	#endif

	vec3 color = vec3(0.0);

	#ifdef FAKE_DISPERSION_EFFECT
		//// RED
		refractedUV = clampUV(texcoord - ((UVNormal + abberationOffset) + directionalSmudge) * refractionMult, texcoord);
		color.r = texture2D(colortex3, refractedUV).r;
		//// GREEN
		refractedUV = clampUV(texcoord - (UVNormal + directionalSmudge) * refractionMult, texcoord);
		color.g = texture2D(colortex3, refractedUV).g;
		//// BLUE
		refractedUV = clampUV(texcoord - ((UVNormal - abberationOffset) + directionalSmudge) * refractionMult, texcoord);
		color.b = texture2D(colortex3, refractedUV).b;
	#else
		color = texture2D(colortex3, refractedUV_no_offset).rgb;
	#endif

	texcoord = refractedUV_no_offset;
	return color;
}

vec4 bilateralUpsample(out float outerEdgeResults, float referenceDepth, sampler2D depth, bool hand){
	vec4 colorSum = vec4(0.0);
	float edgeSum = 0.0;
	float threshold = 0.005;

	vec2 coord = gl_FragCoord.xy - 1.5;

	vec2 UV = coord;
	const ivec2 SCALE = ivec2(1.0/VL_RENDER_RESOLUTION);
	ivec2 UV_DEPTH = ivec2(UV*VL_RENDER_RESOLUTION)*SCALE;
	ivec2 UV_COLOR = ivec2(UV*VL_RENDER_RESOLUTION);
	ivec2 UV_NOISE = ivec2(gl_FragCoord.xy*texelSize + 1);

	ivec2 OFFSET[5] = ivec2[](
		ivec2(-1,-1),
		ivec2( 1, 1),
		ivec2(-1, 1),
		ivec2( 1,-1),
		ivec2( 0, 0)
	);

	for(int i = 0; i < 5; i++) {
 
		#ifdef DISTANT_HORIZONS
			float offsetDepth = sqrt(texelFetch2D(depth, UV_DEPTH + (OFFSET[i] + UV_NOISE) * SCALE,0).a/65000.0);
		#else
			float offsetDepth = linearize(texelFetch2D(depth, UV_DEPTH + (OFFSET[i] + UV_NOISE) * SCALE, 0).r);
		#endif
 
		float edgeDiff = abs(offsetDepth - referenceDepth) < threshold ? 1.0 : 1e-7;
		outerEdgeResults = max(outerEdgeResults, abs(referenceDepth - offsetDepth));

		vec4 offsetColor = texelFetch2D(colortex0, UV_COLOR + OFFSET[i] + UV_NOISE, 0).rgba;
		colorSum += offsetColor*edgeDiff;
		edgeSum += edgeDiff;
	}

	outerEdgeResults = outerEdgeResults > (hand ? 0.005 : referenceDepth*0.05 + 0.1) ? 1.0 : 0.0;

	return colorSum / edgeSum;
}

vec4 VLTemporalFiltering(vec3 viewPos, in float referenceDepth, sampler2D depth, bool hand){
	vec2 offsetTexcoord = gl_FragCoord.xy * texelSize;
	vec2 VLtexCoord = offsetTexcoord * VL_RENDER_RESOLUTION;

	// get previous frames position stuff for UV
	vec3 previousPosition = toPreviousPos(viewPos);
	previousPosition = toClipSpace3Prev(previousPosition);

	vec2 velocity = previousPosition.xy - offsetTexcoord;
	previousPosition.xy = offsetTexcoord + velocity;

	vec4 currentFrame = texture2D(colortex0, VLtexCoord);

	// to fill pixel gaps in geometry edges, do a bilateral upsample.
	// pass a mask to only show upsampled color around the edges of blocks. this is so it doesnt blur reprojected results.
	float outerEdgeResults = 0.0;
	vec4 upsampledCurrentFrame = bilateralUpsample(outerEdgeResults, referenceDepth, depth, hand);

	if (previousPosition.x < 0.0 || previousPosition.y < 0.0 || previousPosition.x > 1.0 || previousPosition.y > 1.0) return currentFrame;

	vec4 col1 = texture2D(colortex0, VLtexCoord + vec2( texelSize.x, texelSize.y));
	vec4 col2 = texture2D(colortex0, VLtexCoord + vec2( texelSize.x, -texelSize.y));
	vec4 col3 = texture2D(colortex0, VLtexCoord + vec2(-texelSize.x, -texelSize.y));
	vec4 col4 = texture2D(colortex0, VLtexCoord + vec2(-texelSize.x, texelSize.y));
	vec4 col5 = texture2D(colortex0, VLtexCoord + vec2( 0.0, texelSize.y));
	vec4 col6 = texture2D(colortex0, VLtexCoord + vec2( 0.0, -texelSize.y));
	vec4 col7 = texture2D(colortex0, VLtexCoord + vec2(-texelSize.x, 0.0));
	vec4 col8 = texture2D(colortex0, VLtexCoord + vec2( texelSize.x, 0.0));

	vec4 colMax = max(currentFrame,max(col1,max(col2,max(col3, max(col4, max(col5, max(col6, max(col7, col8))))))));
	vec4 colMin = min(currentFrame,min(col1,min(col2,min(col3, min(col4, min(col5, min(col6, min(col7, col8))))))));

	vec4 frameHistory = texture2D(colortex10, previousPosition.xy*RENDER_SCALE);
	vec4 clampedFrameHistory = clamp(frameHistory, colMin, colMax);

	float blendingFactor = 0.1;

	if(abs(clampedFrameHistory.a  - frameHistory.a) > 0.1) blendingFactor = 1.0;

	vec4 reprojectFrame = mix(clampedFrameHistory, currentFrame, blendingFactor);

	// return clamp(reprojectFrame,0.0,65000.0);
	return clamp(mix(reprojectFrame, upsampledCurrentFrame, outerEdgeResults),0.0,65000.0);
}

void blendAllFogTypes(inout vec3 color, inout float bloomyFogMult, vec4 volumetrics, float linearDistance, vec3 playerPos, vec3 cameraPosition, bool isSky){

	// blend cave fog
	#if defined OVERWORLD_SHADER && defined CAVE_FOG
		if (isEyeInWater == 0 && eyeAltitude < 1500){
			vec3 cavefogCol = vec3(CaveFogColor_R, CaveFogColor_G, CaveFogColor_B) * 0.3;
			cavefogCol *= 1.0-pow(1.0-pow(1.0 - max(1.0 - linearDistance/far,0),2),CaveFogFallOff);
			cavefogCol *= exp(-7.0*clamp(playerPos.y*0.5+0.5,0,1)) * 0.999 + 0.001;

			#ifdef CAVE_FOG_DARKEN_SKY
				float skyhole = pow(clamp(1.0-pow(max(playerPos.y - 0.6,0.0)*5.0,2.0),0.0,1.0),2);
				color.rgb = mix(color.rgb + cavefogCol * caveDetection, cavefogCol, isSky ? skyhole * caveDetection : 0.0);
			#else
				color.rgb += cavefogCol * caveDetection;
			#endif
		}
	#endif

	/// water absorption; it is completed when volumetrics are blended.
	if(isEyeInWater == 1){
		vec3 totEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
		vec3 scatterCoef = Dirt_Amount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / 3.14;

		float distanceFromWaterSurface = playerPos.y + 1.0 + (cameraPosition.y - waterEnteredAltitude)/waterEnteredAltitude;
		distanceFromWaterSurface = clamp(distanceFromWaterSurface,0,1);

		vec3 transmittance = exp(-totEpsilon * linearDistance);
		color.rgb *= transmittance;

		vec3 transmittance2 = exp(-totEpsilon * 50.0);
		float fogfade = 1.0 - max((1.0 - linearDistance / min(far, 16.0*7.0) ),0);
		color.rgb += (transmittance2 * scatterCoef) * fogfade;
    
		bloomyFogMult *= 0.5;
	}

	/// blend volumetrics
	color = color * volumetrics.a + volumetrics.rgb;
  
	// make bloomy fog only work outside of the overworld (unless underwater)
	#ifndef OVERWORLD_SHADER
		bloomyFogMult *= volumetrics.a;
	#endif

	// blend vanilla fogs (blindness, darkness, lava, powdered snow)
	if(isEyeInWater > 1 || blindness > 0 || darknessFactor > 0){
		float enviornmentFogDensity = 1.0 - clamp(linearDistance/fogEnd,0,1);
		enviornmentFogDensity = 1.0 - enviornmentFogDensity*enviornmentFogDensity;
		enviornmentFogDensity *= enviornmentFogDensity;
		enviornmentFogDensity =  mix(enviornmentFogDensity, 1.0, min(darknessLightFactor*2.0,1));

		color = mix(color, toLinear(fogColor), enviornmentFogDensity);
	}
}

void blendForwardRendering( inout vec3 color, vec4 translucentShader ){

	// REMEMBER that forward rendered color is written as color.rgb/10.0, invert it.
	if(translucentShader.a > 0) {
		color = color * (1.0 - translucentShader.a) + translucentShader.rgb * 10.0;
	}
}

float getBorderFogDensity(float linearDistance, vec3 playerPos, bool sky){
	if(sky) return 0.0;

	#ifdef DISTANT_HORIZONS
		float borderFogDensity = smoothstep(1.0, 0.0, min(max(1.0 - linearDistance / dhRenderDistance,0.0)*3.0,1.0)   );
	#else
		float borderFogDensity = smoothstep(1.0, 0.0, min(max(1.0 - linearDistance / far,0.0)*3.0,1.0)   );
	#endif
  
	borderFogDensity *= exp(-10.0 * pow(clamp(playerPos.y,0.0,1.0)*4.0,2.0));
	borderFogDensity *= (1.0-caveDetection);

	return borderFogDensity;
}

void main() {
  /* RENDERTARGETS:7,3,10 */

	////// --------------- SETUP STUFF --------------- //////
	vec2 texcoord = gl_FragCoord.xy*texelSize;
	float depth = texelFetch2D(depthtex0, ivec2(gl_FragCoord.xy),0).x;
	bool hand = depth < 0.56;
	float z = depth;

	float z2 = texture2D(depthtex1, texcoord).x;
	float frDepth = linearize(z);

	float swappedDepth = z;

	#ifdef DISTANT_HORIZONS
		float DH_depth0 = texture2D(dhDepthTex,texcoord).x;
		float depthOpaque = z;
		float depthOpaqueL = linearizeDepthFast(depthOpaque, near, farPlane);
		
		float dhDepthOpaque = DH_depth0;
		float dhDepthOpaqueL = linearizeDepthFast(dhDepthOpaque, dhNearPlane, dhFarPlane);
		if (depthOpaque >= 1.0 || (dhDepthOpaqueL < depthOpaqueL && dhDepthOpaque > 0.0)){
			depthOpaque = dhDepthOpaque;
			depthOpaqueL = dhDepthOpaqueL;
		}

		swappedDepth = depthOpaque;
	#else
		float DH_depth0 = 0.0;
	#endif

	bool isSky = swappedDepth >= 1.0;

	vec3 viewPos = toScreenSpace_DH(texcoord/RENDER_SCALE, z, DH_depth0);
	vec3 playerPos = toWorldSpace(viewPos);

	float linearDistance = length(playerPos);
	float linearDistance_cylinder = length(playerPos.xz);
	vec3 playerPos_normalized = normalize(playerPos);

	vec3 viewPos_alt = toScreenSpace(vec3(texcoord/RENDER_SCALE, z2));
	vec3 playerPos_alt = toWorldSpace(viewPos_alt);
	float linearDistance_cylinder_alt = length(playerPos_alt.xz);

	float lightleakfix = clamp(pow(eyeBrightnessSmooth.y/240.,2) ,0.0,1.0);
	float lightleakfixfast = clamp(eyeBrightness.y/240.,0.0,1.0);

	////// --------------- UNPACK OPAQUE GBUFFERS --------------- //////
	// float opaqueMasks = decodeVec2(texture2D(colortex1,texcoord).a).y;
	// bool isOpaque_entity = abs(opaqueMasks-0.45) < 0.01;

	////// --------------- UNPACK TRANSLUCENT GBUFFERS --------------- //////
	vec4 data = texelFetch2D(colortex11,ivec2(texcoord/texelSize),0).rgba;
	vec4 unpack0 = vec4(decodeVec2(data.r),decodeVec2(data.g)) ;
	vec4 unpack1 = vec4(decodeVec2(data.b),decodeVec2(data.a)) ;
	
	vec4 albedo = vec4(unpack0.ba,unpack1.rg);
	vec2 tangentNormals = unpack0.xy*2.0-1.0;
  
	bool nameTagMask = abs(unpack1.a - 0.1) < 0.01;
	float nametagbackground = nameTagMask ? 0.25 : 1.0;

	if(albedo.a < 0.01) tangentNormals = vec2(0.0);

	////// --------------- UNPACK MISC --------------- //////
	// 1.0 = water mask
	// 0.9 = entity mask
	// 0.8 = reflective entities
	// 0.7 = reflective blocks
	float translucentMasks = texture2D(colortex7, texcoord).a;

	bool isWater = translucentMasks > 0.99;
	bool isReflectiveEntity = abs(translucentMasks - 0.8) < 0.01;
	bool isReflective = abs(translucentMasks - 0.7) < 0.01 || isWater || isReflectiveEntity;
	bool isEntity = abs(translucentMasks - 0.9) < 0.01 || isReflectiveEntity;

  ////// --------------- get volumetrics

	#ifdef OVERWORLD_SHADER 
		float DH_mixedLinearZ = sqrt(texelFetch2D(colortex12,ivec2(gl_FragCoord.xy),0).a/65000.0);
		vec4 temporallyFilteredVL = VLTemporalFiltering(viewPos, DH_mixedLinearZ, colortex12, hand);
	#else
		vec4 temporallyFilteredVL = VLTemporalFiltering(viewPos, frDepth, depthtex0, hand);
	#endif

	gl_FragData[2] = temporallyFilteredVL;

	float bloomyFogMult = 1.0;

  ////// --------------- distort texcoords as a refraction effect
	vec2 refractedCoord = texcoord;

  ////// --------------- MAIN COLOR BUFFER
	#ifdef FAKE_REFRACTION_EFFECT
		vec3 color = doRefractionEffect(refractedCoord, tangentNormals.xy, linearDistance, isReflectiveEntity, isWater && isEyeInWater == 1);
	#else
		vec3 color = texture2D(colortex3, refractedCoord).rgb;
	#endif

  ////// --------------- START BLENDING FOGS AND FORWARD RENDERED COLOR
	vec4 TranslucentShader = texture2D(colortex2, texcoord);

  // blend border fog. be sure to blend before and after forward rendered color blends.
	#if defined BorderFog && defined OVERWORLD_SHADER
		vec4 borderFog = vec4(skyGroundColor, getBorderFogDensity(linearDistance_cylinder, playerPos_normalized, swappedDepth >= 1.0));

		#ifndef SKY_GROUND
			borderFog.rgb = skyFromTex(playerPos, colortex4)/1200.0 * Sky_Brightness;
		#endif

		#ifndef DISTANT_HORIZONS
			color = mix(color, borderFog.rgb, getBorderFogDensity(linearDistance_cylinder_alt, normalize(playerPos_alt), z2 >= 1.0 || TranslucentShader.a <= 0));
		#endif
	#else
		vec4 borderFog = vec4(0.0);
	#endif

  // apply block breaking effect.
	if(albedo.a > 0.01 && !isWater && TranslucentShader.a <= 0.0 && !isEntity) color = mix(color*6.0, color, luma(albedo.rgb)) * albedo.rgb;
  
  // apply multiplicative color blend for glass n stuff
	#ifdef Glass_Tint
		if(!isWater) color *= mix(normalize(albedo.rgb+1e-7), vec3(1.0), max(borderFog.a, min(max(0.1-albedo.a,0.0) * 10.0,1.0))) ;
	#endif

  // blend forward rendered programs onto the color.
	blendForwardRendering(color, TranslucentShader);

	#if defined BorderFog && defined OVERWORLD_SHADER
		color = mix(color, borderFog.rgb, getBorderFogDensity(linearDistance_cylinder, playerPos_normalized, swappedDepth >= 1.0));
	#endif

  // tweaks to VL for nametag rendering
	#ifdef IS_IRIS
		temporallyFilteredVL.a = min(temporallyFilteredVL.a + (1.0-nametagbackground),1.0);
		temporallyFilteredVL.rgb *= nametagbackground;
	#endif

  // bloomy rain effect
	#ifdef OVERWORLD_SHADER
		float rainDrops =  clamp(texture2D(colortex9, texcoord).a, 0.0, 1.0); 
		if(rainDrops > 0.0) bloomyFogMult *= clamp(1.0 - pow(rainDrops * 5.0, 2), 0.0, 1.0);
	#endif
 
  // blend all fog types. volumetric fog, volumetric clouds, distance based fogs for lava, powdered snow, blindness, and darkness.
	blendAllFogTypes(color, bloomyFogMult, temporallyFilteredVL, linearDistance, playerPos_normalized, cameraPosition, isSky);

////// --------------- RAINBOWS

	#if RAINBOW > 0 && defined OVERWORLD_SHADER
		vec3 rainbow = drawRainbow(playerPos);
		float bottomLayerHeight = min(CloudLayer0_height, CloudLayer1_height);
		float bottomLayerTallness = CloudLayer0_height < CloudLayer1_height ? CloudLayer0_tallness : CloudLayer1_tallness;
		rainbow = mix(rainbow * temporallyFilteredVL.a, rainbow, smoothstep(bottomLayerHeight + bottomLayerTallness, bottomLayerHeight, playerPos_normalized.y * RAINBOW_DISTANCE + cameraPosition.y)); // Insert cloud
		color += rainbow;
	#endif

////// --------------- FINALIZE
	#ifdef display_LUT
		float zoomLevel = 1.0;
		vec3 thingy = texelFetch2D(colortex4,ivec2(gl_FragCoord.xy/zoomLevel),0).rgb /1200.0;

		if(luma(thingy) > 0.0) {
			color.rgb =  thingy;
			bloomyFogMult = 1.0;
		}

		if(hideGUI == 1) {
			#ifdef OVERWORLD_SHADER
				color.rgb = skyCloudsFromTex(playerPos_normalized, colortex4).rgb/1200.0;
			#else
				color.rgb = volumetricsFromTex(playerPos_normalized, colortex4, 0.0).rgb/1200.0;
			#endif
		}
	#endif

	gl_FragData[0].r = bloomyFogMult; // pass fog alpha so bloom can do bloomy fog
	gl_FragData[1].rgb = clamp(color.rgb, 0.0,68000.0);
}