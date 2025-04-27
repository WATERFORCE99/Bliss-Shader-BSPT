#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/util.glsl"

#ifdef END_SHADER
	flat out float Flashing;
#endif

uniform int worldDay;
#include "/lib/scene_controller.glsl"

flat out vec3 WsunVec;
flat out vec3 WmoonVec;
flat out vec3 unsigned_WsunVec;
flat out vec3 averageSkyCol_Clouds;
flat out vec4 lightCol;
flat out vec3 moonCol;
flat out vec3 albedoSmooth;

flat out vec2 TAA_Offset;
flat out vec3 zMults;
uniform sampler2D colortex4;

uniform float near;

uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;

uniform float sunElevation;
uniform float frameTimeCounter;

uniform int framemod8;
#include "/lib/TAA_jitter.glsl"

#include "/lib/Shadow_Params.glsl"

void main() {
	gl_Position = ftransform();

	#ifdef END_SHADER
		Flashing = texelFetch2D(colortex4,ivec2(1,1),0).x/150.0;
	#endif

	zMults = vec3(1.0/(far * near),far+near,far-near);

	lightCol.rgb = texelFetch2D(colortex4,ivec2(6,37),0).rgb;
	lightCol.a = float(sunElevation > 1e-5)*2.0 - 1.0;

	moonCol = texelFetch2D(colortex4,ivec2(9,37),0).rgb;

	#if defined FLASHLIGHT && defined FLASHLIGHT_BOUNCED_INDIRECT
		albedoSmooth = texelFetch2D(colortex4,ivec2(15.5,2.5),0).rgb;
	#endif

	averageSkyCol_Clouds = texelFetch2D(colortex4,ivec2(0,37),0).rgb;

	unsigned_WsunVec = normalize(mat3(gbufferModelViewInverse) * sunPosition);

	vec3 moonVec = normalize(mat3(gbufferModelViewInverse) * moonPosition);

	WmoonVec = moonVec;

	if(dot(-moonVec, unsigned_WsunVec) < 0.9999) WmoonVec = -moonVec;

	WsunVec = mix(WmoonVec, unsigned_WsunVec, clamp(lightCol.a,0,1));

	readSceneControllerParameters(colortex4, parameters.smallCumulus, parameters.largeCumulus, parameters.altostratus, parameters.fog);

	#ifdef TAA
		TAA_Offset = offsets[framemod8];
	#else
		TAA_Offset = vec2(0.0);
	#endif

	#ifdef TAA_UPSCALING
		gl_Position.xy = (gl_Position.xy*0.5+0.5)*RENDER_SCALE*2.0-1.0;
	#endif
}
