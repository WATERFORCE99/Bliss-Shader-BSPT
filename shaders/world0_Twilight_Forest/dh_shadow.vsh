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
varying vec2 texcoord;

flat varying int water;

#include "/lib/projections.glsl"

#include "/lib/Shadow_Params.glsl"

// uniform float far;

#include "/lib/DistantHorizons_projections.glsl"

varying float overdrawCull;
// uniform int renderStage;

void main() {
	water = 0;

	if(gl_Color.a < 1.0) water = 1;

	texcoord.xy = gl_MultiTexCoord0.xy;

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
}