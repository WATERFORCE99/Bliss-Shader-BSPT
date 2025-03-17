vec3 cosineHemisphereSample(vec2 Xi){
	float theta = 6.28318530718 * Xi.y;

	float r = sqrt(Xi.x);
	return vec3(r * cos(theta), r * sin(theta), sqrt(1.0 - Xi.x));
}

vec3 TangentToWorld(vec3 N, vec3 H){
	vec3 T = normalize(cross(abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0), N));
	vec3 B = cross(N, T);

	return vec3((T * H.x) + (B * H.y) + (N * H.z));
}

////////////////////////////////////////////////////////////////
/////////////////////////////	SSAO ///////////////////////////
////////////////////////////////////////////////////////////////

vec4 BilateralUpscale_SSAO(sampler2D tex, sampler2D depth, vec2 coord, float referenceDepth){
	ivec2 scaling = ivec2(1.0);
	ivec2 posDepth = ivec2(coord) * scaling;
	ivec2 posColor = ivec2(coord);
  	ivec2 pos = ivec2(gl_FragCoord.xy*texelSize + 1);

	ivec2 getRadius[4] = ivec2[](
   	 	ivec2(-2,-2),
	  	ivec2(-2, 0),
		ivec2( 0, 0),
		ivec2( 0,-2)
  	);

	#ifdef DISTANT_HORIZONS
		float diffThreshold = 0.0005 ;
	#else
		float diffThreshold = 0.005;
	#endif

	vec4 RESULT = vec4(0.0);
	float SUM = 0.0;

	for (int i = 0; i < 4; i++) {
		
		ivec2 radius = getRadius[i];
		#ifdef DISTANT_HORIZONS
			float offsetDepth = sqrt(texelFetch2D(depth, posDepth + radius * scaling + pos * scaling,0).a/65000.0);
		#else
			float offsetDepth = ld(texelFetch2D(depth, posDepth + radius * scaling + pos * scaling, 0).r);
		#endif

		float EDGES = abs(offsetDepth - referenceDepth) < diffThreshold ? 1.0 : 1e-5;
		
		RESULT += texelFetch2D(tex, posColor + radius + pos, 0) * EDGES;
		
		SUM += EDGES;
	}

	// return vec4(1,1,1,1) * SUM/4;

	return RESULT / SUM;
}

////////////////////////////////////////////////////////////////////
/////////////////////////////	RTAO/SSGI ///////////////////////////
////////////////////////////////////////////////////////////////////

vec2 texelSizeInv = 1.0 / texelSize;

vec3 rayTrace_GI(vec3 dir,vec3 position,float dither, float quality){
	vec3 clipPosition = toClipSpace3(position);
	float rayLength = ((position.z + dir.z * far * sqrt(3)) > -near)
					? (-near - position.z) / dir.z
					: far * sqrt(3);
	vec3 direction = normalize(toClipSpace3(position + dir * rayLength) - clipPosition);  //convert to clip space
	direction.xy = normalize(direction.xy);

	//get at which length the ray intersects with the edge of the screen
	vec3 maxLengths = (step(0.0,direction) - clipPosition) / direction;
	float mult = maxLengths.y;

	float biasdist =  1 + clamp(position.z * position.z / 50.0, 0, 2); // shrink sample size as distance increases

	vec3 stepv = direction * mult / quality * vec3(RENDER_SCALE, 1.0) / biasdist;
	lowp vec3 spos = clipPosition * vec3(RENDER_SCALE,1.0) ;

	spos.xy += TAA_Offset * texelSize * 0.5 / RENDER_SCALE;

	spos += stepv * dither;

	int maxIterations = int(quality * clamp(1.0 - position.z / far, 0.1, 1.0));
	for(int i = 0; i < maxIterations; i++){
		#ifdef UseQuarterResDepth
			float sp = sqrt(texelFetch2D(colortex4, ivec2(spos.xy * texelSizeInv / 4), 0).w / 65000.0);
		#else
			float sp = linZ(texelFetch2D(depthtex1, ivec2(spos.xy * texelSizeInv), 0).r);
		#endif
		float currZ = linZ(spos.z);

		float hit = step(sp, currZ);
		float dist = abs(sp - currZ) / currZ;
		vec3 result = mix(vec3(1.1), vec3(spos.xy, invLinZ(sp)) / vec3(RENDER_SCALE, 1.0), hit * step(dist, biasdist * 0.05));
		if (result.z < 1.0){
			result.xy = clamp(result.xy, 0.0, 1.0);
			return result;
		}
		spos += stepv;
	}
	return vec3(1.1);
}

vec3 RT_alternate(vec3 dir, vec3 position, float noise, float stepsizes, bool isLOD, inout float CURVE){

	vec3 worldpos = mat3(gbufferModelViewInverse) * position;

	float dist = 1.0 + 2.0 * length(worldpos) / far; // step length as distance increases
	float stepSize = stepsizes / dist;

	int maxSteps = STEPS;
	vec3 clipPosition = toClipSpace3(position);
	float rayLength = ((position.z + dir.z * far * sqrt(3)) > -sqrt(3) * near)
					? (-sqrt(3) * near - position.z) / dir.z
					: sqrt(3) * far;
	vec3 end = toClipSpace3(position + dir * rayLength) ;
	vec3 direction = end - clipPosition ;  //convert to clip space

	float len = max(abs(direction.x) * texelSizeInv.x, abs(direction.y) * texelSizeInv.y) / stepSize;

	//get at which length the ray intersects with the edge of the screen
	vec3 maxLengths = (step(0.0,direction)-clipPosition) / direction;
	float mult = min(min(maxLengths.x,maxLengths.y),maxLengths.z)*2000.0;

	vec3 stepv = direction / len;

	int iterations = min(int(min(len, mult*len)-2), maxSteps);

	lowp vec3 spos = clipPosition * vec3(RENDER_SCALE, 1.0) + stepv * (noise - 0.5);
	spos.xy += TAA_Offset * texelSize * 0.5 * RENDER_SCALE;

	float biasamount = 0.00005;
	float minZ = spos.z;
	float maxZ = spos.z;
	CURVE = 0.0; 

  	for(int i = 0; i < iterations; i++) {
		if (any(lessThan(spos, vec3(0.0))) || any(greaterThan(spos, vec3(1.0)))) return vec3(1.1);

		#ifdef UseQuarterResDepth
			float sp = invLinZ(sqrt(texelFetch2D(colortex4, ivec2(spos.xy * texelSizeInv/4),0).w / 65000.0));
		#else
			float sp = texelFetch2D(depthtex1, ivec2(spos.xy * texelSizeInv),0).r;
		#endif

		float currZ = linZ(spos.z);
		float nextZ = linZ(sp);

		if(nextZ < currZ && (sp <= max(minZ, maxZ) && sp >= min(minZ, maxZ))) return vec3(spos.xy / RENDER_SCALE, sp);
		
		minZ = maxZ - biasamount / currZ;
		maxZ += stepv.z;

		spos += stepv;

		CURVE += 1.0 / float(iterations);
	}
	return vec3(1.1);
}

vec3 ApplySSRT(
	in vec3 unchangedIndirect,
	in vec3 blockLightColor,
	in vec3 minimumLightColor,

	vec3 viewPos,
	vec3 normal,
	vec3 noise,

	float lightmap, 

	bool isGrass,
	bool isLOD
	){
	int nrays = RAY_COUNT;

	vec3 radiance = vec3(0.0);
	vec3 occlusion = vec3(0.0);
	vec3 skycontribution = vec3(0.0);

	float CURVE = 1.0;
	vec3 bouncedLight = vec3(0.0);

	for (int i = 0; i < nrays; i++){
		int seed = (frameCounter%40000)*nrays+i;
		vec2 ij = fract(R2_samples(seed) + noise.xy);
		lowp vec3 rayDir = TangentToWorld(normal, normalize(cosineHemisphereSample(ij)));

		#if indirect_RTGI == 0 || indirect_RTGI == 1
			vec3 rayHit = RT_alternate(mat3(gbufferModelView) * rayDir, viewPos, noise.z, 10.0, isLOD, CURVE);  // choc sspt 

			CURVE = 1.0 - pow(1.0-pow(1.0 - CURVE, 2.0), 5.0);
			CURVE = mix(CURVE, 1.0, clamp(length(viewPos.z) / far, 0.0, 1.0));
		#elif indirect_RTGI == 2
			vec3 rayHit = rayTrace_GI(mat3(gbufferModelView) * rayDir, viewPos, noise.z, 50.0); // ssr rt
		#endif

		#ifdef OVERWORLD_SHADER
			skycontribution = doIndirectLighting(skyCloudsFromTex(rayDir, colortex4).rgb/1200.0, minimumLightColor, lightmap);
			skycontribution = mix(skycontribution, vec3(luma(skycontribution)), 0.25) + blockLightColor;
		#else
			skycontribution = volumetricsFromTex(rayDir, colortex4, 6).rgb / 1200.0;
		#endif

		radiance += skycontribution;

		if (rayHit.z < 1.0){
			rayHit.xy = clamp(rayHit.xy, 0.0, 1.0);

			#if indirect_RTGI == 1
				bouncedLight = texture2D(colortex5, rayHit.xy).rgb; // vec3 (1,0,0);

			#elif indirect_RTGI == 2
				vec3 previousPosition = mat3(gbufferModelViewInverse) * toScreenSpace(rayHit) + gbufferModelViewInverse[3].xyz + cameraPosition-previousCameraPosition;
				previousPosition = mat3(gbufferPreviousModelView) * previousPosition + gbufferPreviousModelView[3].xyz;
				previousPosition.xy = projMAD(gbufferPreviousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5;

				previousPosition.xy = clamp(previousPosition.xy, 0.0, 1.0);
				bouncedLight = texture2D(colortex5, previousPosition.xy).rgb;
			#endif

			radiance += bouncedLight * GI_Strength;

			occlusion += skycontribution * CURVE;
		}
	}
	return max((radiance - occlusion)/nrays,0.0);
}