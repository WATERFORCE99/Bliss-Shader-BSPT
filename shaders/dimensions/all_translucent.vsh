#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/bokeh.glsl"
#include "/lib/items.glsl"

uniform float frameTimeCounter;
#include "/lib/Shadow_Params.glsl"

#if defined PHYSICSMOD_OCEAN_SHADER
	#include "/lib/oceans.glsl"
#endif

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

out vec4 lmtexcoord;
out vec4 color;

uniform sampler2D colortex4;
uniform sampler2D noisetex;

#ifdef OVERWORLD_SHADER
	flat out vec3 averageSkyCol_Clouds;
	flat out vec4 lightCol;
	flat out vec3 WsunVec;

	uniform int worldDay;
	#include "/lib/scene_controller.glsl"
#endif

out vec4 normalMat;
out vec3 binormal;
out vec4 tangent;
out vec3 flatnormal;

#ifdef LARGE_WAVE_DISPLACEMENT
	out vec3 largeWaveNormal;
#endif

out vec3 viewVector;

flat out int glass;
#if defined ENTITIES && defined IS_IRIS
	flat out int NAMETAG;
#endif

attribute vec4 at_tangent;
attribute vec4 mc_Entity;
#if defined ENTITIES || defined BLOCKENTITIES
	uniform int entityId;
#endif

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform float sunElevation;

out vec4 tangent_other;

uniform int frameCounter;
uniform float aspectRatio;
uniform float viewHeight;
uniform float viewWidth;
uniform int hideGUI;
uniform float screenBrightness;

uniform int heldItemId;
uniform int heldItemId2;
flat out float HELD_ITEM_BRIGHTNESS;

uniform vec2 texelSize;
uniform int framemod8;
#include "/lib/TAA_jitter.glsl"

#include "/lib/projections.glsl"

float getWave (vec3 pos, float range){
	return pow(1.0-texture2D(noisetex, (pos.xz + frameTimeCounter * WATER_WAVE_SPEED)/125.0).b, 5.0) * WATER_WAVE_STRENGTH * range;
}

vec3 getWaveNormal(vec3 posxz, float range){

	float deltaPos = 0.5;
	vec3 coord = posxz;

	float h0 = getWave(coord,range);
	float h1 = getWave(coord - vec3(deltaPos,0.0,0.0),range);
	float h3 = getWave(coord - vec3(0.0,0.0,deltaPos),range);

	float xDelta = (h1-h0)/deltaPos * 1.5;
	float yDelta = (h3-h0)/deltaPos * 1.5;

	vec3 wave = normalize(vec3(xDelta, yDelta, 1.0-pow(abs(xDelta+yDelta),2.0)));

	return wave;
}

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
 	gl_Position = ftransform();
	#if defined ENTITIES && defined IS_IRIS
		// force out of frustum
		if (entityId == 1599) gl_Position.z -= 10000.0;
	#endif

	#if defined PHYSICSMOD_OCEAN_SHADER && defined PHYSICS_OCEAN
		// basic texture to determine how shallow/far away from the shore the water is
		physics_localWaviness = texelFetch(physics_waviness, ivec2(gl_Vertex.xz) - physics_textureOffset, 0).r;
		// transform gl_Vertex (since it is the raw mesh, i.e. not transformed yet)
		vec4 finalPosition = vec4(gl_Vertex.x, gl_Vertex.y + physics_waveHeight(gl_Vertex.xz, PHYSICS_ITERATIONS_OFFSET, physics_localWaviness, physics_gameTime), gl_Vertex.z, gl_Vertex.w);
		// pass this to the fragment shader to fetch the texture there for per fragment normals
		physics_localPosition = finalPosition.xyz;

		vec3 position = mat3(gl_ModelViewMatrix) * vec3(finalPosition) + gl_ModelViewMatrix[3].xyz;
	#else
		vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;
	#endif

	// lmtexcoord.xy = (gl_MultiTexCoord0).xy;
	lmtexcoord.xy = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	vec2 lmcoord = gl_MultiTexCoord1.xy / 240.0;
	lmtexcoord.zw = lmcoord;

	#ifdef LARGE_WAVE_DISPLACEMENT
		if(mc_Entity.x == 8.0) {
			vec3 playerPos = mat3(gbufferModelViewInverse) * position.xyz;
			#ifdef DISTANT_HORIZONS
				float range = pow(1-pow(1-clamp(1.0 - length(playerPos) / far, 0.0,1.0),3.0),3.0);
			#else
				float range = min(1.0 + pow(length(playerPos) / 256,2.0), 256.0);
			#endif

			vec4 displacedVertex = vec4(gl_Vertex.x, gl_Vertex.y + (getWave(gl_Vertex.xyz + cameraPosition, range)*0.6-0.5), gl_Vertex.z, gl_Vertex.w);
			position = mat3(gl_ModelViewMatrix) * vec3(displacedVertex) + gl_ModelViewMatrix[3].xyz;
		
			playerPos = mat3(gbufferModelViewInverse) * position.xyz;
			largeWaveNormal = getWaveNormal(playerPos + cameraPosition, range);
		}
	#endif

   	vec3 worldpos = toWorldSpace(position);
	#ifdef PLANET_CURVATURE
		float curvature = length(worldpos) / (16*8);
		worldpos.y -= curvature * curvature * CURVATURE_AMOUNT;
	#endif

	position = mat3(gbufferModelView) * worldpos + gbufferModelView[3].xyz;

	#if !defined ENTITIES && !defined HAND
 		gl_Position = toClipSpace4alt(position);
	#endif

	HELD_ITEM_BRIGHTNESS = 0.0;

	#ifdef Hand_Held_lights
		if(heldItemId > 999 || heldItemId2 > 999) HELD_ITEM_BRIGHTNESS = 0.9;
	#endif

	// 1.0 = water mask
	// 0.9 = entity mask
	// 0.8 = reflective entities
	// 0.7 = glass
	// 0.6 = slime & honey
	// 0.5 = ice
	// 0.4 = nether portal
	float mat = 0.0;

	// water mask
	if(mc_Entity.x == 8.0) {
    		mat = 1.0;
  	}

	// translucent entities
	#if defined ENTITIES || defined BLOCKENTITIES
		mat = 0.9;
		if (entityId == 1803) mat = 0.8;
	#endif

	// glass
	if (mc_Entity.x >= 301 && mc_Entity.x <= 317) mat = 0.7;

	// slime & honey
	if (mc_Entity.x == 318 || mc_Entity.x == 319) mat = 0.6;

	// ice
	if (mc_Entity.x == 320) mat = 0.5;

	// nether portal
	if (mc_Entity.x == 321) mat = 0.4;

	#if defined ENTITIES && defined IS_IRIS
		NAMETAG = 0;
		if (entityId == 1600) NAMETAG = 1;
	#endif

	tangent = vec4(normalize(gl_NormalMatrix *at_tangent.rgb),at_tangent.w);
	normalMat = vec4(normalize(gl_NormalMatrix * gl_Normal), mat);

	binormal = normalize(cross(tangent.rgb,normalMat.xyz)*at_tangent.w);

	mat3 tbnMatrix = mat3(tangent.x, binormal.x, normalMat.x,
						tangent.y, binormal.y, normalMat.y,
						tangent.z, binormal.z, normalMat.z);

	#ifdef LARGE_WAVE_DISPLACEMENT
		if(mc_Entity.x == 8.0) {
			largeWaveNormal = normalize(largeWaveNormal * tbnMatrix);
		}else{
			largeWaveNormal = normalMat.xyz;
		}
	#endif

	flatnormal = normalMat.xyz;
	viewVector = normalize(tbnMatrix * position.xyz);

	color = vec4(gl_Color.rgb, 1.0);

	#ifdef OVERWORLD_SHADER
		lightCol.rgb = texelFetch2D(colortex4,ivec2(6,37),0).rgb;
		lightCol.a = float(sunElevation > 1e-5)*2.0 - 1.0;

		averageSkyCol_Clouds = texelFetch2D(colortex4,ivec2(0,37),0).rgb;

		// WsunVec = lightCol.a * normalize(mat3(gbufferModelViewInverse) * sunPosition);

		WsunVec = normalize(mat3(gbufferModelViewInverse) * sunPosition);
		vec3 moonVec = normalize(mat3(gbufferModelViewInverse) * moonPosition);
		vec3 WmoonVec = moonVec;
		if(dot(-moonVec, WsunVec) < 0.9999) WmoonVec = -moonVec;

		WsunVec = mix(WmoonVec, WsunVec, clamp(lightCol.a,0,1));

		readSceneControllerParameters(colortex4, parameters.smallCumulus, parameters.largeCumulus, parameters.altostratus, parameters.fog);
	#endif

	#ifdef TAA_UPSCALING
		gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
	#endif
	#ifdef TAA
		#if defined ENTITIES && defined IS_IRIS
		// remove jitter for nametags lol
			if(entityId != 1600) gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
		#else
			gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
		#endif
	#endif

	#if DOF_QUALITY == 5
		vec2 jitter = clamp(jitter_offsets[frameCounter % 64], -1.0, 1.0);
		jitter = rotate(radians(float(frameCounter))) * jitter;
		jitter.y *= aspectRatio;
		jitter.x *= DOF_ANAMORPHIC_RATIO;

		#if MANUAL_FOCUS == -2
			float focusMul = 0;
		#elif MANUAL_FOCUS == -1
			float focusMul = gl_Position.z - mix(pow(512.0, screenBrightness), 512.0 * screenBrightness, 0.25);
		#else
			float focusMul = gl_Position.z - MANUAL_FOCUS;
		#endif

		vec2 totalOffset = (jitter * JITTER_STRENGTH) * focusMul * 1e-2;
		gl_Position.xy += hideGUI >= 1 ? totalOffset : vec2(0);
	#endif
}