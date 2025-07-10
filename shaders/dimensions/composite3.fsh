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
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex15;
uniform vec2 texelSize;

uniform float viewHeight;
uniform float viewWidth;
uniform vec3 sunVec;
uniform float frameTimeCounter;
uniform float far;
uniform float near;
uniform float farPlane;

uniform int hideGUI;
uniform int dhRenderDistance;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform ivec2 eyeBrightness;
uniform float rainStrength;
uniform float blindness;
uniform float darknessFactor;
uniform float darknessLightFactor;
uniform float caveDetection;

#include "/lib/waterBump.glsl"
#include "/lib/res_params.glsl"

#ifdef OVERWORLD_SHADER
	#include "/lib/climate_settings.glsl"
#endif

#include "/lib/sky_gradient.glsl"
#include "/lib/projections.glsl"

uniform float eyeAltitude;

float ld(float depth) {
	return 1.0 / (zMults.y - depth * zMults.z);		// (-depth * (far - near)) = (2.0 * near)/ld - far - near
}

#include "/lib/DistantHorizons_projections.glsl"

vec4 blueNoise(vec2 coord){
	return texelFetch2D(colortex6, ivec2(coord)%512 , 0);
}

vec3 normVec(vec3 vec){
	return vec*inversesqrt(dot(vec,vec));
}

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
	return (near * far) / (depth * (near - far) + far);
}

vec3 doRefractionEffect(inout vec2 texcoord, vec2 normal, float linearDistance, bool isReflectiveEntity){
  
	// make the tangent space normals match the directions of the texcoord UV, this greatly improves the refraction effect.
	vec2 UVNormal = vec2(normal.x,-normal.y);
  
	float refractionMult = 0.3 / (1.0 + pow(linearDistance,0.8));
	float diffractionMult = 0.035;
	float smudgeMult = 1.0;

	if(isReflectiveEntity) refractionMult *= 0.5;

	// for diffraction, i wanted to know *when* normals were at an angle, not what the
	float clampValue = 0.2;
	vec2 abberationOffset = (clamp(UVNormal,-clampValue, clampValue)/clampValue) * diffractionMult;

	// return vec3(abs(abberationOffset), 0.0);

	#ifdef REFRACTION_SMUDGE
		vec2 directionalSmudge = abberationOffset * (blueNoise()-0.5) * smudgeMult;
	#else
		vec2 directionalSmudge = vec2(0.0);
	#endif

	vec2 refractedUV = texcoord - (UVNormal + directionalSmudge)*refractionMult;

	#ifdef FAKE_DISPERSION_EFFECT
		refractionMult *= min(decodeVec2(texelFetch2D(colortex11, ivec2((texcoord - ((UVNormal + abberationOffset) + directionalSmudge)*refractionMult)/texelSize),0).b).g,
							decodeVec2(texelFetch2D(colortex11, ivec2((texcoord + ((UVNormal + abberationOffset) + directionalSmudge)*refractionMult)/texelSize),0).b).g) > 0.0 ? 1.0 : 0.0;
	#else
		refractionMult *= decodeVec2(texelFetch2D(colortex11, ivec2(refractedUV/texelSize),0).b).g > 0.0 ? 1.0 : 0.0;
	#endif

	// a max bound around screen edges and edges of the refracted screen
	vec2 vignetteSides = clamp(min((1.0 - refractedUV)/0.05, refractedUV/0.05)+0.5,0.0,1.0);
	float vignette = vignetteSides.x*vignetteSides.y;
	refractionMult *= vignette;

	vec3 color = vec3(0.0);

	#ifdef FAKE_DISPERSION_EFFECT
		//// RED
		refractedUV = clamp(texcoord - ((UVNormal + abberationOffset) + directionalSmudge)*refractionMult ,0.0,1.0);
		color.r = texelFetch2D(colortex3, ivec2(refractedUV/texelSize),0).r;
		//// GREEN
		refractedUV = clamp(texcoord - (UVNormal + directionalSmudge)*refractionMult ,0,1);
		color.g = texelFetch2D(colortex3, ivec2(refractedUV/texelSize),0).g;
		//// BLUE
		refractedUV = clamp(texcoord - ((UVNormal - abberationOffset) + directionalSmudge)*refractionMult ,0.0,1.0);
		color.b = texelFetch2D(colortex3, ivec2(refractedUV/texelSize),0).b;
	#else
		refractedUV = clamp(texcoord - (UVNormal + directionalSmudge)*refractionMult,0,1);
		color = texture2D(colortex3, refractedUV).rgb;
	#endif

	texcoord = texcoord - (UVNormal + directionalSmudge)*refractionMult;

	return color;
}

vec3 closestToCamera5taps(vec2 texcoord, sampler2D depth){
	vec2 du = vec2(texelSize.x*2., 0.0);
	vec2 dv = vec2(0.0, texelSize.y*2.);

	vec3 dtl = vec3(texcoord,0.) + vec3(-texelSize, 				texture2D(depth, texcoord - dv - du).x);
	vec3 dtr = vec3(texcoord,0.) + vec3( texelSize.x, -texelSize.y, texture2D(depth, texcoord - dv + du).x);
	vec3 dmc = vec3(texcoord,0.) + vec3( 0.0, 0.0, 					texture2D(depth, texcoord).x);
	vec3 dbl = vec3(texcoord,0.) + vec3(-texelSize.x, texelSize.y, 	texture2D(depth, texcoord + dv - du).x);
	vec3 dbr = vec3(texcoord,0.) + vec3( texelSize.x, texelSize.y, 	texture2D(depth, texcoord + dv + du).x);

	vec3 dmin = dmc;
	dmin = dmin.z > dtr.z ? dtr : dmin;
	dmin = dmin.z > dtl.z ? dtl : dmin;
	dmin = dmin.z > dbl.z ? dbl : dmin;
	dmin = dmin.z > dbr.z ? dbr : dmin;
	
	#ifdef TAA_UPSCALING
		dmin.xy = dmin.xy/RENDER_SCALE;
	#endif

	return dmin;
}

vec4 bilateralUpsample(out float outerEdgeResults, float referenceDepth, sampler2D depth){

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
		ivec2(-2,-2),
		ivec2( 1, 1),
		ivec2(-1, 1),
		ivec2( 2,-2),
		ivec2( 0, 0)
	);

	for(int i = 0; i < 5; i++) {
 
		#ifdef DISTANT_HORIZONS
			float offsetDepth = sqrt(texelFetch2D(depth, UV_DEPTH + (OFFSET[i] + UV_NOISE) * SCALE,0).a/65000.0);
		#else
			float offsetDepth = ld(texelFetch2D(depth, UV_DEPTH + (OFFSET[i] + UV_NOISE) * SCALE, 0).r);
		#endif
 
		float edgeDiff = abs(offsetDepth - referenceDepth) < threshold ? 1.0 : 1e-7;
		outerEdgeResults = max(outerEdgeResults, clamp(referenceDepth - offsetDepth,0.0,1.0));

		vec4 offsetColor = texelFetch2D(colortex0, UV_COLOR + OFFSET[i] + UV_NOISE, 0).rgba;
		colorSum += offsetColor*edgeDiff;
		edgeSum += edgeDiff;
	}

	outerEdgeResults = outerEdgeResults > 0.1 ? 1.0 : 0.0;

	return colorSum / edgeSum;
}

vec4 VLTemporalFiltering(vec3 viewPos, in float referenceDepth, sampler2D depth){
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
	vec4 upsampledCurrentFrame = bilateralUpsample(outerEdgeResults, referenceDepth, depth);

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

uniform float waterEnteredAltitude;

void main() {
  /* RENDERTARGETS:7,3,10 */

	////// --------------- SETUP STUFF --------------- //////
	vec2 texcoord = gl_FragCoord.xy*texelSize;

	float z = texelFetch2D(depthtex0, ivec2(gl_FragCoord.xy),0).x;//texture2D(depthtex0, texcoord).x;
	float z2 = texture2D(depthtex1, texcoord).x;
	float frDepth = ld(z);

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

	vec3 viewPos = toScreenSpace_DH(texcoord/RENDER_SCALE, z, DH_depth0);
	vec3 playerPos = toWorldSpace(viewPos);

	vec3 playerPos_normalized = normVec(playerPos);

	vec3 viewPos_alt = toScreenSpace(vec3(texcoord/RENDER_SCALE, z2));
	vec3 playerPos_alt = toWorldSpace(viewPos_alt);

	float linearDistance = length(playerPos);
	float linearDistance_cylinder = length(playerPos.xz);

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
		vec4 temporallyFilteredVL = VLTemporalFiltering(viewPos, DH_mixedLinearZ, colortex12);
	#else
		vec4 temporallyFilteredVL = VLTemporalFiltering(viewPos, frDepth, depthtex0);
	#endif

	gl_FragData[2] = temporallyFilteredVL;

	float bloomyFogMult = 1.0;

  ////// --------------- distort texcoords as a refraction effect
  vec2 refractedCoord = texcoord;

  ////// --------------- MAIN COLOR BUFFER
	#ifdef FAKE_REFRACTION_EFFECT
		// ApplyDistortion(refractedCoord, tangentNormals, linearDistance, isEntity);
		// vec3 color = texture2D(colortex3, refractedCoord).rgb;
		vec3 color = doRefractionEffect(refractedCoord, tangentNormals.xy, linearDistance, isReflectiveEntity);
	#else
		// vec3 color = texture2D(colortex3, refractedCoord).rgb;
		vec3 color = texelFetch2D(colortex3, ivec2(refractedCoord/texelSize),0).rgb;
	#endif

	vec4 TranslucentShader = texture2D(colortex2, texcoord);
	// color = vec3(texcoord-0.5,0.0) * mat3(gbufferModelViewInverse);
	// apply block breaking effect.
	if(albedo.a > 0.01 && !isWater && TranslucentShader.a <= 0.0 && !isEntity) color = mix(color*6.0, color, luma(albedo.rgb)) * albedo.rgb;

  ////// --------------- BLEND TRANSLUCENT GBUFFERS 
  //////////// and do border fog on opaque and translucents
  
  	#ifdef BorderFog
		#ifdef DISTANT_HORIZONS
			float fog = smoothstep(1.0, 0.0, min(max(1.0 - linearDistance_cylinder / dhRenderDistance,0.0)*3.0,1.0));
		#else
			float fog = smoothstep(1.0, 0.0, min(max(1.0 - linearDistance_cylinder / far,0.0)*3.0,1.0));
		#endif

		fog *= exp(-10.0 * pow(clamp(playerPos_normalized.y,0.0,1.0)*4.0,2.0));

		fog *= (1.0-caveDetection);

		if(swappedDepth >= 1.0 || isEyeInWater != 0) fog = 0.0;

		#ifdef SKY_GROUND
			vec3 borderFogColor = skyGroundColor;
		#else
			vec3 borderFogColor = skyFromTex(playerPos_normalized, colortex4)/1200.0 * Sky_Brightness;
		#endif

		color.rgb = mix(color.rgb, borderFogColor, fog);
	#else
		float fog = 0.0;
	#endif

	if (TranslucentShader.a > 0.0){
		#ifdef Glass_Tint
			if(!isWater) color *= mix(normalize(albedo.rgb+1e-7), vec3(1.0), max(fog, min(max(0.1-albedo.a,0.0) * 10.0,1.0)));
		#endif

		#ifdef BorderFog
			TranslucentShader = mix(TranslucentShader, vec4(0.0), fog);
		#endif

		color *= (1.0-TranslucentShader.a);
		color += TranslucentShader.rgb*10.0; 
	}

////// --------------- VARIOUS FOG EFFECTS (behind volumetric fog)
//////////// blindness, liquid fogs and misc fogs

#if defined OVERWORLD_SHADER && defined CAVE_FOG
	if (isEyeInWater == 0 && eyeAltitude < 1500){

		vec3 cavefogCol = vec3(CaveFogColor_R, CaveFogColor_G, CaveFogColor_B);

		#ifdef PER_BIOME_ENVIRONMENT
			BiomeFogColor(cavefogCol);
		#endif

		cavefogCol *= 1.0-pow(1.0-pow(1.0 - max(1.0 - linearDistance/far,0.0),2.0),CaveFogFallOff);
		cavefogCol *= exp(-7.0*clamp(normalize(playerPos_normalized).y*0.5+0.5,0.0,1.0)) * 0.999 + 0.001;
		cavefogCol *= 0.3;

		float skyhole = pow(clamp(1.0-pow(max(playerPos_normalized.y - 0.6,0.0)*5.0,2.0),0.0,1.0),2);

		color.rgb = mix(color.rgb + cavefogCol * caveDetection, cavefogCol, z >= 1.0 ? skyhole * caveDetection : 0.0);
	}
#endif

////// --------------- underwater fog
	if (isEyeInWater == 1){
		// float dirtAmount = Dirt_Amount;
		// vec3 waterEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
		// vec3 dirtEpsilon = vec3(Dirt_Absorb_R, Dirt_Absorb_G, Dirt_Absorb_B);
		vec3 totEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);// dirtEpsilon*dirtAmount + waterEpsilon;
		vec3 scatterCoef = Dirt_Amount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / 3.14;

		float distanceFromWaterSurface = normalize(playerPos).y + 1.0 + (cameraPosition.y - waterEnteredAltitude)/waterEnteredAltitude;
		distanceFromWaterSurface = clamp(distanceFromWaterSurface, 0.0,1.0);

		vec3 transmittance = exp(-totEpsilon * linearDistance);
		color.rgb *= transmittance;

		vec3 transmittance2 = exp(-totEpsilon * 50.0);
		float fogfade = 1.0 - max((1.0 - linearDistance / min(far, 16.0*7.0) ),0);
		color.rgb += (transmittance2 * scatterCoef) * fogfade;

		bloomyFogMult *= 0.5;
	}

////// --------------- BLEND FOG INTO SCENE
//////////// apply VL fog over opaque and translucents

	bloomyFogMult *= temporallyFilteredVL.a;
  
	#ifdef IS_IRIS
		// if(z >= 1.0) color = vec3(0,255,0);
		// else color = vec3(0.01);

		color *= min(temporallyFilteredVL.a + (1.0-nametagbackground),1.0);
		color += temporallyFilteredVL.rgb * nametagbackground;
	#else
		color *= temporallyFilteredVL.a ;
		color += temporallyFilteredVL.rgb ;
	#endif
  
////// --------------- VARIOUS FOG EFFECTS (in front of volumetric fog)
//////////// blindness, liquid fogs and misc fogs

////// --------------- bloomy rain effect
	#ifdef OVERWORLD_SHADER
		float rainDrops = clamp(texture2D(colortex9,texcoord).a, 0.0, 1.0) * RAIN_VISIBILITY; 
		if(rainDrops > 0.0) bloomyFogMult *= clamp(1.0 - pow(rainDrops*5.0,2),0.0,1.0);
	#endif
  
////// --------------- lava.
	if (isEyeInWater == 2){
		color.rgb = mix(color.rgb, vec3(0.1,0.0,0.0), 1.0-exp(-10.0*clamp(linearDistance*0.5,0.,1.))*0.5);
		bloomyFogMult = 0.0;
	}

///////// --------------- powdered snow
	if (isEyeInWater == 3){
		color.rgb = mix(color.rgb,vec3(0.5,0.75,1.0),clamp(linearDistance*0.5,0.,1.));
		bloomyFogMult = 0.0;
	}

////// --------------- blindness
	color.rgb *= mix(1.0,clamp(exp(pow(linearDistance*(blindness*0.2),2) * -5),0.,1.), blindness);

//////// --------------- darkness effect
	color.rgb *= mix(1.0, (1.0-darknessLightFactor*2.0) * clamp(1.0-pow(length(viewPos)*(darknessFactor*0.07),2.0),0.0,1.0), darknessFactor);
  
////// --------------- FINALIZE
	#ifdef display_LUT

	float zoomLevel = 75.0;
	vec3 thingy = texelFetch2D(colortex4,ivec2(gl_FragCoord.xy/zoomLevel),0).rgb /1200.0;

		if(luma(thingy) > 0.0){
			color.rgb =  thingy;
			bloomyFogMult = 1.0;
		}

		#ifdef OVERWORLD_SHADER
			if(hideGUI == 1) color.rgb = skyCloudsFromTex(playerPos_normalized, colortex4).rgb/1200.0;
		#else
			if(hideGUI == 1) color.rgb = volumetricsFromTex(playerPos_normalized, colortex4, 0.0).rgb/1200.0;
		#endif

	#endif
	// color.rgb = testThing.rgb;
	gl_FragData[0].r = bloomyFogMult; // pass fog alpha so bloom can do bloomy fog
	gl_FragData[1].rgb = clamp(color.rgb, 0.0,68000.0);
}