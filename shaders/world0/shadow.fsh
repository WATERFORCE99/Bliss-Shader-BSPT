#version 120

#include "/lib/settings.glsl"

varying vec4 color;

#ifdef TRANSLUCENT_COLORED_SHADOWS
	varying vec3 Fcolor;
#else
	const vec3 Fcolor = vec3(1.0);
#endif

varying vec2 Ftexcoord;
uniform sampler2D tex;
uniform sampler2D noisetex;

#ifdef LPV_SHADOWS
	#include "/lib/cube/cubeData.glsl"
	flat in int render;
#endif

float blueNoise(){
	return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 );
}

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
	#ifdef LPV_SHADOWS
		if (render >= 0 && (
			any(lessThan(gl_FragCoord.xy, minBounds[render >> 4] + renderBounds[render & 15])) ||
			any(greaterThan(gl_FragCoord.xy, maxBounds[render >> 4] + renderBounds[render & 15])))){
			discard;
			return;
		}
	#endif

	vec4 shadowColor = vec4(texture2D(tex,Ftexcoord.xy).rgb * Fcolor.rgb,  texture2DLod(tex, Ftexcoord.xy, 0).a);

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		if(shadowColor.a > 0.9999) shadowColor.rgb = vec3(0.0);
	#endif

	// gl_FragData[0] = vec4(texture2D(tex,texcoord.xy).rgb * color.rgb,  texture2DLod(tex, texcoord.xy, 0).a);
	gl_FragData[0] = shadowColor;

  	#ifdef Stochastic_Transparent_Shadows
		if(gl_FragData[0].a < blueNoise()){
			discard;
			return;
		}
  	#endif
}