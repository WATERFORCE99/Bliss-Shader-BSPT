
// Common constants

const float e = exp(1.0);
const float hand_depth = 0.56;

#if defined TAA && defined TAA_UPSCALING
	const float taau_render_scale = RENDER_SCALE.x;
#else
	const float taau_render_scale = 1.0;
#endif

// Helper functions

float max_of(vec2 v) { return max(v.x, v.y); }

float length_squared(vec2 v) { return dot(v, v); }
float length_squared(vec3 v) { return dot(v, v); }

float rcp_length(vec2 v) { return inversesqrt(dot(v, v)); }
float rcp_length(vec3 v) { return inversesqrt(dot(v, v)); }

float fast_acos(float x) {
	const float C0 = 1.57018;
	const float C1 = -0.201877;
	const float C2 = 0.0464619;

	float res = (C2 * abs(x) + C1) * abs(x) + C0; // p(x)
	res *= sqrt(1.0 - abs(x));

	return x >= 0 ? res : PI - res; // Undo range reduction
}

vec2 fast_acos(vec2 v) { return vec2(fast_acos(v.x), fast_acos(v.y)); }

float linear_step(float edge0, float edge1, float x) {
	return clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
}

vec2 linear_step(vec2 edge0, vec2 edge1, vec2 x) {
	return clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
}

vec4 project(mat4 m, vec3 pos) {
	return vec4(m[0].x, m[1].y, m[2].zw) * pos.xyzz + m[3];
}

vec3 project_and_divide(mat4 m, vec3 pos) {
	vec4 homogenous = project(m, pos);
	return homogenous.xyz / homogenous.w;
}

vec3 screen_to_view_space(vec3 screen_pos, bool handle_jitter) {
	vec3 ndc_pos = 2.0 * screen_pos - 1.0;
	return project_and_divide(gbufferProjectionInverse, ndc_pos);
}

vec3 view_to_screen_space(vec3 view_pos, bool handle_jitter) {
	vec3 ndc_pos = project_and_divide(gbufferProjection, view_pos);
	return ndc_pos * 0.5 + 0.5;
}

// ---------------------
//   ambient occlusion
// ---------------------

#define GTAO_SLICES        2
#define GTAO_HORIZON_STEPS 3
#define GTAO_RADIUS        2.0
#define GTAO_FALLOFF_START 0.75

float integrate_arc(vec2 h, float n, float cos_n) {
	vec2 tmp = cos_n + 2.0 * h * sin(n) - cos(2.0 * h - n);
	return 0.25 * (tmp.x + tmp.y);
}

float calculate_maximum_horizon_angle(
	vec3 view_slice_dir,
	vec3 viewer_dir,
	vec3 screen_pos,
	vec3 view_pos,
	float radius,
	float dither
) {
	const float step_size = GTAO_RADIUS / float(GTAO_HORIZON_STEPS);

	float max_cos_theta = -1.0;

	vec2 ray_step = (view_to_screen_space(view_pos + view_slice_dir * step_size, true) - screen_pos).xy;
	vec2 ray_pos = screen_pos.xy + ray_step * (dither + max_of(texelSize) * rcp_length(ray_step));


	for (int i = 0; i < GTAO_HORIZON_STEPS; ++i, ray_pos += ray_step) {
		float depth = texelFetch2D(depthtex1, ivec2(clamp(ray_pos,0.0,1.0) * viewSize * taau_render_scale - 0.5), 0).x;

		if (depth == 1.0 || depth < hand_depth || depth == screen_pos.z) continue;

		vec3 offset = screen_to_view_space(vec3(ray_pos, depth), true) - view_pos;

		float len_sq = length_squared(offset);
		float norm = inversesqrt(len_sq);

		float distance_falloff = linear_step(GTAO_FALLOFF_START * GTAO_RADIUS, GTAO_RADIUS, len_sq * norm);

		float cos_theta = dot(viewer_dir, offset) * norm;
			cos_theta = mix(cos_theta, -1.0, distance_falloff);

		max_cos_theta = max(cos_theta, max_cos_theta);
	}

	return fast_acos(clamp(max_cos_theta, -1.0, 1.0));
}

float ambient_occlusion(vec3 screen_pos, vec3 view_pos, vec3 view_normal, vec2 dither) {
	float ao = 0.0;

	// Construct local working space
	vec3 viewer_dir = normalize(-view_pos);
	vec3 viewer_right = normalize(cross(vec3(0.0, 1.0, 0.0), viewer_dir));
	vec3 viewer_up = cross(viewer_dir, viewer_right);
	mat3 local_to_view = mat3(viewer_right, viewer_up, viewer_dir);

	// Reduce AO radius very close up, makes some screen-space artifacts less obvious
	float ao_radius = max(0.25 + 0.75 * smoothstep(0.0, 81.0, length_squared(view_pos)), 0.5);

	for (int i = 0; i < GTAO_SLICES; ++i) {
		float slice_angle = (i + dither.x) * (PI / float(GTAO_SLICES));

		vec3 slice_dir = vec3(cos(slice_angle), sin(slice_angle), 0.0);
		vec3 view_slice_dir = local_to_view * slice_dir;

		vec3 ortho_dir = slice_dir - dot(slice_dir, viewer_dir) * viewer_dir;
		vec3 axis = cross(slice_dir, viewer_dir);

		vec3 projected_normal = view_normal - axis * dot(view_normal, axis);

		float len_sq = dot(projected_normal, projected_normal);
		float norm = inversesqrt(len_sq);

		float sgn_gamma = sign(dot(ortho_dir, projected_normal));
		float cos_gamma = clamp(dot(projected_normal, viewer_dir) * norm, 0.0, 1.0);
		float gamma = sgn_gamma * fast_acos(cos_gamma);

		vec2 max_horizon_angles;
		max_horizon_angles.x = calculate_maximum_horizon_angle(-view_slice_dir, viewer_dir, screen_pos, view_pos, ao_radius, dither.y);
		max_horizon_angles.y = calculate_maximum_horizon_angle( view_slice_dir, viewer_dir, screen_pos, view_pos, ao_radius, dither.y);

		max_horizon_angles = gamma + clamp(vec2(-1.0, 1.0) * max_horizon_angles - gamma, -hPI, hPI) ;


		ao += integrate_arc(max_horizon_angles, gamma, cos_gamma) * len_sq * norm  ;
	}
	const float albedo = 0.2;
	ao /= float(GTAO_SLICES);
	ao /= albedo * ao + (1.0 - albedo);

	return ao;
}
