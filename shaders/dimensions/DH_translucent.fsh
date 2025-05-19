#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/tonemaps.glsl"
#include "/lib/projections.glsl"
#include "/lib/util.glsl"
#include "/lib/dither.glsl"

uniform vec2 texelSize;
// uniform int moonPhase;
uniform float frameTimeCounter;

const bool shadowHardwareFiltering = true;
uniform sampler2DShadow shadow;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
#ifdef DISTANT_HORIZONS
	uniform sampler2D dhDepthTex;
	uniform sampler2D dhDepthTex1;
#endif

uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex12;

#include "/lib/sky_gradient.glsl"
#include "/lib/waterBump.glsl"
#include "/lib/Shadow_Params.glsl"

in vec4 pos;
in vec4 gcolor;
in vec4 normals_and_materials;
in vec2 lightmapCoords;
flat in int isWater;

// uniform float far;

// uniform sampler2D colortex4;
flat in vec3 averageSkyCol_Clouds;
flat in vec4 lightCol;
flat in vec3 WsunVec;
flat in vec3 WsunVec2;

#include "/lib/DistantHorizons_projections.glsl"

uniform float near;
float invLinZ (float lindepth){
	return -((2.0*near/lindepth)-far-near)/(far-near);
}

float ld(float dist) {
	return (2.0 * near) / (far + near - dist * (far - near));
}

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
	return (near * far) / (depth * (near - far) + far);
}

uniform int isEyeInWater;
uniform float rainStrength;

#ifdef OVERWORLD_SHADER
	uniform int worldTime;
	uniform int worldDay;

	#include "/lib/scene_controller.glsl"
	#define CLOUDSHADOWSONLY
	#include "/lib/volumetricClouds.glsl"
#endif

float GGX(vec3 n, vec3 v, vec3 l, float r, float f0) {
	r = max(pow(r,2.5), 0.0001);

	vec3 h = l + v;
	float hn = inversesqrt(dot(h, h));

	float dotLH = clamp(dot(h,l)*hn,0.,1.);
	float dotNH = clamp(dot(h,n)*hn,0.,1.) ;
	float dotNL = clamp(dot(n,l),0.,1.);
	float dotNHsq = dotNH*dotNH;

	float denom = dotNHsq * r - dotNHsq + 1.;
	float D = r / (PI * denom * denom);

	float F = f0 + (1. - f0) * exp2((-5.55473*dotLH-6.98316)*dotLH);
	float k2 = .25 * r;

	return dotNL * D * F / (dotLH*dotLH*(1.0-k2)+k2);
}

uniform int framemod8;
#include "/lib/TAA_jitter.glsl"

vec3 rayTrace(vec3 dir, vec3 position,float dither, float fresnel, bool inwater){

	float quality = mix(5.0, SSR_STEPS, fresnel);
	vec3 clipPosition = DH_toClipSpace3(position);
	float rayLength = ((position.z + dir.z * dhFarPlane*sqrt(3.0)) > -dhNearPlane)
					?(-dhNearPlane - position.z) / dir.z
					:dhFarPlane*sqrt(3.0);
	vec3 direction = normalize(DH_toClipSpace3(position+dir*rayLength)-clipPosition);  //convert to clip space
	direction.xy = normalize(direction.xy);

	//get at which length the ray intersects with the edge of the screen
	vec3 maxLengths = (step(0.,direction)-clipPosition) / direction;
	float mult = min(min(maxLengths.x,maxLengths.y),maxLengths.z);

	vec3 stepv = direction * mult / quality * vec3(RENDER_SCALE,1.0);

	vec3 spos = clipPosition*vec3(RENDER_SCALE,1.0) + stepv*dither;
	float minZ = clipPosition.z;
	float maxZ = spos.z+stepv.z*0.5;

	spos.xy += offsets[framemod8]*texelSize*0.5/RENDER_SCALE;

	for (int i = 0; i <= int(quality); i++) {

		// float sp = DH_inv_ld(sqrt(texelFetch2D(colortex12,ivec2(spos.xy/texelSize/4),0).a/65000.0));
		float sp = DH_inv_ld(sqrt(texelFetch2D(colortex12,ivec2(spos.xy/texelSize/4),0).a/64000.0));

		if(sp < max(minZ,maxZ) && sp > min(minZ,maxZ)) return vec3(spos.xy/RENDER_SCALE,sp);
		spos += stepv;

		//small bias
		minZ = maxZ-0.00005/DH_ld(spos.z);

		maxZ += stepv.z;
	}
	return vec3(1.1);
}

vec3 applyBump(mat3 tbnMatrix, vec3 bump, float puddle_values){
	float bumpmult = puddle_values;
	bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);
	return normalize(bump*tbnMatrix);
}

#define FORWARD_SPECULAR
#define FORWARD_ENVIRONMENT_REFLECTION
#define FORWARD_BACKGROUND_REFLECTION
#define FORWARD_ROUGH_REFLECTION

/* RENDERTARGETS:2,7 */
void main() {
	if (gl_FragCoord.x * texelSize.x < 1.0  && gl_FragCoord.y * texelSize.y < 1.0 ) {

		bool iswater = isWater > 0;

		float material = 0.7;
		if(iswater) material = 1.0;

		vec3 normals = normalize(normals_and_materials.xyz);
		if (!gl_FrontFacing) normals = -normals;

		vec3 worldSpaceNormals =  mat3(gbufferModelViewInverse) * normals;

		vec3 viewPos = pos.xyz;
		vec3 playerPos = toWorldSpace(viewPos);
		float transition = exp(-25* pow(clamp(1.0 - length(playerPos)/(far-8),0.0,1.0),2));

		#ifdef DH_OVERDRAW_PREVENTION
			#if OVERDRAW_MAX_DISTANCE == 0
				float maxOverdrawDistance = far;
			#else
				float maxOverdrawDistance = OVERDRAW_MAX_DISTANCE;
			#endif

			if(length(playerPos) < clamp(far-16*4, 16, maxOverdrawDistance) ){ discard; return;}
		#endif

		vec3 waterNormals = worldSpaceNormals;

		if(iswater && abs(worldSpaceNormals.y) > 0.1){
			vec3 waterPos = (playerPos+cameraPosition).xzy;

			vec3 bump = normalize(getWaveNormal(waterPos, playerPos, true));

			float bumpmult = WATER_WAVE_STRENGTH;

			bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);

			waterNormals.xz = bump.xy;
		}

		normals = worldToView(waterNormals);

		gl_FragData[0] = gcolor;
		// float UnchangedAlpha = gl_FragData[0].a;
    
		vec3 Albedo = toLinear(gl_FragData[0].rgb);

		if(iswater){
			#ifdef Vanilla_like_water
				Albedo *= sqrt(luma(Albedo));
			#else
				Albedo = vec3(0.0);
				gl_FragData[0].a = 1.0/255.0;
			#endif
		}

		#ifdef WhiteWorld
			gl_FragData[0].rgb = vec3(0.5);
			gl_FragData[0].a = 1.0;
		#endif

		// diffuse
		vec3 Indirect_lighting = vec3(0.0);
		// vec3 MinimumLightColor = vec3(1.0);
		vec3 Direct_lighting = vec3(0.0);

		#ifdef OVERWORLD_SHADER
			vec3 DirectLightColor = lightCol.rgb/2400.0;

			float NdotL = clamp(dot(worldSpaceNormals, WsunVec),0.0,1.0); 
			NdotL = clamp((-15 + NdotL*255.0) / 240.0  ,0.0,1.0);

			float Shadows = 1.0;

			#ifdef DISTANT_HORIZONS_SHADOWMAP
				vec3 feetPlayerPos_shadow = toWorldSpace(pos.xyz);

				vec3 projectedShadowPosition = toShadowSpaceProjected(feetPlayerPos_shadow);

				//apply distortion
				#ifdef DISTORT_SHADOWMAP
					float distortFactor = calcDistort(projectedShadowPosition.xy);
					projectedShadowPosition.xy *= distortFactor;
				#else
					float distortFactor = 1.0;
				#endif

				float smallbias = -0.0035;

 				bool ShadowBounds = abs(projectedShadowPosition.x) < 1.0-1.5/shadowMapResolution && abs(projectedShadowPosition.y) < 1.0-1.5/shadowMapResolution && abs(projectedShadowPosition.z) < 6.0;

				if(ShadowBounds){
					Shadows = 0.0;
					projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5);

					#ifdef LPV_SHADOWS
						projectedShadowPosition.xy *= 0.8;
					#endif

					Shadows = shadow2D(shadow, projectedShadowPosition + vec3(0.0,0.0, smallbias)).x;
				}
			#endif

			Shadows *= getCloudShadow(playerPos + cameraPosition, WsunVec);

    			Direct_lighting = DirectLightColor * NdotL * Shadows;

    			vec3 AmbientLightColor = averageSkyCol_Clouds/900.0 ;

    			vec3 ambientcoefs = worldSpaceNormals.xyz / dot(abs(worldSpaceNormals.xyz), vec3(1.0));
    			float SkylightDir = ambientcoefs.y*1.5;
    
    			float skylight = max(pow(worldSpaceNormals.y*0.5+0.5,0.1) + SkylightDir, 0.2);
    			AmbientLightColor *= skylight;
		#endif

		#ifndef OVERWORLD_SHADER
			vec3 AmbientLightColor = vec3(0.5);
		#endif

		Indirect_lighting = AmbientLightColor;

		vec3 FinalColor = (Indirect_lighting + Direct_lighting) * Albedo;

		// specular
		#ifdef FORWARD_SPECULAR
			vec3 Reflections_Final = vec3(0.0);
			vec4 Reflections = vec4(0.0);
			vec3 BackgroundReflection = FinalColor; 
			vec3 SunReflection = vec3(0.0);

			float roughness = 0.0;
			float f0 = 0.02;
			// f0 = 0.9;

			vec3 reflectedVector = reflect(normalize(viewPos), normals);
			float normalDotEye = dot(normals, normalize(viewPos));

			float fresnel =  pow(clamp(1.0 + normalDotEye, 0.0, 1.0),5.0);

			fresnel = mix(f0, 1.0, fresnel);

			#ifdef SNELLS_WINDOW
				if(isEyeInWater == 1) fresnel = pow(clamp(1.5 + normalDotEye,0.0,1.0), 25.0);
			#endif

			#if defined FORWARD_ENVIRONMENT_REFLECTION && defined DH_SCREENSPACE_REFLECTIONS
				vec3 rtPos = rayTrace(reflectedVector, viewPos, interleaved_gradientNoise_temporal(), fresnel, false);
				if (rtPos.z < 1.){
					vec3 previousPosition = toPreviousPos(DH_toScreenSpace(rtPos));
					previousPosition.xy = projMAD(dhPreviousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5;
					previousPosition.xy = clamp(previousPosition.xy, 0.0, 1.0);
					Reflections.a = 1.0;
					Reflections.rgb = texture2D(colortex5, previousPosition.xy).rgb;
				}
        		#endif

			#ifdef FORWARD_BACKGROUND_REFLECTION
				BackgroundReflection = skyCloudsFromTex(mat3(gbufferModelViewInverse) * reflectedVector, colortex4).rgb / 1200.0; 
			#endif

			#ifdef WATER_SUN_SPECULAR
				SunReflection = (DirectLightColor * Shadows) * GGX(normalize(normals), -normalize(viewPos), normalize(WsunVec2), roughness, f0) * (1.0-Reflections.a);
			#endif

			Reflections_Final = mix(FinalColor, mix(BackgroundReflection, Reflections.rgb, Reflections.a), fresnel);
			Reflections_Final += SunReflection;

			gl_FragData[0].a = gl_FragData[0].a + (1.0-gl_FragData[0].a) * fresnel;
	
			gl_FragData[0].rgb = clamp(Reflections_Final / gl_FragData[0].a * 0.1,0.0,65000.0);

			if (gl_FragData[0].r > 65000.) gl_FragData[0].rgba = vec4(0.0);
		#else
			gl_FragData[0].rgb = FinalColor * 0.1;
		#endif
	    
		#ifdef DH_OVERDRAW_PREVENTION
			float distancefade = min(max(1.0 - length(playerPos)/clamp(far-16*4, 16, maxOverdrawDistance),0.0)*5,1.0);

			if(texture2D(depthtex0, gl_FragCoord.xy*texelSize).x < 1.0 || distancefade > 0.0){
				gl_FragData[0].a = 0.0;
				material = 0.0;
			}
		#endif

		#if DEBUG_VIEW == debug_DH_WATER_BLENDING
			if(gl_FragCoord.x*texelSize.x > 0.53) gl_FragData[0] = vec4(0.0);
		#endif

		gl_FragData[1] = vec4(Albedo, material);
	}
}