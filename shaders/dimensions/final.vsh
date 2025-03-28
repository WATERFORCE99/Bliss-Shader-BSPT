#include "/lib/settings.glsl"

uniform mat4 gbufferModelViewInverse;

out vec2 texcoord;

#ifdef OVERWORLD_SHADER
	uniform vec3 sunPosition;
	uniform sampler2D colortex4;

	flat out vec3 WsunVec;

	#include "/lib/scene_controller.glsl"
#endif

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
	gl_Position = ftransform();
	texcoord = gl_MultiTexCoord0.xy;

	#ifdef OVERWORLD_SHADER
		WsunVec = normalize(mat3(gbufferModelViewInverse) * sunPosition);

		readSceneControllerParameters(colortex4, parameters.smallCumulus, parameters.largeCumulus, parameters.altostratus, parameters.fog);
	#endif
}
