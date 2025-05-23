#ifdef IS_IRIS
	uniform float currentPlayerHealth;
	uniform float maxPlayerHealth;
	uniform float oneHeart;
	uniform float threeHeart;

	uniform float CriticalDamageTaken;
	uniform float MinorDamageTaken;
#else
	uniform bool isDead;
#endif

uniform float exitWater;
uniform float enterWater;
uniform float onFire;
// uniform float exitPowderSnow;
uniform int isEyeInWater;
uniform float rainyAreas;
uniform float smoothBiome_Dry;

uniform ivec2 eyeBrightness;

// uniform float currentPlayerHunger;
// uniform float maxPlayerHunger;

// uniform float currentPlayerArmor;
// uniform float maxPlayerArmor;

// uniform float currentPlayerAir;
// uniform float maxPlayerAir;

// uniform bool is_sneaking;
// uniform bool is_sprinting;
// uniform bool is_hurt;
// uniform bool is_invisible;
// uniform bool is_burning;

// uniform bool is_on_ground;
// uniform bool isSpectator;

float rainExposed = rainStrength * rainyAreas * clamp((eyeBrightness.y/240.0 - 0.9) * 10.0, 0.0, 1.0);

vec3 distortedRain(){
	vec2 uv = texcoord;

	for (float r = 4.0; r > 0.0; r--) {
		vec2 gridSize = viewSize * r * 0.015;
		vec2 p = TAU * uv * gridSize + randNoise(uv * 100.0);
		vec2 s = sin(p);

		vec2 gridCoord = round(uv * gridSize - 0.25) / gridSize;
		vec4 dropData = vec4(randNoise(gridCoord * 200.0), randNoise(gridCoord));

		float timeFactor = max(0.0, 1.0 - fract(frameTimeCounter * (dropData.b + 0.1) + dropData.g) * 5.0);
		float dropShape = (s.x + s.y) * timeFactor * rainExposed * (1.0 -exitWater) * (1.0 -exitWater);

		if (dropData.r < (5.0 - r) * 0.08 && dropShape > 0.5) {
			vec3 normal = normalize(-vec3(cos(p), mix(0.2, 2.0, dropShape - 0.5)));
			vec2 refractedUV = uv - normal.xy * 0.6;
			return texture2D(colortex7, refractedUV).rgb * 0.5;
		}
	}
	return vec3(0.0);
}

float distortionBase(float c, float t){
	vec2 zoomin = 0.5 + (texcoord - 0.5) * (1.0 - pow(1.0 - clamp(-texcoord.y * 0.5 + 0.75, 0.0, 1.0), 1.0)) * (1.0 - pow(1.0 - c, 2.0));
	vec2 UV = zoomin * vec2(aspectRatio, 1.0);
	return texture2D(noisetex, UV * 0.5 - vec2(0.0, t)).b * clamp(-texcoord.y * 0.3 + 0.3, 0.0, 1.0) * c;
}

void applyGameplayEffects(inout vec3 color, in vec2 texcoord, float noise){

	// detect when health is zero
	#ifdef IS_IRIS
		bool isDead = currentPlayerHealth * maxPlayerHealth <= 0.0 && currentPlayerHealth > -1;
	#else
		float oneHeart = 0.0;
		float threeHeart = 0.0;
	#endif

	float distortmask = 0.0;
	float vignette = sqrt(clamp(dot(texcoord*2.0 - 1.0, texcoord*2.0 - 1.0) * 0.5, 0.0, 1.0));

//////////////////////// DAMAGE DISTORTION /////////////////////
	#if defined LOW_HEALTH_EFFECT || defined DAMAGE_TAKEN_EFFECT   
		float heartBeat = pow(sin(frameTimeCounter * 15) * 0.5 + 0.5,2.0) * 0.2 + 0.1;
        
		// apply low health distortion effects
		float damageDistortion = vignette * noise * heartBeat * threeHeart;
        
		// apply critical hit distortion effect
		damageDistortion = mix(damageDistortion, vignette * (0.5 + noise), CriticalDamageTaken) * MOTION_AMOUNT;
        
		// apply death distortion effect
		distortmask = isDead ? vignette * (0.7 + noise*0.3) : damageDistortion;
	#endif

//////////////////////// WATER DISTORTION /////////////////////
	#ifdef WATER_ON_CAMERA_EFFECT
		if(exitWater > 0.0){
			vec3 scale = vec3(1.0,1.0,0.0);

			scale.xy = (isEyeInWater == 1 ? vec2(0.3) : vec2(0.5 * aspectRatio, 0.25 + (exitWater * exitWater) * 0.25));
			scale.z = isEyeInWater == 1 ? 0.0 : exitWater;

			float waterDrops = texture2D(noisetex, (texcoord - vec2(0.0, scale.z)) * scale.xy).r ;
			waterDrops = isEyeInWater == 0 ? sqrt(min(max(waterDrops - (1.0 - sqrt(exitWater)) * 0.7,0.0) * (1.0 + exitWater),1.0)) * 0.3 : 0.0;

			// apply distortion effects for exiting water and under water
			distortmask = max(distortmask, waterDrops);

			float waterDistort = isEyeInWater == 1 ? distortionBase(isEyeInWater, frameTimeCounter * 0.05) * WATER_DISTORTION_AMOUNT : 0.0;
			distortmask = max(distortmask, waterDistort);
		}
    
		if(enterWater > 0.0){
			vec2 zoomTC = 0.5 + (texcoord - 0.5) * (1.0 - (1.0-sqrt(1.0-enterWater)));
			float waterSplash = texture2D(noisetex, zoomTC * vec2(aspectRatio,1.0)).r * DISTORT_EFFECT_AMOUNT * (1.0-enterWater);
 
			distortmask = max(distortmask, waterSplash);
		}
	#endif

//////////////////////// HEAT DISTORTION /////////////////////
	#ifdef ON_FIRE_DISTORT_EFFECT
		float flameDistort = distortionBase(onFire, frameTimeCounter * 0.3) * DISTORT_EFFECT_AMOUNT;
 
		distortmask = max(distortmask, flameDistort);
	#endif

//////////////////////// APPLY DISTORTION /////////////////////
	// all of the distortion will be based around zooming the UV in the center
	vec2 zoomUV = 0.5 + (texcoord - 0.5) * (1.0 - distortmask);
	vec3 distortedColor = texture2D(colortex7, zoomUV).rgb;

	#if defined WATER_ON_CAMERA_EFFECT || defined ON_FIRE_DISTORT_EFFECT
		// apply the distorted water color to the scene, but revert back to before when it ends
		if(exitWater > 0.01 || onFire > 0.01) color = distortedColor;
	#endif

	#ifdef RAIN_ON_CAMERA_EFFECT
		if(isEyeInWater == 0) color += distortedRain();
	#endif

//////////////////////// APPLY COLOR EFFECTS /////////////////////
	#if defined LOW_HEALTH_EFFECT || defined DAMAGE_TAKEN_EFFECT
		vec3 distortedColorLuma =  vec3(1.0, 0.0, 0.0) * dot(distortedColor, vec3(0.21, 0.72, 0.07));
   
		#ifdef LOW_HEALTH_EFFECT
			float colorLuma = dot(color, vec3(0.21, 0.72, 0.07));

			vec3 LumaRedEdges = mix(vec3(colorLuma), vec3(1.0, 0.3, 0.3) * distortedColorLuma.r, vignette);

			// apply color effects for when you are at low health
			color = mix(color, LumaRedEdges, mix(vignette * threeHeart, oneHeart, oneHeart));
		#endif

		#ifdef DAMAGE_TAKEN_EFFECT
			color = mix(color, distortedColorLuma, vignette * sqrt(min(MinorDamageTaken,1.0)));
			color = mix(color, distortedColorLuma, sqrt(CriticalDamageTaken));
		#endif

		if(isDead) color = distortedColorLuma * 0.35;
	#endif
}