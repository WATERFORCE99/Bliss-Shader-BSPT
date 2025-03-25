uniform sampler2D noisetex;
uniform int frameCounter;

float interleaved_gradientNoise_temporal(){
	vec2 coord = gl_FragCoord.xy;
	
	#ifdef TAA
		coord += (frameCounter*9)%40000;
	#endif

	return fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
}

float R2_dither(){
	vec2 coord = gl_FragCoord.xy ;

	#ifdef TAA
		coord += (frameCounter*2)%40000;
	#endif
	
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * coord.x + alpha.y * coord.y);
}

float blueNoise(){
	#ifdef TAA
  		return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887);
	#endif
}

vec2 randNoise(vec2 p){
	vec2 co = floor(p);
	vec2 mu = fract(p);
	mu = 3.*mu*mu-2.*mu*mu*mu;
	vec2 a = simpleRand22((co+vec2(0.,0.)));
	vec2 b = simpleRand22((co+vec2(1.,0.)));
	vec2 c = simpleRand22((co+vec2(0.,1.)));
	vec2 d = simpleRand22((co+vec2(1.,1.)));
	return mix(mix(a, b, mu.x), mix(c, d, mu.x), mu.y);
}