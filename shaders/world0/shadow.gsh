#version 330 compatibility

layout (triangles) in;
layout (triangle_strip) out;

#include "/lib/settings.glsl"

#define OVERWORLD_SHADER

#ifdef LPV_SHADOWS
	// limit vertex output to light count to reduce overhead
	// can be slow when the shader wants to output too many vertices, even if they aren't outputted
	// there are 3 vertices for the regular shadows, and up to 3x5 for each light
	#if LPV_SHADOWS_LIGHT_COUNT == 1
		layout (max_vertices = 18) out;
	#elif LPV_SHADOWS_LIGHT_COUNT == 2
		layout (max_vertices = 33) out;
	#elif LPV_SHADOWS_LIGHT_COUNT == 3
		layout (max_vertices = 48) out;
	#elif LPV_SHADOWS_LIGHT_COUNT == 4
		layout (max_vertices = 63) out;
	#elif LPV_SHADOWS_LIGHT_COUNT == 5
		layout (max_vertices = 78) out;
	#elif LPV_SHADOWS_LIGHT_COUNT == 6
		layout (max_vertices = 93) out;
	#else
		#ifdef TRANSLUCENT_COLORED_SHADOWS
			// colored shadows need more vertex data, so can only push fewer vertices
			layout (max_vertices = 102) out;
		#else
			#if LPV_SHADOWS_LIGHT_COUNT == 7
				layout (max_vertices = 108) out;
			#elif LPV_SHADOWS_LIGHT_COUNT == 8
				layout (max_vertices = 123) out;
			#elif LPV_SHADOWS_LIGHT_COUNT == 9
				layout (max_vertices = 138) out;
			#endif
		#endif
	#endif
#else
	// only 3 shadow vertices
	layout (max_vertices = 3) out;
#endif

in vec4 color[3];
in vec2 texcoord[3];

out vec2 Ftexcoord;
#ifdef TRANSLUCENT_COLORED_SHADOWS
	out vec3 Fcolor;
#endif

#ifdef LPV_SHADOWS
	in vec3 worldPos[3];
	flat in vec3 worldNormal[3];
	flat out int render;

	#include "/lib/cube/emit.glsl"
	#include "/lib/cube/lightData.glsl"

	uniform usampler1D texCloseLights;
	uniform vec3 cameraPosition;
	uniform vec3 previousCameraPosition;
	#ifdef LPV_HAND_SHADOWS
		uniform vec3 relativeEyePosition;
		uniform vec3 playerLookVector;
	#endif
#endif

void main() {
	#ifdef LPV_SHADOWS
		for (int i = 0; i < LPV_SHADOWS_LIGHT_COUNT; i++) {
			uint data = texelFetch(texCloseLights, i, 0).r;
			float dist;
			ivec3 pos;
			uint id;
			if (getLightData(data, dist, pos, id)) {
				vec3 lightPos = -fract(previousCameraPosition) + (previousCameraPosition - cameraPosition) + vec3(pos) - 14.5;
				#ifdef LPV_HAND_SHADOWS
					if (dist < 0.0001) {
						vec2 viewDir = normalize(playerLookVector.xz) * 0.25;
						lightPos = -relativeEyePosition + vec3(viewDir.x, 0, viewDir.y);
					}
				#endif

				vec3 dists = vec3(length(worldPos[0] - lightPos), length(worldPos[1] - lightPos), length(worldPos[2] - lightPos));
				if (
					// check that all vertices are in range, don't want to render unnecessary vertices
					all(lessThan(dists, vec3(14))) &&
					// discard backfaces, if they are closer than 1 block, since those can be the faces from the light
					(max(max(dists.x, dists.y), dists.z) > 1.45 || dot(worldNormal[0], worldPos[0] - lightPos) < 0)) {
					for (int f = 0; f < 6; f++) {
						render = i + f * 16;
						emitCubemap(directionMatices[f], cubeFaceOffsets[f]*2+renderOffsets[i]*2, lightPos);
					}
				}
			} else {
				// since lights are sorted, if one light is invalid all followings are aswell
				break;
			}
		}

		render = -1;
	#endif

	for (int i = 0; i < 3; i++) {
		gl_Position = gl_in[i].gl_Position;
		#ifdef LPV_SHADOWS
			gl_Position.xy = gl_Position.xy * 0.8 - 0.2 * gl_Position.w;
		#endif
		Ftexcoord = texcoord[i].xy;
		#ifdef TRANSLUCENT_COLORED_SHADOWS
			Fcolor = color[i].rgb;
		#endif
		EmitVertex();
	}
	EndPrimitive();
}