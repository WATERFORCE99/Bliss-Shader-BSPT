#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"

out vec4 pos;
out vec4 gcolor;
	
out vec4 normals_and_materials;
out vec2 lightmapCoords;
flat out int isWater;

uniform sampler2D colortex4;
flat out vec3 averageSkyCol_Clouds;
flat out vec4 lightCol;

#ifdef OVERWORLD_SHADER
	uniform int worldDay;
	#include "/lib/scene_controller.glsl"
#endif

out mat4 normalmatrix;

flat out vec3 WsunVec;
flat out vec3 WsunVec2;
uniform mat4 dhProjection;
uniform vec3 sunPosition;
uniform float sunElevation;

uniform vec2 texelSize;
uniform int framemod8;

#if DOF_QUALITY == 5
	uniform int hideGUI;
	uniform int frameCounter;
	uniform float aspectRatio;
	uniform float screenBrightness;
	uniform float far;
	#include "/lib/bokeh.glsl"
#endif

uniform int framemod4_DH;
#define DH_TAA_OVERRIDE
#include "/lib/TAA_jitter.glsl"

#include "/lib/projections.glsl"
                     
void main() {
	gl_Position = dhProjection * gl_ModelViewMatrix * gl_Vertex;

	vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;
   
	vec3 worldpos = toWorldSpace(position);

	// worldpos.y -= length(worldpos)/(16*2);

	#ifdef PLANET_CURVATURE
		float curvature = length(worldpos) / (16*8);
		worldpos.y -= curvature*curvature * CURVATURE_AMOUNT;
	#endif
	position = mat3(gbufferModelView) * worldpos + gbufferModelView[3].xyz;

	gl_Position = toClipSpace4alt(position);

	pos = gl_ModelViewMatrix * gl_Vertex;

	// vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;

	isWater = 0;
	if (dhMaterialId == DH_BLOCK_WATER){
		isWater = 1;

		// offset water to not look like a full cube
    		// vec3 worldpos = mat3(gbufferModelViewInverse) * position;// + gbufferModelViewInverse[3].xyz ;
		// worldpos.y -= 1.8/16.0;
    		// position = mat3(gbufferModelView) * worldpos;// + gbufferModelView[3].xyz;
	}

	// gl_Position = toClipSpace4alt(position);

	normals_and_materials = vec4(mat3(gbufferModelView) * gl_Normal, 1.0);

	gcolor = gl_Color;
	lightmapCoords = gl_MultiTexCoord1.xy;

	lightCol.rgb = texelFetch2D(colortex4,ivec2(6,37),0).rgb;
	lightCol.a = float(sunElevation > 1e-5)*2.0 - 1.0;

	averageSkyCol_Clouds = texelFetch2D(colortex4,ivec2(0,37),0).rgb;

	#ifdef OVERWORLD_SHADER
		readSceneControllerParameters(colortex4, parameters.smallCumulus, parameters.largeCumulus, parameters.altostratus, parameters.fog);
	#endif

	WsunVec = lightCol.a * normalize(mat3(gbufferModelViewInverse) * sunPosition);
	WsunVec2 = lightCol.a * normalize(sunPosition);

	#ifdef TAA_UPSCALING
		gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
	#endif
	#if defined TAA && defined DH_TAA_JITTER
		gl_Position.xy += offsets[framemod4_DH] * gl_Position.w*texelSize;
	#endif

	#if DOF_QUALITY == 5
		vec2 jitter = clamp(jitter_offsets[frameCounter % 64], -1.0, 1.0);
		jitter = rotate(radians(float(frameCounter))) * jitter;
		jitter.y *= aspectRatio;
		jitter.x *= DOF_ANAMORPHIC_RATIO;

		#if MANUAL_FOCUS == -2
			float focusMul = 0;
		#elif MANUAL_FOCUS == -1
			float focusMul = gl_Position.z + (far / 3.0) - mix(pow(512.0, screenBrightness), 512.0 * screenBrightness, 0.25);
		#else
			float focusMul = gl_Position.z + (far / 3.0) - MANUAL_FOCUS;
		#endif

		vec2 totalOffset = (jitter * JITTER_STRENGTH) * focusMul * 1e-2;
		gl_Position.xy += hideGUI >= 1 ? totalOffset : vec2(0);
	#endif
}