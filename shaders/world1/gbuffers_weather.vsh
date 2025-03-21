#version 120
#define TAA

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

out vec4 color;
out vec4 lmtexcoord;

uniform vec2 texelSize;
uniform int framemod8;
const vec2[8] offsets = vec2[8](vec2(1.,-3.)/8.,
								vec2(-1.,3.)/8.,
								vec2(5.0,1.)/8.,
								vec2(-3,-5.)/8.,
								vec2(-5.,5.)/8.,
								vec2(-7.,-1.)/8.,
								vec2(3,7.)/8.,
								vec2(7.,-7.)/8.);

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
	gl_Position = ftransform();

	lmtexcoord.xy = (gl_MultiTexCoord0).xy;
	lmtexcoord.zw = gl_MultiTexCoord1.xy / 240.0;

	color = gl_Color;
	#ifdef TAA
		gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
	#endif
}