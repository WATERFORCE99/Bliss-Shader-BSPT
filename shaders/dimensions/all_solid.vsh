#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/bokeh.glsl"
#include "/lib/blocks.glsl"
#include "/lib/entities.glsl"
#include "/lib/items.glsl"

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/


#if defined HAND || !defined MC_NORMAL_MAP
	#undef POM
#endif

#ifdef POM
	#define MC_NORMAL_MAP
#endif

varying vec4 color;
varying float VanillaAO;

varying vec4 lmtexcoord;
varying vec4 normalMat;

// #ifdef POM
	varying vec4 vtexcoordam; // .st for add, .pq for mul
	varying vec4 vtexcoord;
// #endif

#ifdef MC_NORMAL_MAP
	varying vec4 tangent;
	attribute vec4 at_tangent;
	varying vec3 FlatNormals;
#endif

uniform float frameTimeCounter;
const float PI48 = 150.796447372*WAVY_SPEED;
float pi2wt = PI48*frameTimeCounter;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

uniform int blockEntityId;
uniform int entityId;
flat varying float blockID;

uniform int heldItemId;
uniform int heldItemId2;
flat varying float HELD_ITEM_BRIGHTNESS;

flat varying int NameTags;

uniform int frameCounter;
uniform float far;
uniform float aspectRatio;
uniform float viewHeight;
uniform float viewWidth;
uniform int hideGUI;
uniform float screenBrightness;
uniform int isEyeInWater;

flat varying float SSSAMOUNT;
flat varying float EMISSIVE;
flat varying int LIGHTNING;
flat varying int PORTAL;
flat varying int SIGN;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec2 texelSize;

uniform int framemod8;
#include "/lib/TAA_jitter.glsl"
							
#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec4 toClipSpace3(vec3 viewSpacePosition) {
	return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition),-viewSpacePosition.z);
}

vec2 calcWave(in vec3 pos) {
	float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec2 ret = (sin(pi2wt*vec2(0.0063,0.0015)*4. - pos.xz + pos.y*0.05)+0.1)*magnitude;
	return ret;
}

vec3 calcMovePlants(in vec3 pos) {
	vec2 move1 = calcWave(pos );
	float move1y = -length(move1);
	return vec3(move1.x,move1y,move1.y)*5.*WAVY_STRENGTH;
}

vec3 calcWaveLeaves(in vec3 pos, in float fm, in float mm, in float ma, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5) {
	float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec3 ret = (sin(pi2wt*vec3(0.0063,0.0224,0.0015)*1.5 - pos))*magnitude;
	return ret;
}

vec3 calcMoveLeaves(in vec3 pos, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5, in vec3 amp1, in vec3 amp2) {
	vec3 move1 = calcWaveLeaves(pos, 0.0054, 0.0400, 0.0400, 0.0127, 0.0089, 0.0114, 0.0063, 0.0224, 0.0015) * amp1;
	return move1*5.*WAVY_STRENGTH;
}

#define SEASONS_VSH
#include "/lib/climate_settings.glsl"

uniform sampler2D noisetex;//depth
float densityAtPos(in vec3 pos) {
	pos /= 18.;
	pos.xz *= 0.5;
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,193.0);
	vec2 coord =  uv / 512.0;
	
	//The y channel has an offset to avoid using two textures fetches
	vec2 xy = texture2D(noisetex, coord).yx;

	return mix(xy.r,xy.g, f.y);
}

vec3 viewToWorld(vec3 viewPos) {
	vec4 pos;
	pos.xyz = viewPos;
	pos.w = 0.0;
	pos = gbufferModelViewInverse * pos;
	return pos.xyz;
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
		if (entityId == 1599) gl_Position.z -= 10000;
	#endif

	vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;

    /////// ----- COLOR STUFF ----- ///////
	color = gl_Color;

	VanillaAO = 1.0 - clamp(color.a,0,1);
	if (color.a < 0.3) color.a = 1.0; // fix vanilla ao on some custom block models.

    /////// ----- RANDOM STUFF ----- ///////
	// gl_TextureMatrix[0] for animated things like charged creepers
	lmtexcoord.xy = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	// #ifdef POM
	vec2 midcoord = (gl_TextureMatrix[0] *  mc_midTexCoord).st;
	vec2 texcoordminusmid = lmtexcoord.xy-midcoord;
	vtexcoordam.pq  = abs(texcoordminusmid)*2;
	vtexcoordam.st  = min(lmtexcoord.xy,midcoord-texcoordminusmid);
	vtexcoord.xy    = sign(texcoordminusmid)*0.5+0.5;
	// #endif

	vec2 lmcoord = gl_MultiTexCoord1.xy / 240.0; 
	lmtexcoord.zw = lmcoord;

	#ifdef MC_NORMAL_MAP
		vec3 alterTangent = at_tangent.rgb;

		tangent = vec4(normalize(gl_NormalMatrix * alterTangent.rgb), at_tangent.w);
	#endif

	normalMat = vec4(normalize(gl_NormalMatrix * gl_Normal), 1.0);

	FlatNormals = normalMat.xyz;

	blockID = mc_Entity.x ;

	if(blockID == BLOCK_GROUND_WAVING_VERTICAL || blockID == BLOCK_GRASS_SHORT || blockID == BLOCK_GRASS_TALL_LOWER || blockID == BLOCK_GRASS_TALL_UPPER ) normalMat.a = 0.60;

	PORTAL = 0;
	SIGN = 0;

	#if defined WORLD && !defined HAND
		if(blockEntityId == BLOCK_SIGN) SIGN = 1;

		if(blockEntityId == BLOCK_END_PORTAL || blockEntityId == 187) PORTAL = 1;
	#endif

	NameTags = 0;

	#ifdef ENTITIES

		// disallow POM to work on item frames.
		if(entityId == ENTITY_ITEM_FRAME) SIGN = 1;

		// try and single out nametag text and then discard nametag background
		// if( dot(gl_Color.rgb, vec3(1.0/3.0)) < 1.0) NameTags = 1;
		// if(gl_Color.a < 1.0) NameTags = 1;
		// if(gl_Color.a >= 0.24 && gl_Color.a <= 0.25 ) gl_Position = vec4(10,10,10,1);
		if(entityId == ENTITY_SSS_MEDIUM || entityId == ENTITY_SSS_WEAK || entityId == ENTITY_PLAYER || entityId == 2468) normalMat.a = 0.45;

	#endif

	if(mc_Entity.x == BLOCK_AIR_WAVING) normalMat.a = 0.55;

    /////// ----- EMISSIVE STUFF ----- ///////

		EMISSIVE = 0.0;
		LIGHTNING = 0;
	// if(NameTags > 0) EMISSIVE = 0.9;

	HELD_ITEM_BRIGHTNESS = 0.0;
	#ifdef Hand_Held_lights
		if(heldItemId > 999 || heldItemId2 > 999 ) HELD_ITEM_BRIGHTNESS = 0.9;
	#endif

	// normal block lightsources		
	if(mc_Entity.x >= 100 && mc_Entity.x < 300) EMISSIVE = 0.5;

	// special cases light lightning and beacon beams...	
	#ifdef ENTITIES
		if(entityId == ENTITY_LIGHTNING){
			LIGHTNING = 1;
			normalMat.a = 0.50;
		}
	#endif

    /////// ----- SSS STUFF ----- ///////

	SSSAMOUNT = 0.0;

	#ifdef WORLD
	/////// ----- SSS ON BLOCKS ----- ///////

		// strong
		if (
			mc_Entity.x == BLOCK_GROUND_WAVING || mc_Entity.x == BLOCK_GROUND_WAVING_VERTICAL ||
			mc_Entity.x == BLOCK_GRASS_SHORT || mc_Entity.x == BLOCK_GRASS_TALL_UPPER || mc_Entity.x == BLOCK_GRASS_TALL_LOWER ||
			mc_Entity.x == BLOCK_SSS_STRONG || mc_Entity.x == BLOCK_SAPLING
			/*|| (mc_Entity.x >= 410 && mc_Entity.x <= 415) || (mc_Entity.x >= 402 && mc_Entity.x <= 405) THIS IS FOR MCME NEW TREES.*/
		){
			SSSAMOUNT = 1.0;
		}

		// medium
		if (
			mc_Entity.x == BLOCK_SSS_WEAK || mc_Entity.x == BLOCK_SSS_WEAK_2 || mc_Entity.x == BLOCK_AIR_WAVING ||
			mc_Entity.x == BLOCK_GLOW_LICHEN || mc_Entity.x == BLOCK_SNOW_LAYERS || mc_Entity.x == BLOCK_CARPET ||
			mc_Entity.x == BLOCK_AMETHYST_BUD_MEDIUM || mc_Entity.x == BLOCK_AMETHYST_BUD_LARGE || mc_Entity.x == BLOCK_AMETHYST_CLUSTER ||
			mc_Entity.x == BLOCK_BAMBOO || mc_Entity.x == BLOCK_SAPLING || mc_Entity.x == BLOCK_VINE || mc_Entity.x == BLOCK_CAVE_VINE_BERRIES
		){
			SSSAMOUNT = 0.5;
		}

		// low
		#ifdef MISC_BLOCK_SSS
			if(mc_Entity.x == BLOCK_SSS_WEIRD || mc_Entity.x == BLOCK_GRASS) SSSAMOUNT = max(0.25 * (1-length(position)/64.0), 0.01);
		#endif

		#ifdef ENTITIES
			#ifdef MOB_SSS
	/////// ----- SSS ON MOBS----- ///////
				// strong
				if(entityId == ENTITY_SSS_MEDIUM) SSSAMOUNT = 0.75;
	
				// medium
	
				// low
				if(entityId == ENTITY_SSS_WEAK || entityId == ENTITY_PLAYER) SSSAMOUNT = 0.4;
			#endif
		#endif

		#ifdef BLOCKENTITIES
	 /////// ----- SSS ON BLOCK ENTITIES----- ///////
			// strong

			// medium
			if(blockEntityId == BLOCK_SSS_WEAK_3) SSSAMOUNT = 0.4;

			// low

		#endif

   		vec3 worldpos = mat3(gbufferModelViewInverse) * position + gbufferModelViewInverse[3].xyz;

		#ifdef WAVY_PLANTS
			// also use normal, so up/down facing geometry does not get detatched from its model parts.
			bool InterpolateFromBase = gl_MultiTexCoord0.t < max(mc_midTexCoord.t, abs(viewToWorld(FlatNormals).y));
			if((
				// these wave off of the ground. the area connected to the ground does not wave.
				(InterpolateFromBase && (mc_Entity.x == BLOCK_GRASS_TALL_LOWER || mc_Entity.x == BLOCK_GRASS_SHORT || mc_Entity.x == BLOCK_SAPLING || mc_Entity.x == BLOCK_GROUND_WAVING_VERTICAL))

				// these wave off of the ceiling. the area connected to the ceiling does not wave.
				|| (!InterpolateFromBase && (mc_Entity.x == BLOCK_VINE))

				// these wave off of the air. they wave uniformly
				|| (mc_Entity.x == BLOCK_GRASS_TALL_UPPER || mc_Entity.x == BLOCK_AIR_WAVING)

				#ifndef RP_MODEL_FIX
					|| (InterpolateFromBase && (mc_Entity.x == BLOCK_GROUND_WAVING)) || (mc_Entity.x == BLOCK_CAVE_VINE_BERRIES)
				#endif

			) && length(position) < 64.0){

				vec3 UnalteredWorldpos = worldpos;

				// apply displacement for waving plant blocks
				worldpos += calcMovePlants(worldpos + cameraPosition) * max(lmtexcoord.w,0.5);

				// apply displacement for waving leaf blocks specifically, overwriting the other waving mode. these wave off of the air. they wave uniformly
				if(mc_Entity.x == BLOCK_AIR_WAVING || mc_Entity.x == BLOCK_CAVE_VINE_BERRIES) worldpos = UnalteredWorldpos + calcMoveLeaves(worldpos + cameraPosition, 0.0040, 0.0064, 0.0043, 0.0035, 0.0037, 0.0041, vec3(1.0,0.2,1.0), vec3(0.5,0.1,0.5))*lmtexcoord.w;
			}
		#endif

		#ifdef PLANET_CURVATURE
			float curvature = length(worldpos) / (16*8);
			worldpos.y -= curvature*curvature * CURVATURE_AMOUNT;
		#endif

		position = mat3(gbufferModelView) * worldpos + gbufferModelView[3].xyz;

		gl_Position = toClipSpace3(position);
	#endif

	#if defined Seasons && defined WORLD && !defined ENTITIES && !defined BLOCKENTITIES && !defined HAND
		YearCycleColor(color.rgb, gl_Color.rgb, mc_Entity.x == BLOCK_AIR_WAVING, true);
	#endif

	#ifdef TAA_UPSCALING
		gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
	#endif

	#ifdef TAA
		gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
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