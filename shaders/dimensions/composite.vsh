#include "/lib/settings.glsl"
#include "/lib/util.glsl"

flat out vec2 TAA_Offset;
flat out vec3 WsunVec;

uniform sampler2D colortex4;

uniform float sunElevation;
uniform vec3 sunPosition;
uniform mat4 gbufferModelViewInverse;

#include "/lib/res_params.glsl"

uniform int framemod8;
#include "/lib/TAA_jitter.glsl"

void main() {
	gl_Position = ftransform();

	WsunVec = (float(sunElevation > 1e-5)*2-1.)*normalize(mat3(gbufferModelViewInverse) * sunPosition);

	TAA_Offset = vec2(0.0);
	#ifdef TAA
		TAA_Offset = offsets[framemod8];
	#endif

	#ifdef TAA_UPSCALING
		gl_Position.xy = (gl_Position.xy*0.5+0.5)*RENDER_SCALE*2.0-1.0;
	#endif
}