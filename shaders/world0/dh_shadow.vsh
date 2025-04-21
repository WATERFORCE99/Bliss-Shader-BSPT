#version 120

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/
#include "/lib/settings.glsl"

#define SHADOW_MAP_BIAS 0.5
const float PI = 3.1415927;
out vec3 color;

flat out int isWater;

#include "/lib/Shadow_Params.glsl"

#include "/lib/projections.glsl"
#include "/lib/DistantHorizons_projections.glsl"

out float overdrawCull;
// uniform int renderStage;

void main() {
	isWater = 0;

	if(gl_Color.a < 1.0) isWater = 1;

	color = gl_Color.rgb;

	vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;
	#ifdef DH_OVERDRAW_PREVENTION
		vec3 worldpos = toShadowSpace(position);
		overdrawCull = 1.0 - clamp(1.0 - length(worldpos) / far,0.0,1.0);
	#else
		overdrawCull = 1.0;
	#endif

	#ifdef DISTORT_SHADOWMAP
		gl_Position = BiasShadowProjection(toClipSpace4(position));
	#else
		gl_Position = toClipSpace4(position);
	#endif

	gl_Position.z /= 6.0;
	#ifdef LPV_SHADOWS
		gl_Position.xy = gl_Position.xy * 0.8 - 0.2 * gl_Position.w;
	#endif
}