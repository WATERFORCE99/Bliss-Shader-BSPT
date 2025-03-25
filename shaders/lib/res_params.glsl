#ifndef TAA
	#undef TAA_UPSCALING
#endif

#ifdef TAA_UPSCALING
	#define SCALE_FACTOR 0.75  // render resolution multiplier. below 0.5 not recommended [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0]

	#define RENDER_SCALE vec2(SCALE_FACTOR, SCALE_FACTOR)
	#define UPSCALING_SHARPNENING 2.0 - SCALE_FACTOR - SCALE_FACTOR
#else
	#define RENDER_SCALE vec2(1.0, 1.0)
	#define UPSCALING_SHARPNENING 0.0
#endif

#define VL_RENDER_RESOLUTION 0.5 // Reduces the resolution at which volumetric fog is computed. (0.5 = half of default resolution) [0.25 0.5 1.0]