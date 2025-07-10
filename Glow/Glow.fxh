/*
	Unlit diffuse shader, with diffuse brightness control
*/

#include "AlamoEngine.fxh"


// material parameters
float  DistortionScale < string UIName="Diffuse Multiplier"; > = 1.0f;

texture BaseTexture
<
	string UIName = "BaseTexture";
	string UIType = "bitmap";
>;

sampler BaseSampler = sampler_state 
{
    texture = (BaseTexture);
    AddressU  = WRAP;        
    AddressV  = WRAP;
    AddressW  = CLAMP;
    MIPFILTER = LINEAR;
    MINFILTER = LINEAR;
    MAGFILTER = LINEAR;
};

// Data Structures

struct VS_INPUT_MESH
{
    float4 Pos  : POSITION;
    float3 Norm : NORMAL;
    float2 Tex  : TEXCOORD0;
};

struct VS_OUTPUT
{
    float4  Pos     : POSITION;
    float4  Diff	: COLOR0;
    float4  Spec	: COLOR1;
    float2  Tex0    : TEXCOORD0;
    float  Fog		: FOG;
};


// Pixel Shader Code

float4 gloss_ps_main(VS_OUTPUT In) : COLOR
{
	float4 base_texel = tex2D(BaseSampler,In.Tex0);
	float3 diffuse = (In.Diff.rgb * base_texel.rgb * DistortionScale * 2);
	//float3 specular = In.Spec.rgb * base_texel.a;
	return float4(diffuse,In.Diff.a);
}
