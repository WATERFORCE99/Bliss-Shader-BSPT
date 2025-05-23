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

float cloudVol(in vec3 pos){
	vec3 samplePos = pos*vec3(1.0,1./48.,1.0);

	float Wind = pow(max(pos.y-30,0.0) / 15.0,2.1);

	float Plumes = texture2D(noisetex, (samplePos.xz + Wind)/256.0).b;
	float floorPlumes = clamp(0.3 - exp(Plumes * -6),0,1);
	Plumes *= Plumes;

	float Erosion = densityAtPosFog(samplePos * 400	- frameTimeCounter*10 - Wind*10) *0.7+0.3 ;

	float RoofToFloorDensityFalloff = exp(max(100-pos.y,0.0) / -15);
	float FloorDensityFalloff = pow(exp(max(pos.y-31,0.0) / -3.0),2);
	float RoofDensityFalloff = exp(max(120-pos.y,0.0) / -10);

	float Output = max((RoofToFloorDensityFalloff - Plumes * (1.0-Erosion)) * 2.0,	clamp((FloorDensityFalloff - floorPlumes*0.5) * Erosion ,0.0,1.0));

	return Output;
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

	int SAMPLECOUNT = 16;

	vec3 wpos = mat3(gbufferModelViewInverse) * viewPosition + gbufferModelViewInverse[3].xyz;
	vec3 dVWorld = (wpos-gbufferModelViewInverse[3].xyz);
	vec3 progressW = vec3(0.0);

	float maxLength = min(length(dVWorld), far)/length(dVWorld);

	dVWorld *= maxLength;

	float dL = length(dVWorld);

	float expFactor = 11.0;
	
	/// -------------  COLOR/LIGHTING STUFF ------------- \\\

	vec3 color = vec3(0.0);
	float absorbance = 1.0;

	vec3 hazeColor = normalize(gl_Fog.color.rgb + 1e-6) * 0.25;

	#if defined LPV_VL_FOG_ILLUMINATION && defined EXCLUDE_WRITE_TO_LUT
    	float TorchBrightness_autoAdjust = mix(1.0, 30.0,  clamp(exp(-10.0*exposure),0.0,1.0)) / 5.0;
	#endif

	for (int i = 0; i < SAMPLECOUNT; i++) {
		float d = (pow(expFactor, float(i+dither2)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
		float dd = pow(expFactor, float(i+dither)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);

		progressW = gbufferModelViewInverse[3].xyz + cameraPosition + d*dVWorld;

		float densityVol = cloudVol(progressW);

		//------ PLUME EFFECT
			float plumeDensity = min(densityVol * pow(min(max(100.0-progressW.y,0.0)/30.0,1.0),4.0), pow(clamp(1.0 - length(progressW-cameraPosition)/far,0.0,1.0),2.0) * NETHER_PLUME_DENSITY);
			float plumeVolumeCoeff = exp(-plumeDensity*dd*dL);

			vec3 lighting = vec3(NETHER_PLUME_R, NETHER_PLUME_G, NETHER_PLUME_B) * exp(-15.0*densityVol);

			color += (lighting - lighting * plumeVolumeCoeff) * absorbance;
			absorbance *= plumeVolumeCoeff;

		//------ HAZE EFFECT
			// dont make haze contrube to absorbance.
			float hazeDensity = 0.001;
			float hazeVolumeCoeff = exp(-hazeDensity*dd*dL);
			
			vec3 hazeLighting = hazeColor;
			
			color += (hazeLighting - hazeLighting*hazeVolumeCoeff) * absorbance;

		//------ CEILING SMOKE EFFECT
			float ceilingSmokeDensity = 0.001 * pow(min(max(progressW.y-40.0,0.0)/50.0,1.0),3.0);
			float ceilingSmokeVolumeCoeff = exp(-ceilingSmokeDensity*dd*dL);
			
			vec3 ceilingSmoke = vec3(0.1);

			color += (ceilingSmoke - ceilingSmoke*ceilingSmokeVolumeCoeff) * (absorbance*0.5+0.5);
			absorbance *= ceilingSmokeVolumeCoeff;

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

				color += (flashlightGlow - flashlightGlow * exp(-max(plumeDensity,0.005)*dd*dL)) * absorbance;
			#endif

		//------ LPV FOG EFFECT
			#if defined LPV_VL_FOG_ILLUMINATION && defined EXCLUDE_WRITE_TO_LUT
				color += LPV_FOG_ILLUMINATION(progressW-cameraPosition, dd, dL) * TorchBrightness_autoAdjust * absorbance;
			#endif

	}
	return vec4(color, absorbance);
}