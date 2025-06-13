// this file contains all things for seasons, weather, and biome specific settings.

uniform float Summer;
uniform float Autumn;
uniform float Winter;
uniform float Spring;

uniform float smoothSwamps;
uniform float smoothJungles;
uniform float smoothDarkForests;
uniform float smoothBiome_Snowy;
uniform float smoothBiome_Dry;

uniform float snowStorm;
uniform float sandStorm;
uniform float sandStorm_red;

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////// SEASONS //////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

#ifdef Seasons
	#ifdef SEASONS_VSH

		void YearCycleColor(
			inout vec3 FinalColor,
			vec3 glcolor,

			bool isLeaves,
			bool isPlants
		){
			// colors for things that arent leaves and using the tint index.
			vec3 SummerCol = vec3(Summer_R, Summer_G, Summer_B);
			vec3 AutumnCol = vec3(Fall_R, Fall_G, Fall_B);
			vec3 WinterCol = vec3(Winter_R, Winter_G, Winter_B) ;
			vec3 SpringCol = vec3(Spring_R, Spring_G, Spring_B);

			// decide if you want to replace biome colors or tint them.
			SummerCol *= glcolor;
			AutumnCol *= glcolor;
			WinterCol *= glcolor;
			SpringCol *= glcolor;

			// do leaf colors different because thats cool and i like it
			if(isLeaves) {
				SummerCol = vec3(Summer_Leaf_R, Summer_Leaf_G, Summer_Leaf_B);
				AutumnCol = vec3(Fall_Leaf_R, Fall_Leaf_G, Fall_Leaf_B);
				WinterCol = vec3(Winter_Leaf_R, Winter_Leaf_G, Winter_Leaf_B);
				SpringCol = vec3(Spring_Leaf_R, Spring_Leaf_G, Spring_Leaf_B);

				SummerCol *= glcolor;
				AutumnCol *= glcolor;
				WinterCol *= glcolor;
				SpringCol *= glcolor;
			}

			// lerp all season colors together
			vec3 SummerToFall = mix(SummerCol, AutumnCol, Summer);
			vec3 FallToWinter = mix(SummerToFall, WinterCol, Autumn);
			vec3 WinterToSpring = mix(FallToWinter, SpringCol, Winter);
			vec3 SpringToSummer = mix(WinterToSpring, SummerCol, Spring);

			// make it so that you only have access to parts of the texture that use the tint index
			#ifdef DH_SEASONS
				bool IsTintIndex = isPlants || isLeaves;
			#else
				bool IsTintIndex = floor(dot(glcolor,vec3(0.5))) < 1.0;  
			#endif

			// multiply final color by the final lerped color, because it contains all the other colors.
			if(IsTintIndex) FinalColor = SpringToSummer;
		}
	#endif
#endif

///////////////////////////////////////////////////////////////////////////////
///////////////////////////// BIOME SPECIFICS /////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

#ifdef PER_BIOME_ENVIRONMENT

	// these range 0.0-1.0. they will never overlap.
	float Inbiome = smoothJungles + smoothSwamps + smoothDarkForests + smoothBiome_Snowy + smoothBiome_Dry;

	void BiomeFogColor(inout vec3 FinalFogColor){		

		vec3 BiomeColors = vec3(0.0);
		BiomeColors.r = smoothSwamps*SWAMP_R + smoothJungles*JUNGLE_R + smoothDarkForests*DARKFOREST_R + smoothBiome_Snowy*SNOWY_R + snowStorm*0.6 + smoothBiome_Dry*DRY_R + sandStorm*1.0 + sandStorm_red*1.0;
		BiomeColors.g = smoothSwamps*SWAMP_G + smoothJungles*JUNGLE_G + smoothDarkForests*DARKFOREST_G + smoothBiome_Snowy*SNOWY_G + snowStorm*0.8 + smoothBiome_Dry*DRY_G + sandStorm*0.85 + sandStorm_red*0.3;
		BiomeColors.b = smoothSwamps*SWAMP_B + smoothJungles*JUNGLE_B + smoothDarkForests*DARKFOREST_B + smoothBiome_Snowy*SNOWY_B + snowStorm*1.0 + smoothBiome_Dry*DRY_B + sandStorm*0.4 + sandStorm_red*0.2;

		// insure the biome colors are locked to the fog shape and lighting, but not its orignal color.
		BiomeColors *= max(dot(FinalFogColor,vec3(0.33333)), MIN_LIGHT_AMOUNT*0.025);

		// interpoloate between normal fog colors and biome colors. the transition speeds are conrolled by the biome uniforms.
		FinalFogColor = mix(FinalFogColor, BiomeColors, Inbiome);
	}

	void BiomeFogDensity(
		inout vec4 UniformDensity,
		inout vec4 CloudyDensity,
		float maxDistance
	){

		vec2 BiomeFogDensity = vec2(0.0); // x = uniform  ||  y = cloudy

		BiomeFogDensity.x = smoothSwamps*SWAMP_UNIFORM_DENSITY + smoothJungles*JUNGLE_UNIFORM_DENSITY + smoothDarkForests*DARKFOREST_UNIFORM_DENSITY + smoothBiome_Snowy*SNOWY_UNIFORM_DENSITY + snowStorm*0.01 + smoothBiome_Dry*DRY_UNIFORM_DENSITY + sandStorm*0.0 + sandStorm_red*0.0;
		BiomeFogDensity.y = smoothSwamps*SWAMP_CLOUDY_DENSITY + smoothJungles*JUNGLE_CLOUDY_DENSITY + smoothDarkForests*DARKFOREST_CLOUDY_DENSITY + smoothBiome_Snowy*SNOWY_CLOUDY_DENSITY + snowStorm*0.5 + smoothBiome_Dry*DRY_CLOUDY_DENSITY + sandStorm*0.5 + sandStorm_red*0.5;

		UniformDensity = UniformDensity + vec4(BiomeFogDensity.x) * Inbiome * maxDistance;
		CloudyDensity  = CloudyDensity + vec4(BiomeFogDensity.y) * Inbiome * maxDistance;
	}

	float BiomeVLFogColors(inout vec3 DirectLightCol, inout vec3 IndirectLightCol){

		vec3 BiomeColors = vec3(0.0);
		BiomeColors.r = smoothSwamps*SWAMP_R + smoothJungles*JUNGLE_R + smoothDarkForests*DARKFOREST_R + smoothBiome_Snowy*SNOWY_R + snowStorm*0.6 + smoothBiome_Dry*DRY_R + sandStorm*1.0 + sandStorm_red*1.0;
		BiomeColors.g = smoothSwamps*SWAMP_G + smoothJungles*JUNGLE_G + smoothDarkForests*DARKFOREST_G + smoothBiome_Snowy*SNOWY_G + snowStorm*0.8 + smoothBiome_Dry*DRY_G + sandStorm*0.85 + sandStorm_red*0.3;
		BiomeColors.b = smoothSwamps*SWAMP_B + smoothJungles*JUNGLE_B + smoothDarkForests*DARKFOREST_B + smoothBiome_Snowy*SNOWY_B + snowStorm*1.0 + smoothBiome_Dry*DRY_B + sandStorm*0.4 + sandStorm_red*0.2;

		DirectLightCol = BiomeColors * max(dot(DirectLightCol,vec3(0.33333)), MIN_LIGHT_AMOUNT*0.025);
		IndirectLightCol = BiomeColors * max(dot(IndirectLightCol,vec3(0.33333)), MIN_LIGHT_AMOUNT*0.025);

		return Inbiome;
	}
#endif