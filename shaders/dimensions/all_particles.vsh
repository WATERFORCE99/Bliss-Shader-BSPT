#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/items.glsl"

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

out vec4 color;
uniform sampler2D colortex4;

out vec4 lmtexcoord;

#ifdef LINES
	flat out int SELECTION_BOX;
#endif

#ifdef OVERWORLD_SHADER
	flat out vec3 averageSkyCol_Clouds;
	flat out vec4 lightCol;
	flat out vec3 WsunVec;

	uniform int worldDay;
	#include "/lib/scene_controller.glsl"
#endif

uniform vec3 sunPosition;
uniform float sunElevation;

uniform vec2 texelSize;
uniform int framemod8;
uniform float frameTimeCounter;
uniform ivec2 eyeBrightnessSmooth;

uniform int heldItemId;
uniform int heldItemId2;
flat out float HELD_ITEM_BRIGHTNESS;

#include "/lib/TAA_jitter.glsl"

#include "/lib/projections.glsl"

#ifdef DAMAGE_BLOCK_EFFECT
	out vec4 vtexcoordam; // .st for add, .pq for mul
	out vec4 vtexcoord;

	attribute vec4 mc_midTexCoord;
	out vec4 tangent;
	attribute vec4 at_tangent;
	out vec4 normalMat;
#endif

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
	lmtexcoord.xy = (gl_MultiTexCoord0).xy;
	lmtexcoord.zw = gl_MultiTexCoord1.xy/240.0;

	#ifdef DAMAGE_BLOCK_EFFECT
		vec2 midcoord = (gl_TextureMatrix[0] * mc_midTexCoord).st;
		vec2 texcoordminusmid = lmtexcoord.xy-midcoord;
		vtexcoordam.pq = abs(texcoordminusmid) * 2;
		vtexcoordam.st = min(lmtexcoord.xy,midcoord-texcoordminusmid);
		vtexcoord.xy = sign(texcoordminusmid) * 0.5 + 0.5;

		tangent = vec4(normalize(gl_NormalMatrix * at_tangent.rgb), at_tangent.w);

		normalMat = vec4(normalize(gl_NormalMatrix * gl_Normal), 1.0);
	#endif

	HELD_ITEM_BRIGHTNESS = 0.0;

	#ifdef Hand_Held_lights
		if(heldItemId > 999 || heldItemId2 > 999) HELD_ITEM_BRIGHTNESS = 0.9;
	#endif

	#ifdef WEATHER
		vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;

   		vec3 worldpos = toWorldSpaceCamera(position);
		bool istopv = worldpos.y > cameraPosition.y + 5.0 && lmtexcoord.w > 0.99;

		if(!istopv){
			worldpos.xyz -= cameraPosition - vec3(2.0,0.0,2.0) * min(max(eyeBrightnessSmooth.y/240.0-0.95,0.0)*11.0,1.0);
		}else{
			worldpos.xyz -= cameraPosition ;
		}

		position = mat3(gbufferModelView) * worldpos + gbufferModelView[3].xyz;

		gl_Position = toClipSpace4alt(position);
	#else
		gl_Position = ftransform();

		#ifdef TAA_UPSCALING
			gl_Position.xy = (gl_Position.xy + gl_Position.w) * RENDER_SCALE-gl_Position.w;
		#endif
		#ifdef TAA
			gl_Position.xy += offsets[framemod8] * gl_Position.w * texelSize;
		#endif
	#endif

	color = gl_Color;

	// color.rgb = worldpos;

	#ifdef LINES
		SELECTION_BOX = 0;
		if(dot(color.rgb,vec3(0.33333)) < 0.00001) SELECTION_BOX = 1;
	#endif

	#ifdef OVERWORLD_SHADER
		lightCol.rgb = texelFetch2D(colortex4, ivec2(6, 37), 0).rgb;
		lightCol.a = float(sunElevation > 1e-5) * 2.0-1.0;
		averageSkyCol_Clouds = texelFetch2D(colortex4, ivec2(0, 37), 0).rgb;
		WsunVec = lightCol.a * normalize(mat3(gbufferModelViewInverse) * sunPosition);

		readSceneControllerParameters(colortex4, parameters.smallCumulus, parameters.largeCumulus, parameters.altostratus, parameters.fog);
	#endif
}