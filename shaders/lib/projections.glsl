uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

vec3 toClipSpace3(vec3 viewSpacePosition) {
	return projMAD(gbufferProjection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
}

vec3 toClipSpace3Prev(vec3 viewSpacePosition) {
	return projMAD(gbufferPreviousProjection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
}

vec4 toClipSpace4(vec3 viewSpacePosition) {
	return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition),1.0);
}

vec4 toClipSpace4alt(vec3 viewSpacePosition) {
	return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition),-viewSpacePosition.z);
}

vec3 toNDC3(vec3 worldPos) {
	vec4 pos = vec4(worldPos, 1.0);
	pos = gbufferProjection * gbufferModelView * pos;
	return pos.xyz/pos.w;
}

vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
	vec3 p3 = p * 2. - 1.;
	vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
	return fragposition.xyz / fragposition.w;
}

vec3 toScreenSpaceVector(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
	vec3 p3 = p * 2. - 1.;
	vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
	return normalize(fragposition.xyz);
}

vec3 toWorldSpace(vec3 p3) {
	p3 = mat3(gbufferModelViewInverse) * p3 + gbufferModelViewInverse[3].xyz;
	return p3;
}

vec3 toWorldSpaceCamera(vec3 p3) {
	p3 = mat3(gbufferModelViewInverse) * p3 + gbufferModelViewInverse[3].xyz;
	return p3 + cameraPosition;
}

vec3 toShadowSpace(vec3 p3) {
	p3 = mat3(shadowModelViewInverse) * p3 + shadowModelViewInverse[3].xyz;
	return p3;
}

vec3 toShadowSpaceProjected(vec3 p3) {
	p3 = mat3(shadowModelView) * p3 + shadowModelView[3].xyz;
	p3 = diagonal3(shadowProjection) * p3 + shadowProjection[3].xyz;
	return p3;
}

vec3 viewToWorld(vec3 viewPos) {
	vec4 pos;
	pos.xyz = viewPos;
	pos.w = 0.0;
	pos = gbufferModelViewInverse * pos;
	return pos.xyz;
}

vec3 worldToView(vec3 worldPos) {
	vec4 pos = vec4(worldPos, 0.0);
	pos = gbufferModelView * pos;
	return pos.xyz;
}

vec3 toPreviousPos(vec3 currentPos) {
	vec3 pos = mat3(gbufferModelViewInverse) * currentPos + gbufferModelViewInverse[3].xyz + cameraPosition-previousCameraPosition;
	return mat3(gbufferPreviousModelView) * pos + gbufferPreviousModelView[3].xyz;
}