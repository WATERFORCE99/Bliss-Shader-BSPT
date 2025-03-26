#include "/lib/settings.glsl"

in vec4 color;
in vec2 texcoord;

uniform sampler2D texture;
uniform sampler2D normals;
uniform sampler2D noisetex;

flat in float exposure;

in vec4 tangent;
in vec4 normalMat;
uniform float frameTimeCounter;

vec3 toLinear(vec3 sRGB){
	return sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878);
}

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

/* DRAWBUFFERS:2 */

void main() {

	vec4 Albedo = texture2D(texture, texcoord);
	Albedo.rgb = toLinear(Albedo.rgb * color.rgb);

	#if defined SPIDER_EYES || defined BEACON_BEAM || defined GLOWING 

		if(Albedo.a < 0.102 || dot(Albedo.rgb, vec3(0.33333)) < 1.0/255.0) { discard; return; }

		float minimumBrightness = 0.5;

		#ifdef BEACON_BEAM
			minimumBrightness = 10.0;
		#endif

		// float autoBrightnessAdjust = mix(minimumBrightness, 100.0, clamp(exp(-10.0*exposure),0.0,1.0));

		#ifdef DISABLE_VANILLA_EMISSIVES
			vec3 emissiveColor = vec3(0.0);
			Albedo.a = 0.0;
		#else
			vec3 emissiveColor =  Albedo.rgb * color.a ;//* autoBrightnessAdjust;
		#endif
        
		gl_FragData[0] = vec4(emissiveColor*0.1, Albedo.a * sqrt(color.a));
	#endif

	#ifdef ENCHANT_GLINT
		// float autoBrightnessAdjust = mix(0.1, 100.0, clamp(exp(-10.0*exposure),0.0,1.0));

		Albedo.rgb = clamp(Albedo.rgb ,0.0,1.0); // for safety

		#ifdef DISABLE_ENCHANT_GLINT
			vec3 GlintColor = vec3(0.0);
			Albedo.a = 0.0;
		#else
			vec3 GlintColor = Albedo.rgb * Emissive_Brightness;
		#endif

		gl_FragData[0] = vec4(GlintColor*0.1, dot(Albedo.rgb,vec3(0.333)) * Albedo.a);
	#endif
}