//=============== DECLARE UNIFORMS BELOW HERE ===============

//=============== DECLARE UNIFORMS ABOVE HERE ===============

void applySceneControllerParameters(
	out float smallCumulusCoverage, out float smallCumulusDensity,
	out float largeCumulusCoverage, out float largeCumulusDensity,
	out float altostratusCoverage, out float altostratusDensity,
	out float fogA, out float fogB
){
	// these are the default parameters if no "trigger" or custom uniform is being used.
	// do not remove them
	smallCumulusCoverage = CloudLayer0_coverage;
	smallCumulusDensity = CloudLayer0_density;

	largeCumulusCoverage = CloudLayer1_coverage;
	largeCumulusDensity = CloudLayer1_density;

	altostratusCoverage = CloudLayer2_coverage;
	altostratusDensity = CloudLayer2_density;

	fogA = 1.0;
	fogB = 1.0;

	// cloud & fog controlled by daily weather
	#ifdef Daily_Weather
		#ifdef CHOOSE_RANDOM_WEATHER_PROFILE
			int dayCounter = int(clamp(hash11(float(mod(worldDay, 1000))) * 10.0, 0,10));
		#else
			int dayCounter = int(mod(worldDay, 10));
		#endif

		//----------- cloud coverage
		vec3 weatherProfile_cloudCoverage[10] = vec3[](
			vec3(DAY0_l0_coverage, DAY0_l1_coverage, DAY0_l2_coverage),
			vec3(DAY1_l0_coverage, DAY1_l1_coverage, DAY1_l2_coverage),
			vec3(DAY2_l0_coverage, DAY2_l1_coverage, DAY2_l2_coverage),
			vec3(DAY3_l0_coverage, DAY3_l1_coverage, DAY3_l2_coverage),
			vec3(DAY4_l0_coverage, DAY4_l1_coverage, DAY4_l2_coverage),
			vec3(DAY5_l0_coverage, DAY5_l1_coverage, DAY5_l2_coverage),
			vec3(DAY6_l0_coverage, DAY6_l1_coverage, DAY6_l2_coverage),
			vec3(DAY7_l0_coverage, DAY7_l1_coverage, DAY7_l2_coverage),
			vec3(DAY8_l0_coverage, DAY8_l1_coverage, DAY8_l2_coverage),
			vec3(DAY9_l0_coverage, DAY9_l1_coverage, DAY9_l2_coverage)
		);

		//----------- cloud density
		vec3 weatherProfile_cloudDensity[10] = vec3[](
			vec3(DAY0_l0_density, DAY0_l1_density, DAY0_l2_density),
			vec3(DAY1_l0_density, DAY1_l1_density, DAY1_l2_density),
			vec3(DAY2_l0_density, DAY2_l1_density, DAY2_l2_density),
			vec3(DAY3_l0_density, DAY3_l1_density, DAY3_l2_density),
			vec3(DAY4_l0_density, DAY4_l1_density, DAY4_l2_density),
			vec3(DAY5_l0_density, DAY5_l1_density, DAY5_l2_density),
			vec3(DAY6_l0_density, DAY6_l1_density, DAY6_l2_density),
			vec3(DAY7_l0_density, DAY7_l1_density, DAY7_l2_density),
			vec3(DAY8_l0_density, DAY8_l1_density, DAY8_l2_density),
			vec3(DAY9_l0_density, DAY9_l1_density, DAY9_l2_density)
		);

		for (int i = 0; i < 10; i++) {
			weatherProfile_cloudCoverage[i] *= vec3(CloudLayer0_coverage, CloudLayer1_coverage, CloudLayer2_coverage);
			weatherProfile_cloudDensity[i] *= vec3(CloudLayer0_density, CloudLayer1_density, CloudLayer2_density);
		}

		smallCumulusCoverage = weatherProfile_cloudCoverage[dayCounter].x;
		smallCumulusDensity = weatherProfile_cloudDensity[dayCounter].x;

		largeCumulusCoverage = weatherProfile_cloudCoverage[dayCounter].y;
		largeCumulusDensity = weatherProfile_cloudDensity[dayCounter].y;

		altostratusCoverage = weatherProfile_cloudCoverage[dayCounter].z;
		altostratusDensity = weatherProfile_cloudDensity[dayCounter].z;

		//----------- fog density
		vec2 weatherProfile_fogDensity[10] = vec2[](
			vec2(DAY0_ufog_density, DAY0_cfog_density),
			vec2(DAY1_ufog_density, DAY1_cfog_density),
			vec2(DAY2_ufog_density, DAY2_cfog_density),
			vec2(DAY3_ufog_density, DAY3_cfog_density),
			vec2(DAY4_ufog_density, DAY4_cfog_density),
			vec2(DAY5_ufog_density, DAY5_cfog_density),
			vec2(DAY6_ufog_density, DAY6_cfog_density),
			vec2(DAY7_ufog_density, DAY7_cfog_density),
			vec2(DAY8_ufog_density, DAY8_cfog_density),
			vec2(DAY9_ufog_density, DAY9_cfog_density)
		);

		fogA = weatherProfile_fogDensity[dayCounter].x;
		fogB = weatherProfile_fogDensity[dayCounter].y;
	#endif

	// apply rain scene
	smallCumulusCoverage *= 1 + rainStrength * Rain_coverage * 0.5;
	smallCumulusDensity *= 1 + rainStrength * 0.5;

	largeCumulusCoverage *=  1 + rainStrength * Rain_coverage * 0.5;
	largeCumulusDensity *= 1 + rainStrength * 0.5;

	altostratusCoverage *=  1 + rainStrength * Rain_coverage;
	altostratusDensity *= 1 + rainStrength;

//=============== CONFIGURE CUSTOM SCENE PARAMETERS BELOW HERE ===============

//=============== CONFIGURE CUSTOM SCENE PARAMETERS ABOVE HERE ===============

}

// write various parameters within singular pixels of a texture, which is a non-clearing buffer reprojecting the previous frame of itself, onto itself.
// this allows smooth interpolation over time from any old parameter value, to any new parameter value.

// read in vertex stage of post processing passes (deferred, composite), so it only runs on 4 vertices
// pass to fragment stage for use.

// the parameters are stored as such:
// smallCumulus = (coverage, density)
// largeCumulus = (coverage, density)
// altostratus = (coverage, density)
// fog = (uniform fog density, cloudy fog density)
// ... and more, eventually

flat varying struct sceneController {
	vec2 smallCumulus;
	vec2 largeCumulus;
	vec2 altostratus;
	vec2 fog;
} parameters;
 
vec3 writeSceneControllerParameters(
	vec2 uv,
	vec2 smallCumulus,
	vec2 largeCumulus,
	vec2 altostratus,
	vec2 fog
){
	// in colortex4, data is written in a 3x3 pixel area from (1,1) to (3,3)
	// avoiding use of any variation of (0,0) to avoid weird textture wrapping issues
	// 4th compnent/alpha is storing 1/4 res depth so i cant store there lol
 
	/* (1,3) */ bool topLeft = uv.x > 1 && uv.x < 2 && uv.y > 3 && uv.y < 4;
	/* (2,3) */ bool topMiddle = uv.x > 2 && uv.x < 3 && uv.y > 3 && uv.y < 4;
	// /* (3,3) */ bool topRight = uv.x > 3 && uv.x < 5 && uv.y > 3 && uv.y < 4;
	// /* (1,2) */ bool middleLeft = uv.x > 1 && uv.x < 2 && uv.y > 2 && uv.y < 3;
	// /* (2,2) */ bool middleMiddle = uv.x > 2 && uv.x < 3 && uv.y > 2 && uv.y < 3;
	// /* (3,2) */ bool middleRight = uv.x > 3 && uv.x < 5 && uv.y > 2 && uv.y < 3;
	// /* (1,1) */ bool bottomLeft = uv.x > 1 && uv.x < 2 && uv.y > 1 && uv.y < 2;
	// /* (2,1) */ bool bottomMiddle = uv.x > 2 && uv.x < 3 && uv.y > 1 && uv.y < 2;
	// /* (3,1) */ bool bottomRight = uv.x > 3 && uv.x < 5 && uv.y > 1 && uv.y < 2;

	vec3 data = vec3(0.0,0.0,0.0);

	if(topLeft) data = vec3(smallCumulus.xy, largeCumulus.x);
	if(topMiddle) data = vec3(largeCumulus.y, altostratus.xy);

	// if(topRight) data = vec4(groundSunColor,fogSunColor.r);
	// if(middleLeft) data = vec4(groundAmbientColor,fogSunColor.g);
	// if(middleMiddle) data = vec4(fogAmbientColor,fogSunColor.b);
	// if(middleRight) data = vec4(cloudSunColor,cloudAmbientColor.r);
	// if(bottomLeft) data = vec4(cloudAmbientColor.gb,0.0,0.0);
	// if(bottomMiddle) data = vec4(0.0);
	// if(bottomRight) data = vec4(0.0);

	return data;
}
 
void readSceneControllerParameters(
	sampler2D colortex,
	out vec2 smallCumulus,
	out vec2 largeCumulus,
	out vec2 altostratus,
	out vec2 fog
){ 
	// in colortex4, read the data stored within the 3 components of the sampled pixels, and pass it to the fragment stage
	// 4th compnent/alpha is storing 1/4 res depth so i cant store there lol
	vec3 data1 = texelFetch2D(colortex,ivec2(1,3),0).rgb/150.0;
	vec3 data2 = texelFetch2D(colortex,ivec2(2,3),0).rgb/150.0;

	smallCumulus = vec2(data1.x,data1.y);
	largeCumulus = vec2(data1.z,data2.x);
	altostratus = vec2(data2.y,data2.z);
	fog = vec2(0.0);
}