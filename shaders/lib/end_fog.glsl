// Hash without Sine
// MIT License...
/* Copyright (c)2014 David Hoskins.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.*/
//----------------------------------------------------------------------------------------
// Integer Hash - II
// - Inigo Quilez, Integer Hash - II, 2017
//   https://www.shadertoy.com/view/XlXcW4
//----------------------------------------------------------------------------------------

uvec3 iqint2(uvec3 x){
	const uint k = 1103515245u;

	x = ((x>>8U)^x.yzx)*k;
	x = ((x>>8U)^x.yzx)*k;
	x = ((x>>8U)^x.yzx)*k;

	return x;
}

uvec3 hash(vec2 s){	
	uvec4 u = uvec4(s, uint(s.x) ^ uint(s.y), uint(s.x) + uint(s.y)); // Play with different values for 3rd and 4th params. Some hashes are okay with constants, most aren't.

	return iqint2(u.xyz);
}

//----------------------------------------------------------------------------------------

float vortexBoundRange = 300.0;

vec3 LightSourcePosition(vec3 worldPos, vec3 cameraPos, float vortexBounds){

	// this is static so it can just sit in one place
	vec3 vortexPos = worldPos - vec3(0.0,200.0,0.0);

	vec3 lightningPos = worldPos - cameraPos;

	// snap-to coordinates in worldspace.
	float cellSize = 200.0;
	lightningPos += fract(cameraPos/cellSize)*cellSize - cellSize*0.5;

	// make the position offset to random places (RNG.xyz from non-clearing buffer).
	vec3 randomOffset = (texelFetch2D(colortex4,ivec2(2,1),0).xyz / 150.0) * 2.0 - 1.0;
	lightningPos -= randomOffset * 2.5;

	return mix(lightningPos, vortexPos, vortexBounds);
}

float densityAtPosFog(in vec3 pos){
	pos /= 16.0;
	pos.xz *= 0.5;

	vec3 p = floor(pos);
	vec3 f = fract(pos);

	f = (f*f) * (3.-2.*f);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,192.0);
	vec2 coord =  uv * 0.002;
	vec2 xy = texture2D(noisetex, coord).yx;
	return mix(xy.r,xy.g, f.y);
}

// Create a rising swirl centered around some origin.
void SwirlAroundOrigin(inout vec3 alteredOrigin, vec3 origin){
	float radiance = 2.39996 + alteredOrigin.y/1.5 + frameTimeCounter/50;
	mat2 rotationMatrix  = mat2(vec2(cos(radiance),  -sin(radiance)),  vec2(sin(radiance),  cos(radiance)));

	// make the swirl only happen within a radius
	float SwirlBounds = clamp(sqrt(length(vec3(origin.x, origin.y-100,origin.z)) / 200.0 - 1.0)  ,0.0,1.0);

	alteredOrigin.xz = mix(alteredOrigin.xz * rotationMatrix, alteredOrigin.xz, SwirlBounds);
}

// control where the fog volume should and should not be using a sphere.
void VolumeBounds(inout float Volume, vec3 Origin){
	vec3 Origin2 = (Origin - vec3(0,100,0));
	Origin2.y *= 0.8;
	float Center1 = length(Origin2);

	float Bounds = max(1.0 - Center1 / 75.0, 0.0) * 5.0;

	float radius = 175.0;
	float thickness = 7500.0;
	float Torus = (thickness - clamp(pow(length(vec2(length(Origin.xz) - radius, Origin2.y)),2.0) - radius, 0.0, thickness)) / thickness;

	Origin2.xz *= 0.5;
	Origin2.y -= 100;

	float orb = clamp((1.0 - length(Origin2) / 15.0) * 1.0, 0.0, 1.0);
	Volume = max(Volume - Bounds - Torus, 0);
}

// create the volume shape
float fogShape(in vec3 pos){
	float vortexBounds = clamp(vortexBoundRange - length(pos), 0.0,1.0);
	vec3 samplePos = pos*vec3(1.0,1.0/48.0,1.0);
	float fogYstart = -60;

	// this is below down where you fall to your death.
	float voidZone = max(exp2(-1.0 * sqrt(max(pos.y + 60.0, 0.0))), 0.0) ;

	// swirly swirly :DDDDDDDDDDD
	SwirlAroundOrigin(samplePos, pos);

	float noise = densityAtPosFog(samplePos * 12.0);
	float erosion = 1.0 - densityAtPosFog((samplePos - frameTimeCounter/20) * (96.0 + (1 - noise) * 6.0));

	float clumpyFog = max(exp(noise * -mix(10,4,vortexBounds)) * mix(2,1,vortexBounds) - erosion * 0.3, 0.0);

	// apply limts
	VolumeBounds(clumpyFog, pos);

	return clumpyFog + voidZone;
}

float endFogPhase(vec3 LightPos){
	float mie = exp(length(LightPos) / -50.0);

	return (mie * 10.0) * (mie * 10.0);
}

vec3 LightSourceColors(float vortexBounds, float lightningflash){
	vec3 vortexColor = vec3(END_VORTEX_R, END_VORTEX_G, END_VORTEX_B);
	vec3 lightningColor = vec3(END_LIGHTNING_R, END_LIGHTNING_G, END_LIGHTNING_B) * lightningflash;

	return mix(lightningColor, vortexColor, vortexBounds);
}

vec3 LightSourceLighting(vec3 startPos, vec3 lightPos, float noise, float density, vec3 lightColor, float vortexBound){

	float phase = endFogPhase(lightPos);
	float shadow = 0.0;

	for (int i = 0; i < 3; i++){
		vec3 shadowSamplePos = startPos - lightPos * (0.05 + i * 0.25);
		shadow += fogShape(shadowSamplePos);
	}

	vec3 finalLighting = lightColor * phase * exp(-32.0 * shadow) ;
	finalLighting += lightColor * phase * phase * (1.0 - exp(-shadow * vec3(END_VORTEX_R, END_VORTEX_G, END_VORTEX_B))) * (1.0 - exp(-density * density));

	return finalLighting;
}

//Mie phase function
float phaseEND(float x, float g){
	float gg = g * g;
	return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14;
}

vec4 GetVolumetricFog(
	vec3 viewPosition,
	float dither,
	float dither2
){
	#ifndef TOGGLE_VL_FOG
		return vec4(0.0,0.0,0.0,1.0);
	#endif

	/// -------------  RAYMARCHING STUFF ------------- \\\

	vec3 wpos = mat3(gbufferModelViewInverse) * viewPosition + gbufferModelViewInverse[3].xyz;
	vec3 dVWorld = (wpos-gbufferModelViewInverse[3].xyz);
	vec3 progressW = vec3(0.0);

	float maxLength = min(length(dVWorld), 480.0) / length(dVWorld);

	dVWorld *= maxLength;

	float dL = length(dVWorld);
	float expFactor = 11.0;

	/// -------------  COLOR/LIGHTING STUFF ------------- \\\

	int SAMPLECOUNT = 16;

	vec3 color = vec3(0.0);
	float absorbance = 1.0;

	float CenterdotV = dot(normalize(vec3(0,100,0)-cameraPosition), normalize(wpos + cameraPosition));

	float skyPhase = (0.5 + pow(clamp(normalize(wpos).y * 0.5 + 0.5, 0.0, 1.0), 4.0) * 5.0) * 0.1;

	float lightningflash = texelFetch2D(colortex4,ivec2(1,1),0).x/150.0;

	#if defined LPV_VL_FOG_ILLUMINATION && defined EXCLUDE_WRITE_TO_LUT
		float TorchBrightness_autoAdjust = mix(1.0, 30.0, clamp(exp(-10.0*exposure),0.0,1.0)) / 5.0;
	#endif

	for (int i = 0; i < SAMPLECOUNT; i++) {
		float d = (pow(expFactor, float(i+dither)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
		float dd = pow(expFactor, float(i+dither2)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);

		vec3 progressW = gbufferModelViewInverse[3].xyz+cameraPosition + d*dVWorld;

		//------ END STORM EFFECT

			// determine where the vortex area ends and chaotic lightning area begins.
			float vortexBounds = clamp(vortexBoundRange - length(progressW), 0.0, 1.0);
			vec3 lightPosition = LightSourcePosition(progressW, cameraPosition, vortexBounds);
			vec3 lightColors = LightSourceColors(vortexBounds, lightningflash) * 0.5;

			float volumeDensity = fogShape(progressW);

			float clearArea = 1.0-min(max(1.0 - length(progressW - cameraPosition) / 20.0,0.0),1.0);
			float stormDensity = min(volumeDensity, clearArea * clearArea * END_STORM_DENSITY);

			float volumeCoeff = exp(-stormDensity * dd * dL);

			vec3 lightsources = LightSourceLighting(progressW, lightPosition, dither, volumeDensity, lightColors, vortexBounds);
			vec3 indirect = vec3(END_FOG_R, END_FOG_G, END_FOG_B) * (exp((volumeDensity * volumeDensity) * -100.0) * 0.8 + 0.2) * 0.05;

			vec3 stormLighting = indirect + lightsources;

			color += (stormLighting - stormLighting*volumeCoeff) * absorbance;
			absorbance *= volumeCoeff;

		//------ HAZE EFFECT
			// dont make haze contrube to absorbance.
			float hazeDensity = 0.001;
			vec3 hazeLighting = vec3(END_FOG_R, END_FOG_G, END_FOG_B) * skyPhase * 0.5;
			color += (hazeLighting - hazeLighting * exp(-hazeDensity * dd * dL)) * absorbance;

		#if defined FLASHLIGHT && defined FLASHLIGHT_FOG_ILLUMINATION
			vec3 shiftedViewPos = mat3(gbufferModelView)*(progressW-cameraPosition) + vec3(-0.25, 0.2, 0.0);
			vec3 shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos;
			vec2 scaledViewPos = shiftedViewPos.xy / max(-shiftedViewPos.z - 0.5, 1e-7);
			float linearDistance = length(shiftedPlayerPos);
			float shiftedLinearDistance = length(scaledViewPos);

			float lightFalloff = 1.0 - clamp(1.0-linearDistance/FLASHLIGHT_RANGE, -0.999,1.0);
			lightFalloff = max(exp(-30.0 * lightFalloff),0.0);
			float projectedCircle = clamp(1.0 - shiftedLinearDistance*FLASHLIGHT_SIZE,0.0,1.0);

			vec3 flashlightGlow = vec3(FLASHLIGHT_R,FLASHLIGHT_G,FLASHLIGHT_B) * lightFalloff * projectedCircle * 0.5;

			color += (flashlightGlow - flashlightGlow * exp(-max(stormDensity,0.005)*dd*dL)) * absorbance;
		#endif

		//------ LPV FOG EFFECT
			#if defined LPV_VL_FOG_ILLUMINATION && defined EXCLUDE_WRITE_TO_LUT
				color += LPV_FOG_ILLUMINATION(progressW-cameraPosition, dd, dL) * TorchBrightness_autoAdjust * absorbance;
			#endif
	}
	return vec4(color, absorbance);
}

float GetEndFogShadow(vec3 WorldPos, vec3 LightPos){
	float Shadow = 0.0;

	for (int i=0; i < 3; i++){
		vec3 shadowSamplePos = WorldPos - LightPos * (0.01 + pow(i, 0.75) * 0.25); 
		Shadow += fogShape(shadowSamplePos) * END_STORM_DENSITY;
	}
	return clamp(exp2(Shadow * -2.0),0.0,1.0);
}