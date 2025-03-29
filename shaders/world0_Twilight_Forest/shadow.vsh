#version 120
#include "/lib/settings.glsl"
#ifdef IS_LPV_ENABLED
	#extension GL_ARB_explicit_attrib_location: enable
	#extension GL_ARB_shader_image_load_store: enable
#endif

#define RENDER_SHADOW

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

#define SHADOW_MAP_BIAS 0.5
const float PI = 3.1415927;
varying vec2 texcoord;

uniform int hideGUI;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float screenBrightness;
uniform vec3 sunVec;
uniform float aspectRatio;
uniform float sunElevation;
uniform vec3 sunPosition;
uniform float lightSign;
uniform float cosFov;
uniform vec3 shadowViewDir;
uniform vec3 shadowCamera;
uniform vec3 shadowLightVec;
uniform float shadowMaxProj;
attribute vec4 mc_midTexCoord;
varying vec4 color;

attribute vec4 mc_Entity;
uniform int blockEntityId;
uniform int entityId;

#include "/lib/Shadow_Params.glsl"
#include "/lib/bokeh.glsl"
#include "/lib/blocks.glsl"
#include "/lib/entities.glsl"

#ifdef IS_LPV_ENABLED
	#ifdef IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
		attribute vec4 at_midBlock;
	#else
		attribute vec3 at_midBlock;
	#endif
    uniform int currentRenderedItemId;
	uniform int renderStage;

	#include "/lib/voxel_common.glsl"
	#include "/lib/voxel_write.glsl"
#endif

const float PI48 = 150.796447372*WAVY_SPEED;
float pi2wt = PI48*frameTimeCounter;

vec2 calcWave(in vec3 pos) {

	float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec2 ret = (sin(pi2wt*vec2(0.0063,0.0015)*4. - pos.xz + pos.y*0.05)+0.1)*magnitude;

	return ret;
}

vec3 calcMovePlants(in vec3 pos) {
	vec2 move1 = calcWave(pos );
	float move1y = -length(move1);
	return vec3(move1.x,move1y,move1.y)*5.*WAVY_STRENGTH/255.0;
}

vec3 calcWaveLeaves(in vec3 pos, in float fm, in float mm, in float ma, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5) {

	float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec3 ret = (sin(pi2wt*vec3(0.0063,0.0224,0.0015)*1.5 - pos))*magnitude;

	return ret;
}

vec3 calcMoveLeaves(in vec3 pos, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5, in vec3 amp1, in vec3 amp2) {
	vec3 move1 = calcWaveLeaves(pos      , 0.0054, 0.0400, 0.0400, 0.0127, 0.0089, 0.0114, 0.0063, 0.0224, 0.0015) * amp1;
	return move1*5.*WAVY_STRENGTH/255.;
}

bool intersectCone(float coneHalfAngle, vec3 coneTip , vec3 coneAxis, vec3 rayOrig, vec3 rayDir, float maxZ) {
	vec3 co = rayOrig - coneTip;
	float prod = dot(normalize(co),coneAxis);
	if (prod <= -coneHalfAngle) return true;   //In view frustrum

	float a = dot(rayDir,coneAxis)*dot(rayDir,coneAxis) - coneHalfAngle*coneHalfAngle;
	float b = 2. * (dot(rayDir,coneAxis)*dot(co,coneAxis) - dot(rayDir,co)*coneHalfAngle*coneHalfAngle);
	float c = dot(co,coneAxis)*dot(co,coneAxis) - dot(co,co)*coneHalfAngle*coneHalfAngle;

	float det = b*b - 4.*a*c;
	if (det < 0.) return false;    // No intersection with either forward cone and backward cone

	det = sqrt(det);
	float t2 = (-b + det) / (2. * a);
	if (t2 <= 0.0 || t2 >= maxZ) return false;  //Idk why it works

	return true;
}

#include "/lib/projections.glsl"

// uniform float far;

#include "/lib/DistantHorizons_projections.glsl"

// uniform int renderStage;

void main() {
	texcoord.xy = gl_MultiTexCoord0.xy;
	color = gl_Color;

	vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;

	// #if defined IS_LPV_ENABLED || defined WAVY_PLANTS  || !defined PLANET_CURVATURE
		vec3 playerpos = toShadowSpace(position);
	// #endif

	#if defined IS_LPV_ENABLED && defined MC_GL_EXT_shader_image_load_store
		PopulateShadowVoxel(playerpos);
	#endif

	int blockId = int(mc_Entity.x + 0.5);

	vec3 worldpos = playerpos;

	#ifdef WAVY_PLANTS
		// also use normal, so up/down facing geometry does not get detatched from its model parts.
		bool InterpolateFromBase = gl_MultiTexCoord0.t < max(mc_midTexCoord.t, abs(viewToWorld(normalize(gl_NormalMatrix * gl_Normal)).y));
		if((
			// these wave off of the ground. the area connected to the ground does not wave.
			(InterpolateFromBase && (mc_Entity.x == BLOCK_GRASS_TALL_LOWER || mc_Entity.x == BLOCK_GRASS_SHORT || mc_Entity.x == BLOCK_SAPLING || mc_Entity.x == BLOCK_GROUND_WAVING_VERTICAL))

			// these wave off of the ceiling. the area connected to the ceiling does not wave.
			|| (!InterpolateFromBase && (mc_Entity.x == BLOCK_VINE))

			// these wave off of the air. they wave uniformly
			|| (mc_Entity.x == BLOCK_GRASS_TALL_UPPER || mc_Entity.x == BLOCK_AIR_WAVING)

			#ifndef RP_MODEL_FIX
				|| (InterpolateFromBase && (mc_Entity.x == BLOCK_GROUND_WAVING)) || (mc_Entity.x == BLOCK_CAVE_VINE_BERRIES)
			#endif

		) && length(position) < 32.0) {

			// apply displacement for waving plant blocks
			worldpos += calcMovePlants(playerpos + cameraPosition) * max(gl_MultiTexCoord1.y,0.5);

			// apply displacement for waving leaf blocks specifically, overwriting the other waving mode. these wave off of the air. they wave uniformly
			if(mc_Entity.x == BLOCK_AIR_WAVING || mc_Entity.x == BLOCK_CAVE_VINE_BERRIES) worldpos = playerpos + calcMoveLeaves(playerpos + cameraPosition, 0.0040, 0.0064, 0.0043, 0.0035, 0.0037, 0.0041, vec3(1.0,0.2,1.0), vec3(0.5,0.1,0.5))*gl_MultiTexCoord1.y;
		}
	#endif

	#ifdef PLANET_CURVATURE
		float curvature = length(worldpos) / (16*8);
		worldpos.y -= curvature*curvature * CURVATURE_AMOUNT;
	#endif

	position = mat3(shadowModelView) * worldpos + shadowModelView[3].xyz;

	#ifdef DISTORT_SHADOWMAP
		if (entityId == ENTITY_SSS_MEDIUM || entityId == ENTITY_SLIME)
			position.xyz = position.xyz - normalize(gl_NormalMatrix * gl_Normal) * 0.25;

		gl_Position = BiasShadowProjection(toClipSpace4(position));
	#else
		gl_Position = toClipSpace4(position);
	#endif
 	

	if (blockId == BLOCK_WATER) gl_Position.w = -1.0;

  	gl_Position.z /= 6.0;
}