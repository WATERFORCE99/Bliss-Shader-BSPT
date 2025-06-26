#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/dither.glsl"

#include "/lib/projections.glsl"

uniform sampler2D colortex1;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex14;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;
#ifdef DISTANT_HORIZONS
	uniform sampler2D dhDepthTex0;
#endif

uniform float rainStrength;

#ifdef OVERWORLD_SHADER
	uniform int worldTime;
	uniform int worldDay;

	flat in vec3 WsunVec;

	#include "/lib/scene_controller.glsl"

	uniform sampler2D colortex4;
	#define CLOUDSHADOWSONLY
	#include "/lib/volumetricClouds.glsl"
#endif

in vec2 texcoord;

uniform vec2 texelSize;
uniform vec2 viewSize;
uniform float frameTime;
uniform float frameTimeCounter;
uniform float viewHeight;
uniform float viewWidth;
uniform float aspectRatio;

uniform int hideGUI;

#include "/lib/tonemaps.glsl"
#include "/lib/color_dither.glsl"
#include "/lib/res_params.glsl"
#include "/lib/lensflare.glsl"
#include "/lib/gameplay_effects.glsl"

#if DEBUG_VIEW == debug_LIGHTS && defined LPV_SHADOWS
	uniform usampler1D texCloseLights;
	uniform usampler3D texSortLights;

	#include "/lib/text.glsl"
	#include "/lib/cube/lightData.glsl"
#endif

uniform float near;
uniform float far;

float ld(float dist){
	return (2.0 * near) / (far + near - dist * (far - near));
}

float convertHandDepth_2(in float depth, bool hand) {
	if(!hand) return depth;

	float ndcDepth = depth * 2.0 - 1.0;
	ndcDepth /= MC_HAND_DEPTH;
	return ndcDepth * 0.5 + 0.5;
}

void doCameraGridLines(inout vec3 color, vec2 UV){

	float lineThicknessY = 0.001;
	float lineThicknessX = lineThicknessY/aspectRatio;
  
	float horizontalLines = abs(UV.x-0.33);
	horizontalLines = min(abs(UV.x-0.66), horizontalLines);

	float verticalLines = abs(UV.y-0.33);
	verticalLines = min(abs(UV.y-0.66), verticalLines);

	float gridLines = horizontalLines < lineThicknessX || verticalLines < lineThicknessY ? 1.0 : 0.0;

	if(hideGUI > 0.0) gridLines = 0.0;
	color = mix(color, vec3(1.0),  gridLines);
}

vec3 doMotionBlur(vec2 texcoord, float depth, float noise, bool hand){
	float samples = 4.0;
	vec3 color = vec3(0.0);

	float blurMult = 1.0;
	if(hand) blurMult = 0.0;

	vec3 viewPos = toScreenSpace(vec3(texcoord, depth));

	vec3 previousPosition = toPreviousPos(viewPos);
	previousPosition = toClipSpace3(previousPosition);

	vec2 velocity = texcoord - previousPosition.xy;
  
	// thank you Capt Tatsu for letting me use these
	velocity /= 1.0 + length(velocity); // ensure the blurring stays sane where UV is beyond 1.0 or -1.0
	velocity /= 1.0 + frameTime*1000.0; // ensure the blur radius stays roughly the same no matter the framerate
	velocity *= blurMult * MOTION_BLUR_STRENGTH; // remove hand blur and add user control

	texcoord = texcoord - velocity*(samples*0.5 + noise);

	vec2 screenEdges = 2.0/viewSize;

	for (int i = 0; i < int(samples); i++) {
		texcoord += velocity;
		color += texture2D(colortex7, clamp(texcoord, screenEdges, 1.0-screenEdges)).rgb;
	}

	return color / samples;
}

uniform sampler2D shadowcolor1;

float doVignette(in vec2 texcoord, in float noise){
	float vignette = 1.0-clamp(1.0-length(texcoord-0.5),0.0,1.0);
  
	vignette *= vignette*vignette;
	vignette = 1.0-vignette;
	vignette *= vignette*vignette*vignette*vignette;
  
	// stop banding
	vignette = vignette + vignette*(noise-0.5)*0.01;
  
	return mix(1.0, vignette, VIGNETTE_STRENGTH);
}

vec3 applyFishEye(vec2 uv, vec3 color) {
	vec2 coords = uv;
	coords = (coords - 0.5) * 2.0;

	vec2 coordOffset = vec2(0.0);
	coordOffset.x = (1.0 - coords.y * coords.y) * coords.x;
	coordOffset.y = (1.0 - coords.x * coords.x) * coords.y;
	coordOffset *= 0.1 * FISHEYE_STRENGTH;

	vec2 fisheyeUV = uv - coordOffset;

	fisheyeUV = clamp(fisheyeUV, vec2(0.0), vec2(1.0));

	return texture2D(colortex7, fisheyeUV).rgb;
}

void main() {
	float noise = blueNoise();

	vec3 COLOR = texture2D(colortex7,texcoord).rgb;

	#ifdef MOTION_BLUR
		float depth = texture2D(depthtex0, texcoord*RENDER_SCALE).r;
		bool hand = depth < 0.56;
		float depth2 = convertHandDepth_2(depth, hand);

		COLOR = doMotionBlur(texcoord, depth2, noise, hand);
	#endif

	#ifdef FISHEYE_EFFECT
		COLOR = applyFishEye(texcoord, COLOR);
	#endif

	#ifdef OVERWORLD_SHADER
		#ifdef LENS_FLARE
			if(isEyeInWater == 0 && WsunVec.y > 0.0){
				vec3 sunNDC = toNDC3(WsunVec);
				vec2 sunPos = sunNDC.xy * 0.5 + 0.5;

				float screenVis = smoothstep(0.5, 0.45, abs(sunPos.x - 0.5)) * smoothstep(0.5, 0.45, abs(sunPos.y - 0.5));
				float depthVis = step(1.0, texture2D(depthtex0, sunPos).x);
				#ifdef DISTANT_HORIZONS
					depthVis *= step(1.0, texture2D(dhDepthTex0, sunPos).x);
				#endif

				float cloudVis = 1.0;
				#if defined VOLUMETRIC_CLOUDS && (defined CloudLayer0 || defined CloudLayer1 || defined CloudLayer2)
					cloudVis = getSunOcculsion(cameraPosition, WsunVec);
					cloudVis = clamp(1.0 - cloudVis * 32.0, 0.0, 1.0);
				#endif

				float sunVis = screenVis * depthVis * cloudVis;

				vec3 lf = lensflare(texcoord, sunPos) * sunVis;
				COLOR += lf;
			}
		#endif
	#endif

	#if defined LOW_HEALTH_EFFECT || defined DAMAGE_TAKEN_EFFECT || defined WATER_ON_CAMERA_EFFECT  
		// for making the fun, more fun
		applyGameplayEffects(COLOR, texcoord, noise);
	#endif

	#ifdef VIGNETTE
		COLOR *= doVignette(texcoord, noise);
	#endif
  
	#ifdef CAMERA_GRIDLINES
		doCameraGridLines(COLOR, texcoord);
	#endif

	#if DEBUG_VIEW == debug_LIGHTS && defined LPV_SHADOWS
		beginText(ivec2(gl_FragCoord.xy * 0.25), ivec2(0, viewHeight*0.25));
		for (int i = 0; i < LPV_SHADOWS_LIGHT_COUNT; i++) {
			uint data = texelFetch(texCloseLights, i, 0).r;
			printString((_L, _i, _g, _h, _t, _space));
			printInt(i);
			float dist;
			ivec3 pos;
			uint id;
			if (!getLightData(data, dist, pos, id)) {
				printString((_colon, _space, _n, _u, _l, _l));
			} else {
				printString((_colon, _space, _d, _colon, _space));
				printFloat(dist);
				printString((_comma, _space, _x, _colon, _space));
				printInt(pos.x - 15);
				printString((_comma, _space, _y, _colon, _space));
				printInt(pos.y - 15);
				printString((_comma, _space, _z, _colon, _space));
				printInt(pos.z - 15);
				printString((_comma, _space, _i, _d, _colon, _space));
				printInt(int(id));
			}
			printLine();
		}
		endText(COLOR);

		int curLight = int(frameTimeCounter * 2.0) % LPV_SHADOWS_LIGHT_COUNT;
		ivec3 coords = ivec3((texcoord - vec2(0.75, 0)) * vec2(4.0, 2.0) * textureSize(texSortLights, 0).xy, curLight);
		if(texcoord.x > 0.75 && texcoord.y < 0.5) {
			COLOR.rgb = vec3(texelFetch(texSortLights, coords, 0).rgb / 4294967295.0);
		}

		beginText(ivec2(gl_FragCoord.xy * 0.25), ivec2(viewWidth *  0.19, viewHeight * 0.135));
		printString((_L, _i, _g, _h, _t, _colon, _space));
		printInt(curLight);
		endText(COLOR);

		vec2 shadowUV = texcoord * vec2(4.0, 2.0);
		if(shadowUV.x < 1.0 && shadowUV.y < 1.0) COLOR = texture2D(shadowcolor1,shadowUV).rgb;
	#endif

	#if DEBUG_VIEW == debug_SHADOWMAP
		vec2 shadowUV = texcoord * vec2(2.0, 1.0) ;

		if(shadowUV.x < 1.0 && shadowUV.y < 1.0 && hideGUI == 1) COLOR = texture2D(shadowcolor1,shadowUV).rgb;
	#elif DEBUG_VIEW == debug_DEPTHTEX0
		COLOR = vec3(ld(texture2D(depthtex0, texcoord*RENDER_SCALE).r));
	#elif DEBUG_VIEW == debug_DEPTHTEX1
		COLOR = vec3(ld(texture2D(depthtex1, texcoord*RENDER_SCALE).r));
	#endif

	gl_FragColor.rgb = COLOR;
}