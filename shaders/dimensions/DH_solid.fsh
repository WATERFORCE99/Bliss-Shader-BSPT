#include "/lib/settings.glsl"
#include "/lib/util.glsl"

in vec4 pos;
in vec4 localPos;
in vec4 gcolor;
in vec2 lightmapCoords;
in vec4 normals_and_materials;
flat in float SSSAMOUNT;
flat in float EMISSIVE;
flat in int dh_material_id;

uniform float far;
// uniform int hideGUI;

#include "/lib/projections.glsl"

uniform sampler2D noisetex;

uniform float frameTimeCounter;

//3D noise from 2d texture
float densityAtPos(in vec3 pos){
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

// https://gitlab.com/jeseibel/distant-horizons-core/-/blob/main/core/src/main/resources/shaders/flat_shaded.frag?ref_type=heads
// Property of Distant Horizons [mod]

const float noiseIntensity = NOISE_INTENSITY;
const int noiseDropoff = NOISE_DROPOFF;

float rand(float co) { return fract(sin(co*(91.3458)) * 47453.5453); }
float rand(vec2 co) { return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453); }
float rand(vec3 co) { return rand(co.xy + rand(co.z)); }

vec3 quantize(const in vec3 val, const in int stepSize) {
	return floor(val * stepSize) / stepSize;
}

vec4 applyNoise(in vec4 fragColor, const in vec3 viewPos, const in float viewDist) {
	// vec3 vertexNormal = normalize(cross(dFdy(vPos.xyz), dFdx(vPos.xyz)));
	// // This bit of code is required to fix the vertex position problem cus of floats in the verted world position varuable
	// vec3 fixedVPos = vPos.xyz + vertexNormal * 0.001;

	float noiseAmplification = noiseIntensity * 0.01;
	float lum = (fragColor.r + fragColor.g + fragColor.b) / 3.0;
	noiseAmplification = (1.0 - pow(lum * 2.0 - 1.0, 2.0)) * noiseAmplification; // Lessen the effect on depending on how dark the object is, equasion for this is -(2x-1)^{2}+1
	noiseAmplification *= fragColor.a; // The effect would lessen on transparent objects
    
	// Mikis idea. make it such that you can control the step amount as distance increases out from where vanilla chunks end.
	// ideally, close = higher steps and far = lower steps
	float highestSteps = NOISE_RESOLUTION;
	float lowestSteps = 2.0;
	float transitionLength = 16.0 * 16.0; // distance it takes to reach the lowest steps from the highest. measured in meters/blocks.
     
	float transitionGradient = clamp((length(viewPos - cameraPosition) - (far+32.0)) / transitionLength,0.0,1.0);
	transitionGradient = sqrt(transitionGradient);// make the gradient appear smoother and less sudden when approaching low steps.low steps.
     
	int dynamicNoiseSteps = int(mix(highestSteps, lowestSteps, transitionGradient));

	// Random value for each position
	float randomValue = rand(quantize(viewPos, dynamicNoiseSteps)) * 2.0 * noiseAmplification - noiseAmplification;

	// Modifies the color
	// A value of 0 on the randomValue will result in the original color, while a value of 1 will result in a fully bright color
	vec3 newCol = fragColor.rgb + (1.0 - fragColor.rgb) * randomValue;
	newCol = clamp(newCol, 0.0, 1.0);

	if (noiseDropoff != 0) {
		float distF = min(viewDist / noiseDropoff, 1.0);
		newCol = mix(newCol, fragColor.rgb, distF); // The further away it gets, the less noise gets applied
	}

	return vec4(newCol,1.0);
}

/* RENDERTARGETS:1,7,8 */
void main() {
    
	#ifdef DH_OVERDRAW_PREVENTION
		#if OVERDRAW_MAX_DISTANCE == 0
			float maxOverdrawDistance = far;
		#else
			float maxOverdrawDistance = OVERDRAW_MAX_DISTANCE;
		#endif

	if(clamp(1.0-length(localPos.xyz)/clamp(far - 32.0,32.0,maxOverdrawDistance),0.0,1.0) > 0.0 ){
		discard;
		return;
	}
	#endif

	vec3 normals = (normals_and_materials.xyz);
	float materials = normals_and_materials.a;
	vec2 PackLightmaps = lightmapCoords;

	// PackLightmaps.y *= 1.05;
	PackLightmaps = min(max(PackLightmaps,0.0)*1.05,1.0);
    
	vec4 data1 = clamp( encode(viewToWorld(normals), PackLightmaps), 0.0, 1.0);
    
	// alpha is material masks, set it to 0.65 to make a DH LODs mask. 
	#ifdef DH_NOISE_TEXTURE
		vec4 Albedo = applyNoise(gcolor, localPos.rgb+cameraPosition, length(localPos.xyz));
	#else
		vec4 Albedo = vec4(gcolor.rgb, 1.0);
	#endif
	// vec3 worldPos = mat3(gbufferModelViewInverse)*pos.xyz + cameraPosition;
	// worldPos = (worldPos*vec3(1.0,1./48.,1.0)/4) ;
	// worldPos = floor(worldPos * 4.0 + 0.001) / 32.0;
	// float noiseTexture = densityAtPos(worldPos* 5000 ) +0.5;

	// float noiseFactor = max(1.0 - 0.3 * dot(Albedo.rgb, Albedo.rgb),0.0);
	// Albedo.rgb *= pow(noiseTexture, 0.6 * noiseFactor);
	// Albedo.rgb *= (noiseTexture*noiseTexture)*0.5 + 0.5;

	#ifdef AEROCHROME_MODE
		if(dh_material_id == DH_BLOCK_LEAVES || dh_material_id == DH_BLOCK_WATER) { // leaves and waterlogged blocks
			float grey = dot(Albedo.rgb, vec3(0.2, 1.0, 0.07));
			Albedo.rgb = mix(vec3(grey), aerochrome_color, 0.7);

		} else if(dh_material_id == DH_BLOCK_GRASS) { // grass
			Albedo.rgb = mix(Albedo.rgb, aerochrome_color, 1.0 - Albedo.g);
		}
	#endif

	#ifdef WhiteWorld
		Albedo.rgb = vec3(0.5);
	#endif
    
	gl_FragData[0] = vec4(encodeVec2(Albedo.x,data1.x),	encodeVec2(Albedo.y,data1.y),	encodeVec2(Albedo.z,data1.z),	encodeVec2(data1.w, materials));
    
	gl_FragData[1].a = 0.0;
    
	#if EMISSIVE_TYPE == 0
		gl_FragData[2].a = 0.0;
	#else
		gl_FragData[2].a = EMISSIVE;
	#endif

	#if SSS_TYPE == 0
		gl_FragData[2].b = 0.0;
	#else
		gl_FragData[2].b = SSSAMOUNT;
	#endif
}