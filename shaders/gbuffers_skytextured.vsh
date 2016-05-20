#version 410 compatibility
#define gbuffers_skytextured
#define vsh
#define ShaderStage -10
#include "/lib/Compatibility.glsl"


varying vec3 color;
varying vec2 texcoord;

void main() {
	color    = gl_Color.rgb;
	texcoord = gl_MultiTexCoord0.st;
	
	gl_Position = ftransform();
}