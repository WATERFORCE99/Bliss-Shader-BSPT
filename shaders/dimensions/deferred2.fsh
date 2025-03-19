#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/dither.glsl"

//Computes volumetric clouds at variable resolution (default 1/4 res)

flat varying vec3 sunColor;
// flat varying vec3 moonColor;
flat varying vec3 averageSkyCol;

flat varying float tempOffsets;
// uniform float far;
uniform float near;
uniform sampler2D depthtex0;

#ifdef DISTANT_HORIZONS
	uniform sampler2D dhDepthTex;
	uniform sampler2D dhDepthTex1;
#endif

// uniform sampler2D colortex4;
uniform sampler2D colortex12;

flat varying vec3 WsunVec;
uniform float sunElevation;
uniform vec3 sunVec;
uniform vec2 texelSize;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform int framemod8;

#include "/lib/projections.glsl"
#include "/lib/DistantHorizons_projections.glsl"


vec3 normVec (vec3 vec){
	return vec*inversesqrt(dot(vec,vec));
}
uniform float far;


float ld(float dist) {
	return (2.0 * near) / (far + near - dist * (far - near));
}

uniform int dhRenderDistance;

#include "/lib/lightning_stuff.glsl"
#include "/lib/sky_gradient.glsl"
#include "/lib/res_params.glsl"

#define CLOUDS_INTERSECT_TERRAIN
uniform float eyeAltitude;

uniform int worldTime;
uniform int worldDay;

flat in vec4 dailyWeatherParams0;
flat in vec4 dailyWeatherParams1;

#include "/lib/volumetricClouds.glsl"


//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////


void main() {

	#if defined OVERWORLD_SHADER && defined VOLUMETRIC_CLOUDS && !defined  CLOUDS_INTERSECT_TERRAIN
		vec2 halfResTC = vec2(floor(gl_FragCoord.xy)/CLOUDS_QUALITY/RENDER_SCALE+0.5+offsets[framemod8]*CLOUDS_QUALITY*RENDER_SCALE*0.5);

		vec2 halfResTC2 = vec2(floor(gl_FragCoord.xy)/CLOUDS_QUALITY+0.5+offsets[framemod8]*CLOUDS_QUALITY*0.5);
		
		#ifdef CLOUDS_INTERSECT_TERRAIN
			float depth = texelFetch2D(depthtex0, ivec2(halfResTC2), 0).x;

			#ifdef DISTANT_HORIZONS
				float DH_depth =  texelFetch2D(dhDepthTex, ivec2(halfResTC2),0).x;
				vec3 viewPos = toScreenSpace_DH(halfResTC*texelSize, depth, DH_depth);
			#else
				vec3 viewPos = toScreenSpace(vec3(halfResTC*texelSize, depth));
			#endif
		#else
			vec3 viewPos = toScreenSpace(vec3(halfResTC*texelSize, 1.0));
		#endif

		vec3 tesvar = vec3(0.0);
		vec4 VolumetricClouds = renderClouds(viewPos, vec2(R2_dither(), blueNoise()), sunColor/80.0, averageSkyCol/30.0,tesvar);

		gl_FragData[0] = VolumetricClouds;
	#else
		gl_FragData[0] = vec4(0.0,0.0,0.0,1.0);
	#endif
}