#include "/lib/res_params.glsl"
#include "/lib/util.glsl"

out vec2 texcoord;
flat out float tempOffsets;

uniform int frameCounter;
uniform int framemod8;
#include "/lib/TAA_jitter.glsl"

void main() {

	gl_Position = ftransform();
	texcoord = gl_MultiTexCoord0.xy;

	tempOffsets = Hammersley(frameCounter%10000);

	#ifdef TAA_UPSCALING
		gl_Position.xy = (gl_Position.xy*0.5+0.5)*RENDER_SCALE*2.0-1.0;
	#endif
}