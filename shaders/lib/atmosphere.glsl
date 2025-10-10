//Original atmosphere code : https://www.shadertoy.com/view/WcdSW4, highly customized.

uniform int moonPhase;

const float sunAngularSize = 0.533333;
const float moonAngularSize = 0.516667;

const float INFINITY = 1.0 / 0.0;

const float EARTH_RADIUS = 6731e3;
const float ATMOSPHERE_HEIGHT = 110e3;
const float ATMOSPHERE_RADIUS = EARTH_RADIUS + ATMOSPHERE_HEIGHT;

const float RAYLEIGH_SCALE_HEIGHT = 32e4; 
const vec3 RAYLEIGH_SCATTERING_COEFFICIENTS = vec3(6.384e-6, 12.00e-6, 28.74e-6);
const vec3 RAYLEIGH_EXTINCTION_COEFFICIENTS = RAYLEIGH_SCATTERING_COEFFICIENTS * skyRL;

const float MIE_SCALE_HEIGHT = 14e4;
const vec3 MIE_SCATTERING_COEFFICIENTS = vec3(1.252e-6, 1.689e-6, 2.530e-6);
const vec3 MIE_EXTINCTION_COEFFICIENTS = MIE_SCATTERING_COEFFICIENTS * skyMie * 1.1;

const float OZONE_SCALE_HEIGHT = 45.5e4;
const vec3 OZONE_EXTINCTION_COEFFICIENTS = vec3(1.824e-6, 1.883e-6, 0.0);

#ifdef MOONPHASE_BASED_MOONLIGHT
	float moonlightbrightness = abs(4-moonPhase)/4.0;
#else
	float moonlightbrightness = 1.0;
#endif

#if colortype == 1
	#define sunColorBase vec3(sunColorR, sunColorG, sunColorB) * sun_illuminance
	#define moonColorBase vec3(moonColorR, moonColorG, moonColorB) * moon_illuminance * moonlightbrightness
#else
	#define sunColorBase blackbody(Sun_temp) * sun_illuminance
	#define moonColorBase blackbody(Moon_temp) * moon_illuminance * moonlightbrightness
#endif

float erfcx(float x) {
	float t = abs(x);
	float t2 = t * t;
	float A = 0.56418958354775629 / (t + 2.06955023132914151);
	float B = (t2 + 2.71078540045147805 * t + 5.80755613130301624) / (t2 + 3.47954057099518960 * t + 12.06166887286239555);
	float C = (t2 + 3.47469513777439592 * t + 12.07402036406381411) / (t2 + 3.72068443960225092 * t + 8.44319781003968454);
	float D = (t2 + 4.00561509202259545 * t + 9.30596659485887898) / (t2 + 3.90225704029924078 * t + 6.36161630953880464);
	float E = (t2 + 5.16722705817812584 * t + 9.1266167673673262) / (t2 + 4.03296893109262491 * t + 5.13578530585681539);
	float F = (t2 + 5.95908795446633271 * t + 9.19435612886969243) / (t2 + 4.11240942957450885 * t + 4.48640329523408675);
	float y = A * B * C * D * E * F;

	if (x < 0.0)
		return 2.0 * exp(t2) - y;
	else
		return y;
}

float air_mass(float r, float z, float t, float H) {
	float a = 0.5 * sqrt(PI) * H * exp(-(r * r - EARTH_RADIUS * EARTH_RADIUS) / (H * H));
	float b = r * z / H;

	if (isinf(t))
	return a * erfcx(b);

	float c = t / H + b;
	float d = exp(b * b - c * c);

	if (z >= 0.0 || t + r * z >= 0.0)
		return a * (erfcx(b) - d * erfcx(c));
	else
		return a * (d * erfcx(-c) - erfcx(-b));
}

float rayleighPhase(float mu) {
	const float rayleighFactor = 3.0 * rPI / 16.0;
	return rayleighFactor * (1.0 + mu * mu);
}

float henyeyGreensteinPhase(float mu, float g) {
	return rPI / 4.0 * (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * mu, 1.5);
}

float drainePhase(float mu, float g, float a) {
	return ((1.0 - g * g) * (1.0 + a * mu * mu)) / (4.0 * (1.0 + (a * (1.0 + 2.0 * g * g)) / 3.0) * PI * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
}

float miePhase(float mu) {
	const float g1 = 0.862;
	const float g2 = 0.5069161813017329;
	const float a = 250.0;
	const float w = 0.24075857115188248;
	float HG = henyeyGreensteinPhase(mu, g1);
	float draine = drainePhase(mu, g2, a);
	return mix(HG, draine, w);
}

float calculateDistance(vec3 origin, vec3 direction, float radius) {
	float r = length(origin);
	float z = dot(normalize(origin), direction);
	float d = radius * radius - r * r * (1.0 - z * z);
	if (d < 0.0) return INFINITY;

	float t1 = sqrt(d) - r * z;
	float t2 = -sqrt(d) - r * z;
	t1 = t1 < 0.0 ? INFINITY : t1;
	t2 = t2 < 0.0 ? INFINITY : t2;
	return min(t1, t2);
}

vec3 skyTransmittance(vec3 origin, vec3 direction, float t) {
	float r = length(origin);
	float z = dot(normalize(origin), direction);

	vec3 tau_r = RAYLEIGH_EXTINCTION_COEFFICIENTS * air_mass(r, z, t, RAYLEIGH_SCALE_HEIGHT);
	vec3 tau_m = MIE_EXTINCTION_COEFFICIENTS * air_mass(r, z, t, MIE_SCALE_HEIGHT);
	vec3 tau_o = OZONE_EXTINCTION_COEFFICIENTS * air_mass(r, z, t, OZONE_SCALE_HEIGHT);

	return exp(-(tau_r + tau_m + tau_o));
}

vec3 calculateScattering(vec3 origin, vec3 direction, vec3 light_dir, float t, vec3 light_color) {
	float r = length(origin);
	float z = dot(normalize(origin), direction);
	float z_light = dot(normalize(origin), light_dir);
	float mu = dot(light_dir, direction);

	vec3 scattering_r = RAYLEIGH_SCATTERING_COEFFICIENTS * air_mass(r, z, t, RAYLEIGH_SCALE_HEIGHT);
	vec3 scattering_m = MIE_SCATTERING_COEFFICIENTS * air_mass(r, z, t, MIE_SCALE_HEIGHT);

	vec3 trans_light = skyTransmittance(origin, light_dir, INFINITY);

	float phase_r = rayleighPhase(mu);
	float phase_m = miePhase(mu);

	vec3 scattering = (scattering_r * phase_r + scattering_m * phase_m) * trans_light * light_color;

	return scattering;
}

vec3 calculateAtmosphere(vec3 background, vec3 viewVector, vec3 upVector, vec3 sunVector, vec3 moonVector, out vec2 pid, out vec3 transmittance, const int iSteps, float noise) {
	vec3 origin = (EARTH_RADIUS + eyeAltitude) * upVector;

	float t_atmosphere = calculateDistance(origin, viewVector, ATMOSPHERE_RADIUS);
	float t_ground = calculateDistance(origin, viewVector, EARTH_RADIUS);

	float t = min(t_atmosphere, t_ground);
    
	if (t >= INFINITY) {
		transmittance = vec3(1.0);
		pid = vec2(-1.0, -1.0);
		return background;
	}

	transmittance = skyTransmittance(origin, viewVector, t);

	#ifdef SKY_GROUND
		float planetGround = exp(-40 * pow(max(-viewVector.y * 2.5 + 0.05, 0.0), 1.8));
	#else
		float planetGround = pow(clamp(viewVector.y + 1.0, 0.0, 1.0), 1.5);
	#endif

	vec3 sunScattering = calculateScattering(origin, viewVector, sunVector, t, sunColorBase);

	vec3 moonScattering = calculateScattering(origin, viewVector, moonVector, t, moonColorBase);

	vec3 ambientSky = mix(vec3(0.15, 0.06, 0.05), vec3(0.4, 0.55, 0.8), sunVector.y) * background;

	pid = vec2(-1.0, t_ground);

	vec3 color = ambientSky + sunScattering * planetGround + moonScattering * planetGround * 0.5;
	return color;
}