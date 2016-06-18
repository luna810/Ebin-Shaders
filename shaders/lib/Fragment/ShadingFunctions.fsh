// Start of #include "/lib/Fragment/ShadingFunctions.fsh"

struct Shading {      // Contains scalar light levels without any color
	float normal;     // Coefficient of light intensity based on the dot product of the normal vector and the light vector
	float sunlight;
	float skylight;
	float torchlight;
	float ambient;
};

struct Lightmap {    // Contains vector light levels with color
	vec3 sunlight;
	vec3 skylight;
	vec3 ambient;
	vec3 torchlight;
};

vec4 ViewSpaceToWorldSpace(in vec4 viewSpacePosition) {
	return gbufferModelViewInverse * viewSpacePosition;
}

vec4 WorldSpaceToShadowSpace(in vec4 worldSpacePosition) {
	return shadowProjection * shadowModelView * worldSpacePosition;
}

#include "/lib/Misc/BiasFunctions.glsl"

vec2 GetDitherred2DNoise(in vec2 coord, in float n) { // Returns a random noise pattern ranging {-1.0 to 1.0} that repeats every n pixels
	coord *= vec2(viewWidth, viewHeight);
	coord  = mod(coord, vec2(n));
	coord /= noiseTextureResolution;
	return texture2D(noisetex, coord).xy;
}

float GetLambertianShading(in vec3 normal, in Mask mask) {
	float shading = max0(dot(normal, lightVector));
	      shading = shading * (1.0 - mask.grass       ) + mask.grass       ;
	      shading = shading * (1.0 - mask.leaves * 0.5) + mask.leaves * 0.5;
	
	return shading;
}

float GetOrenNayarShading(in vec4 viewSpacePosition, in vec3 normal, in float roughness, in Mask mask) {
#ifdef PBR
	vec3 eyeDir = normalize(viewSpacePosition.xyz);
	
	float NdotL = dot(normal, lightVector);
	float NdotV = dot(normal, eyeDir);
	
	float angleVN = acos(NdotV);
	float angleLN = acos(NdotL);
	
	float alpha = max(angleVN, angleLN);
	float beta  = min(angleVN, angleLN);
	float gamma = dot(eyeDir - normal * NdotV, lightVector - normal * NdotL);
	
	float roughnessSquared = pow2(roughness);
	
	float A = 1.0 -  0.5 * (roughnessSquared / (roughnessSquared + 0.57));
	float B =       0.45 * (roughnessSquared / (roughnessSquared + 0.09));
	float C = sin(alpha) * tan(beta);
	
	float shading = max0(NdotL) * (A + B * max0(gamma) * C);
	
	shading = shading * (1.0 - mask.grass       ) + mask.grass       ;
	shading = shading * (1.0 - mask.leaves * 0.5) + mask.leaves * 0.5;
	
	return shading;
#else
	return GetLambertianShading(normal, mask);
#endif
}

float HardShadows(in vec3 position) {
	return pow2(shadow2D(shadow, position.xyz).x);
}

float UniformlySoftShadows(in vec3 position, in float biasCoeff) {
	float spread = 1.0 * (1.0 - biasCoeff) / shadowMapResolution;
	
	cfloat range       = 1.0;
	cfloat interval    = 1.0;
	cfloat sampleCount = pow(range / interval * 2.0 + 1.0, 2.0); // Calculating the sample count outside of the for-loop is generally faster.
	
	float sunlight = 0.0;
	
	for (float y = -range; y <= range; y += interval)
		for (float x = -range; x <= range; x += interval)
			sunlight += shadow2D(shadow, vec3(position.xy + vec2(x, y) * spread, position.z)).x;
	
	sunlight /= sampleCount; // Average the samples by dividing the sum by the sample count.
	
	return pow2(sunlight);
}

float VariablySoftShadows(in vec3 position, in float biasCoeff) {
	float vpsSpread = 0.4 / biasCoeff;
	
	vec2 randomAngle = GetDitherred2DNoise(texcoord, 64.0).xy * PI * 2.0;
	
	mat2 blockerRotation = mat2(
		cos(randomAngle.x), -sin(randomAngle.x),
	    sin(randomAngle.y),  cos(randomAngle.y)); //Random Rotation Matrix for blocker, high noise
	
	mat2 pcfRotation = mat2(
		cos(randomAngle.x), -sin(randomAngle.x),
		sin(randomAngle.x),  cos(randomAngle.x)); //Random Rotation Matrix for blocker, high noise
	
	float range       = 1.0;
	float sampleCount = pow(range * 2.0 + 1.0, 2.0);
	
	float avgDepth = 0.0;
	//Blocker Search
	for(float y = -range; y <= range; y++) {
		for(float x = -range; x <= range; x++) {
			vec2 lookupPosition = position.xy + vec2(x, y) * 8.0 / shadowMapResolution * blockerRotation * vpsSpread;
			float depthSample = texture2DLod(shadowtex1, lookupPosition, 0).x;
			
			avgDepth += pow(clamp(position.z - depthSample, 0.0, 1.0), 1.7);
		}
	}
	
	avgDepth /= sampleCount;
	avgDepth  = sqrt(avgDepth);
	
	float spread = avgDepth * 0.02 * vpsSpread + 0.45 / shadowMapResolution;
	
	range       = 2.0;
	sampleCount = pow(range * 2.0 + 1.0, 2.0);
	
	float sunlight = 0.0;
	
	//PCF Blur
	for (float y = -range; y <= range; y++) {
		for (float x = -range; x <= range; x++) {
			vec2 coord = vec2(x, y) * pcfRotation;
			
			sunlight += shadow2D(shadow, vec3(coord * spread + position.st, position.z)).x;
		}
	}
	
	return sunlight / sampleCount;
}

float ComputeDirectSunlight(in vec4 position, in float normalShading, cuint Shadow_Type) {
	if (normalShading <= 0.01) return 0.0;
	
	float biasCoeff;
	
	position     = ViewSpaceToWorldSpace(position);
	position     = WorldSpaceToShadowSpace(position);
	position.xyz = BiasShadowProjection(position.xyz, biasCoeff);
	position.xyz = position.xyz * 0.5 + 0.5;
	
	if (any(greaterThan(abs(position.xyz - 0.5), vec3(0.5)))) return 1.0;
	
	switch(Shadow_Type == 0 ? SHADOW_TYPE : Shadow_Type) {
		case 2: return UniformlySoftShadows(position.xyz, biasCoeff);
		case 3: return VariablySoftShadows(position.xyz, biasCoeff);
		
		default: return HardShadows(position.xyz);
	}
}

vec3 CalculateShadedFragment(in Mask mask, in float torchLightmap, in float skyLightmap, in vec3 normal, in float smoothness, in vec4 ViewSpacePosition) {
	Shading shading;
	shading.normal = GetOrenNayarShading(ViewSpacePosition, normal, 1.0 - smoothness, mask);
	
	shading.sunlight  = shading.normal;
	shading.sunlight *= ComputeDirectSunlight(ViewSpacePosition, shading.normal, 0);
	shading.sunlight *= pow2(skyLightmap);
	
	shading.torchlight = 1.0 - pow(clamp01(torchLightmap - 0.075), 4.0);
	shading.torchlight = 1.0 / pow(shading.torchlight, 2.0) - 1.0;
	
	shading.skylight = pow(skyLightmap, 4.0);
	
	shading.ambient = 1.0;
	
	
	Lightmap lightmap;
	lightmap.sunlight = shading.sunlight * sunlightColor;
	
	lightmap.skylight = shading.skylight * sqrt(skylightColor);
	
	lightmap.ambient = shading.ambient * vec3(1.0);
	
	lightmap.torchlight = shading.torchlight * vec3(1.00, 0.25, 0.05);
	
	
	return vec3(
	    lightmap.sunlight   * 6.0   * SUN_LIGHT_LEVEL
	+   lightmap.skylight   * 0.35  * SKY_LIGHT_LEVEL
	+   lightmap.ambient    * 0.015 * AMBIENT_LIGHT_LEVEL
	+   lightmap.torchlight * 4.0   * TORCH_LIGHT_LEVEL
	    );
}

// End of #include "/lib/Fragment/ShadingFunctions.fsh"