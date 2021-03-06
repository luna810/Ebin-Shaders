#version 410 compatibility
#define composite1
#define fsh
#define ShaderStage 1
#include "/lib/Syntax.glsl"

/* DRAWBUFFERS:146 */

const bool colortex5MipmapEnabled = true;
const bool colortex6MipmapEnabled = true;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D gdepthtex;
uniform sampler2D depthtex1;
uniform sampler2D noisetex;
uniform sampler2D shadowtex1;
uniform sampler2DShadow shadow;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowProjection;

uniform vec3 cameraPosition;
uniform vec3 upPosition;

uniform float near;
uniform float far;

uniform float viewWidth;
uniform float viewHeight;

uniform ivec2 eyeBrightnessSmooth;

uniform int isEyeInWater;

varying vec2 texcoord;

#include "/lib/Settings.glsl"
#include "/lib/Utility.glsl"
#include "/lib/Debug.glsl"
#include "/lib/Uniform/Global_Composite_Variables.glsl"
#include "/lib/Fragment/Masks.fsh"
#include "/lib/Misc/Calculate_Fogfactor.glsl"


vec3 GetDiffuse(vec2 coord) {
	return texture2D(colortex1, coord).rgb;
}

float GetDepth(vec2 coord) {
	return texture2D(gdepthtex, coord).x;
}

float GetTransparentDepth(vec2 coord) {
	return texture2D(depthtex1, coord).x;
}

float ExpToLinearDepth(float depth) {
	return 2.0 * near * (far + near - depth * (far - near));
}

vec4 CalculateViewSpacePosition(vec2 coord, float depth) {
	vec4 position  = gbufferProjectionInverse * vec4(vec3(coord, depth) * 2.0 - 1.0, 1.0);
	     position /= position.w;
	
	return position;
}

vec3 GetNormal(vec2 coord) {
	return DecodeNormal(texture2D(colortex4, coord).xy);
}


#include "/lib/Fragment/Calculate_Shaded_Fragment.fsh"

void BilateralUpsample(vec3 normal, float depth, out vec3 GI, out float volFog, out float AO) {
	GI = vec3(0.0);
	volFog = 0.0;
	AO = 0.0;
	
#if (defined GI_ENABLED || defined VOLUMETRIC_FOG || defined AO_ENABLED)
	depth = ExpToLinearDepth(depth);
	
	float totalWeights   = 0.0;
	float totalFogWeight = 0.0;
	float totalAOWeight = 0.0;
	
	cfloat kernal = 2.0;
	cfloat range = kernal - kernal * 0.5 - 0.5;
	
	
	for(float i = -range; i <= range; i++) {
		for(float j = -range; j <= range; j++) {
			vec2 offset = vec2(i, j) / vec2(viewWidth, viewHeight);
			
			float sampleDepth = ExpToLinearDepth(texture2D(gdepthtex, texcoord + offset * 8.0).x);
		
			vec3  sampleNormal = GetNormal(texcoord + offset * 8.0);
		
		#ifdef GI_ENABLED
			
			float weight  = 1.0 - abs(depth - sampleDepth);
			      weight *= dot(normal, sampleNormal);
			      weight  = pow(weight, 32);
			      weight  = max(1.0e-6, weight);
			
			GI += pow(texture2DLod(colortex5, texcoord * COMPOSITE0_SCALE + offset * 2.0, 1).rgb, vec3(2.2)) * weight;
			
			totalWeights += weight;
		#endif
		
		#ifdef AO_ENABLED
			float AOWeight = 1.0 - abs(depth - sampleDepth);
						AOWeight *= dot(normal, sampleNormal);
			      AOWeight = pow(AOWeight, 32);
			      AOWeight = max(1.0e-6, AOWeight);
			
			AO += texture2DLod(colortex5, texcoord * COMPOSITE0_SCALE + offset * 2.0, 1).a * AOWeight;
			
			totalAOWeight += AOWeight;
		#endif
			
		#ifdef VOLUMETRIC_FOG
			float FogWeight = 1.0 - abs(depth - sampleDepth) * 10.0;
			      FogWeight = pow(FogWeight, 32);
			      FogWeight = max(0.1e-8, FogWeight);
			
			volFog += texture2DLod(colortex6, texcoord * COMPOSITE0_SCALE + offset * 2.0, 1).r * FogWeight;
			
			totalFogWeight += FogWeight;
		#endif
		}
	}
	
	GI *= 5.0 / totalWeights;
	volFog /= totalFogWeight;
	AO /= totalAOWeight;
#endif
	
#ifndef AO_ENABLED
	AO = 1.0;
#endif
}


void main() {
	float depth0 = GetDepth(texcoord);
	
	if (depth0 >= 1.0) { discard; }
	
	
	float depth1 = GetTransparentDepth(texcoord);
	
	vec4 encode1 = texture2D(colortex4, texcoord);
	
	vec3 normal = DecodeNormal(encode1.xy);
	
	float smoothness;
	float skyLightmap;
	Decode16(encode1.b, smoothness, skyLightmap);
	
	float torchLightmap;
	Mask  mask;
	Decode16(encode1.a, torchLightmap, mask.materialIDs);
	mask = CalculateMasks(mask.materialIDs);
	
	if (depth0 != depth1) {
		vec3 encode0 = texture2D(colortex0, texcoord).rgb;
		
		mask.transparent = 1.0;
		mask.water   = float(encode0.r >= 0.5);
		mask.matIDs  = 1.0;
		mask.bit[0] *= 1.0 - mask.transparent;
		mask.bit[1]  = mask.transparent;
		mask.bit[2]  = mask.water;
		mask.materialIDs = EncodeMaterialIDs(mask.matIDs, mask.bit[0], mask.bit[1], mask.bit[2], mask.bit[3]);
		
		encode0.r = mod(encode0.r, 0.5);
		
		encode1 = vec4(encode0.rgb, Encode16(vec2(torchLightmap, mask.materialIDs)));
	}
	
	
	vec3 GI; float volFog; float AO;
	BilateralUpsample(normal, depth1, GI, volFog, AO);
	
	gl_FragData[1] = vec4(encode1);
	gl_FragData[2] = vec4(volFog, 0.0, 0.0, 1.0);
	
	
	vec3 diffuse = GetDiffuse(texcoord);
	vec4 viewSpacePosition1 = CalculateViewSpacePosition(texcoord, depth1);
	
	vec3 composite  = CalculateShadedFragment(mask, torchLightmap, skyLightmap, GI, AO, normal, smoothness, viewSpacePosition1);
	     composite *= pow(diffuse * 1.2, vec3(2.8));
	
	gl_FragData[0] = vec4(composite, 1.0);
	
	exit();
}
