#ifndef AO_ENABLED
	#define CalculateSSAO(a, b) 1.0
#elif AO_MODE == 1 // AlchemyAO
float CalculateSSAO(vec4 viewSpacePosition, vec3 normal) {
	cint samples = 12;
	cfloat radius = 0.7;
	cfloat intensity = 0.10;
	cfloat depthBias = 0.00025;
	
	float sampleArea = radius / viewSpacePosition.z;
	float sampleStep = sampleArea / samples;
	
	float randomAngle = GetDitherred2DNoise(texcoord, 64.0).x * 6.28318530718; // 6.28318530718 is 2.0 * PI
	cfloat angleMarch = 6.28318530718 / samples;
	float AO;

	for(int i = 0; i < samples; i++) {
		vec2 pixelOffset = texcoord + vec2(sampleStep * cos(randomAngle), sampleStep * sin(randomAngle));
		vec3 offsetPosition = CalculateViewSpacePosition(pixelOffset, GetDepth(pixelOffset)).xyz;
		
		vec3 differential = offsetPosition - viewSpacePosition.xyz;
		float diffLength = lengthSquared(differential);
		
		float EdgeError = step(0.0, pixelOffset.x) * step(0.0, 1.0 - pixelOffset.x) *
                      step(0.0, pixelOffset.y) * step(0.0, 1.0 - pixelOffset.y);

		AO += (max0(dot(normal, differential) + depthBias * viewSpacePosition.z) * step(sqrt(diffLength), radius) * EdgeError) / (diffLength + 0.0001);
		randomAngle += angleMarch;
	}
	return max0(1.0 - (AO * (2 * intensity)) / samples);
}

#else // HBAO

// HBAO paper http://rdimitrov.twistedsanity.net/HBAO_SIGGRAPH08.pdf
// HBAO SIGGRAPH presentation http://developer.download.nvidia.com/presentations/2008/SIGGRAPH/HBAO_SIG08b.pdf
float CalculateSSAO(vec4 viewSpacePosition, vec3 normal) {
	cfloat sampleRadius     = 0.5;
	cint   sampleDirections = 6;
	cfloat sampleStep       = 0.016;
	cint   sampleStepCount  = 2;
	cfloat tanBias          = 0.2;
	
	float AO;
	
	vec2 noise = GetDitherred2DNoise(texcoord * COMPOSITE0_SCALE, 64.0).xy;
	
	float  angle = noise.x * 2.0 * PI;
	cfloat sampleDirInc = 2.0 * PI / sampleDirections;
	
	for(uint i = 0; i < sampleDirections; i++) {
		vec2 sampleDir = vec2(cos(angle), sin(angle));
		
		angle += sampleDirInc;
		
		float tangentAngle = acos(dot(vec3(sampleDir, 0.0), normal)) - (PI * 0.5) + tanBias;
		float horizonAngle = tangentAngle;
		
		vec3 prevDiff;
		
		for(uint j = 0; j < sampleStepCount; j++) {
			vec2 sampleOffset = (j + noise.y) * sampleStep * sampleDir;
			vec2 offsetCoord  = texcoord + sampleOffset;
			
			float offsetDepth = GetDepth(offsetCoord);
			
			vec3 offsetViewSpace = CalculateViewSpacePosition(offsetCoord, offsetDepth).xyz;
			vec3 differential    = offsetViewSpace - viewSpacePosition.xyz;
			
			if(length(differential) < sampleRadius) {
				prevDiff = differential;
				
				float elevationAngle = atan(differential.z / length(differential.xy));
				
				horizonAngle = max(horizonAngle, elevationAngle);
			}
		}
		
		float attenuation = 1.0 / (1.0 + length(prevDiff));
		float occlusion = clamp01(attenuation * (sin(horizonAngle) - sin(tangentAngle)));
		
		AO += occlusion;
	}
	
	AO *= 3.0 / (sampleDirections * sampleStepCount);
	AO  = clamp01(1.0 - sqrt(AO));
	
	return AO;
}
#endif
