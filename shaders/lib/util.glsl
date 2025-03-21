uniform sampler2D noisetex;
uniform int frameCounter;

const float PI 		= acos(-1.0);
const float TAU 	= PI * 2.0;
const float hPI 	= PI * 0.5;
const float rPI 	= 1.0 / PI;
const float rTAU 	= 1.0 / TAU;

const float PHI	= sqrt(5.0) * 0.5 + 0.5;
const float rLOG2	= 1.0 / log(2.0);

const float goldenAngle = TAU / PHI / PHI;

#define clamp01(x) clamp(x, 0.0, 1.0)
#define max0(x) max(x, 0.0)
#define min0(x) min(x, 0.0)
#define max3(a) max(max(a.x, a.y), a.z)
#define min3(a) min(min(a.x, a.y), a.z)
#define max4(a, b, c, d) max(max(a, b), max(c, d))
#define min4(a, b, c, d) min(min(a, b), min(c, d))

#define fsign(x) (clamp01(x * 1e35) * 2.0 - 1.0)
#define fstep(x,y) clamp01((y - x) * 1e35)

#define diagonal2(m) vec2((m)[0].x, (m)[1].y)
#define diagonal3(m) vec3(diagonal2(m), m[2].z)
#define diagonal4(m) vec4(diagonal3(m), m[2].w)

#define transMAD(mat, v) (mat3(mat) * (v) + (mat)[3].xyz)
#define projMAD(mat, v) (diagonal3(mat) * (v) + (mat)[3].xyz)

#define encodeColor(x) (x * 0.00005)
#define decodeColor(x) (x * 20000.0)

#define cubeSmooth(x) (x * x * (3.0 - 2.0 * x))

#define lumCoeff vec3(0.2125, 0.7154, 0.0721)

float facos(const float sx){
	float x = clamp(abs( sx ),0.,1.);
	float a = sqrt( 1. - x ) * ( -0.16882 * x + 1.56734 );
	return mix(PI - a, a, step(0.0, sx));
	//float c = clamp(-sx * 1e35, 0., 1.);
	//return c * pi + a * -(c * 2. - 1.); //no conditional version
}

vec2 sincos(float x){
	return vec2(sin(x), cos(x));
}

vec2 circlemap(float i, float n){
	return sincos(i * n * goldenAngle) * sqrt(i);
}

vec3 circlemapL(float i, float n){
	return vec3(sincos(i * n * goldenAngle), sqrt(i));
}

vec3 calculateRoughSpecular(const float i, const float alpha2, const int steps){

	float x = (alpha2 * i) / (1.0 - i);
	float y = i * float(steps) * 64.0 * 64.0 * goldenAngle;

	float c = inversesqrt(x + 1.0);
	float s = sqrt(x) * c;

	return vec3(cos(y) * s, sin(y) * s, c);
}

vec3 clampNormal(vec3 n, vec3 v){
	float NoV = clamp( dot(n, -v), 0., 1. );
	return normalize( NoV * v + n );
}

vec3 srgbToLinear(vec3 srgb){
	return mix(
		srgb / 12.92,
		pow(.947867 * srgb + .0521327, vec3(2.4) ),
		step( .04045, srgb )
	);
}

vec3 linearToSRGB(vec3 linear){
	return mix(
		linear * 12.92,
		pow(linear, vec3(1./2.4) ) * 1.055 - .055,
		step( .0031308, linear )
	);
}

vec3 blackbody(float Temp){
	float t = pow(Temp, -1.5);
	float lt = log(Temp);

	vec3 col = vec3(0.0);
	col.x = 220000.0 * t + 0.58039215686;
	col.y = mix(0.39231372549 * lt - 2.44549019608, 138039.215686 * t + 0.72156862745, step(6500.0, Temp));
	col.z = 0.76078431372 * lt - 5.68078431373;
	col = clamp01(col);
	col = Temp < 1000. ? col * Temp * 0.001 : col;

	return srgbToLinear(col);
}

float calculateHardShadows(float shadowDepth, vec3 shadowPosition, float bias){
	if(shadowPosition.z >= 1.0) return 1.0;

	return 1.0 - fstep(shadowDepth, shadowPosition.z - bias);
}

vec3 genUnitVector(vec2 xy){
	xy.x *= TAU; xy.y = xy.y * 2.0 - 1.0;
	return vec3(sincos(xy.x) * sqrt(1.0 - xy.y * xy.y), xy.y);
}

vec2 rotate(vec2 x, float r){
	vec2 sc = sincos(r);
	return mat2(sc.x, -sc.y, sc.y, sc.x) * x;
}

vec3 cartToSphere(vec2 coord){
	coord *= vec2(TAU, PI);
	vec2 lon = sincos(coord.x) * sin(coord.y);
	return vec3(lon.x, 2.0/PI*coord.y-1.0, lon.y);
}

vec2 sphereToCart(vec3 dir){
	float lonlat = atan(-dir.x, -dir.z);
	return vec2(lonlat * rTAU +0.5,0.5*dir.y+0.5);
}

mat3 getRotMat(vec3 x,vec3 y){
	float d = dot(x,y);
	vec3 cr = cross(y,x);

	float s = length(cr);

	float id = 1.-d;

	vec3 m = cr/s;

	vec3 m2 = m*m*id+d;
	vec3 sm = s*m;

	vec3 w = (m.xy*id).xxy*m.yzz;

	return mat3(
		m2.x, w.x-sm.z, w.y+sm.y,
		w.x+sm.z, m2.y, w.z-sm.x,
		w.y-sm.y, w.z+sm.x, m2.z
	);
}

// No intersection if returned y component is < 0.0
vec2 rsi(vec3 position, vec3 direction, float radius){
	float PoD = dot(position, direction);
	float radiusSquared = radius * radius;

	float delta = PoD * PoD + radiusSquared - dot(position, position);
	if (delta < 0.0) return vec2(-1.0);
		delta = sqrt(delta);

	return -PoD + vec2(-delta, delta);
}

float HaltonSeq3(int index){
	float r = 0.;
	float f = 1.;
	for (int i = index; i > 0; i /= 3){
		f /= 3.0;
		r += f * float(i % 3);
	}
	return r;
}

float HaltonSeq2(int index){
	float r = 0.;
	float f = 1.;
	for (int i = index; i > 0; i /= 2){
		f *= 0.5;
		r += f * float(i % 2);
	}
	return r;
}

float Hammersley(int i) {
	uint bits = uint(i);
	bits = (bits << 16u) | (bits >> 16u);
	bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
	bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
	bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
	bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
	return float(bits) * 2.3283064365386963e-10; // 1/2^32
}

vec2 R2_samples(int n){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha * n);
}

float luma(vec3 color) {
	return dot(color,vec3(0.21, 0.72, 0.07));
}

vec2 simpleRand22(vec2 p){
    mat2 m = mat2(12.9898,.16180,78.233,.31415);
	return fract(sin(m * p) * vec2(43758.5453, 14142.1));
}

float hash11(float p) {
	p = fract(p * .1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash12(vec2 p){
	vec3 p3  = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3){
	p3  = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx+19.19);
	return fract((p3.xx+p3.yz)*p3.zy);
}

vec3 hash31(float p){
	vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx+33.33);
	return fract((p3.xxy+p3.yzz)*p3.zyx); 
}

vec3 decode (vec2 encn){
	vec3 n = vec3(0.0);
	encn = encn * 2.0 - 1.0;
	n.xy = abs(encn);
	n.z = 1.0 - n.x - n.y;
	n.xy = n.z <= 0.0 ? (1.0 - n.yx) * sign(encn) : encn;
	return clamp(normalize(n.xyz),-1.0,1.0);
}

vec2 decodeVec2(float a){
	const vec2 constant1 = 65535. / vec2( 256., 65536.);
	const float constant2 = 256. / 255.;
	return fract( a * constant1 ) * constant2 ;
}