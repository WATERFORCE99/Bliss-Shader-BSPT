//Original atmosphere code : https://www.shadertoy.com/view/WcdSW4, heavily customized.

uniform int moonPhase;

const float sunAngularSize = 0.533333;
const float moonAngularSize = 0.516667;

const float INFINITY = 1.0 / 0.0;

const float EARTH_RADIUS = 6731e3;
const float ATMOSPHERE_HEIGHT = 110e3;
const float ATMOSPHERE_RADIUS = EARTH_RADIUS + ATMOSPHERE_HEIGHT;

const float RAYLEIGH_SCALE_HEIGHT = 32.4e4; 
const vec3 RAYLEIGH_SCATTERING_COEFFICIENTS = vec3(6.184e-6, 12.30e-6, 28.04e-6);
const vec3 RAYLEIGH_EXTINCTION_COEFFICIENTS = RAYLEIGH_SCATTERING_COEFFICIENTS * skyRL;

const float MIE_SCALE_HEIGHT = 14.0e4;
const vec3 MIE_SCATTERING_COEFFICIENTS = vec3(1.252e-5, 1.689e-5, 2.530e-5);
const vec3 MIE_EXTINCTION_COEFFICIENTS = MIE_SCATTERING_COEFFICIENTS * skyMie * 1.1;

const float OZONE_SCALE_HEIGHT = 45.5e4;
const vec3 OZONE_EXTINCTION_COEFFICIENTS = vec3(1.224e-6, 2.883e-6, 5.441e-8);

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

	return (x < 0.0) ? 2.0 * exp(t2) - y : y;
}

float air_mass(float r, float z, float t, float H) {
	float a = 0.5 * sqrt(PI) * H * exp(-(r * r - EARTH_RADIUS * EARTH_RADIUS) / (H * H));
	float b = r * z / H;

	if (isinf(t))
	return a * erfcx(b);

	float c = t / H + b;
	float d = exp(b * b - c * c);

	return (z >= 0.0 || t + r * z >= 0.0) 
		? a * (erfcx(b) - d * erfcx(c))
		: a * (d * erfcx(-c) - erfcx(-b));
}

float rayleighPhase(float mu) {
	return 3.0 * rPI / 16.0 * (1.0 + mu * mu);
}

float miePhase(float mu) {
	float g = 0.77;
	float g2 = g * g;
	return rPI / 4.0 * (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * mu, 1.5);
}

float calculateDistance(vec3 origin, vec3 direction, float radius) {
	float r = length(origin);
	float z = dot(normalize(origin), direction);
	float d = radius * radius - r * r * (1.0 - z * z);

	if (d < 0.0) return INFINITY;

	float t1 = sqrt(d) - r * z;
	float t2 = -sqrt(d) - r * z;

	return (t1 > 0.0) ? ((t2 > 0.0) ? min(t1, t2) : t1) : ((t2 > 0.0) ? t2 : INFINITY);
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

	vec3 trans_light = skyTransmittance(origin + direction * t * 0.15, light_dir, INFINITY);

	float phase_r = rayleighPhase(mu);
	float phase_m = miePhase(mu);

	vec3 scattering = (scattering_r * phase_r + scattering_m * phase_m) * trans_light * light_color;

	return scattering;
}

vec3 colorCorrection(vec3 color) {
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 gray = vec3(luminance);

	float saturation = mix(0.8, 1.15, smoothstep(0.1, 0.5, luminance));

	color = mix(gray, color, saturation);   
	return color;
}

vec3 calculateAtmosphere(vec3 background, vec3 viewVector, vec3 upVector, vec3 sunVector, vec3 moonVector, out vec2 pid, out vec3 transmittance, float noise) {
	vec3 origin = (EARTH_RADIUS + eyeAltitude) * upVector;

	float t = 100000.0;
	transmittance = skyTransmittance(origin, viewVector, t);

	float t_ground = calculateDistance(origin, viewVector, EARTH_RADIUS);
	pid = vec2(-1.0, t_ground);

	#ifdef SKY_GROUND
		float planetGround = exp(-40.0 * pow(max(-viewVector.y * 2.5 + 0.05, 0.0), 1.8));
	#else
		float planetGround = pow(max(viewVector.y + 1.0, 0.0), 1.5);
	#endif

	vec3 sunScattering = calculateScattering(origin, viewVector, sunVector, t, sunColorBase);
	vec3 moonScattering = calculateScattering(origin, viewVector, moonVector, t, moonColorBase);

	vec3 ambientSky = mix(vec3(0.45, 0.2, 0.37), vec3(0.6, 0.75, 0.85), smoothstep(0.1, 0.3, sunVector.y)) * background;

	vec3 color = ambientSky + (sunScattering + moonScattering * 0.5) * planetGround;
	return colorCorrection(color);
}