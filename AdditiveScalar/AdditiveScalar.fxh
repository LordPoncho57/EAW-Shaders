/*
	Simple additive shader, now with a intensity scalar

    But it's the header file or something.
*/

#include "AlamoEngine.fxh"

//////////////////////
// Material parameters
//////////////////////
texture BaseTexture
<
	string UIName = "BaseTexture";
	string UIType = "bitmap";
>;

float2 UVScrollRate < string UIName="UVScrollRate"; > = { 0.0f, 0.0f };
float3 Color < string UIName="Color"; string UIType = "ColorSwatch"; > = {1.0f, 1.0f, 1.0f};
float  DistortionScale < string UIName="Diffuse Multiplier"; > = 1.0f;

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

////////////////
// Vertex Shader
////////////////

// Data structs

struct VS_OUTPUT
{
    float4 Pos  : POSITION;
    float4 Diff : COLOR0;
    float2 Tex  : TEXCOORD0;
    float  Fog	: FOG;
};

struct VS_INPUT
{
    float3 Pos  : POSITION;
    float2 Tex  : TEXCOORD0;
};

// Calculations

VS_OUTPUT vs_main(VS_INPUT In)
{
    VS_OUTPUT Out = (VS_OUTPUT)0;

    Out.Pos  = mul(float4(In.Pos, 1), m_worldViewProj);             // position (projected)
    Out.Tex  = In.Tex + m_time*UVScrollRate;

   	Out.Diff.rgb = Color * m_lightScale.rgb;
    Out.Diff *= m_lightScale.a;
    Out.Diff.a = 1.0f;

	// Output fog
	Out.Fog = 1.0f; //Compute_Fog(Out.Pos.xyz);

    return Out;
}


// Pixel Shader Code
float4 additive_ps_main(VS_OUTPUT In) : COLOR
{
    float4 texel = tex2D(BaseSampler,In.Tex) * DistortionScale; // Added distortion scalar
    return texel * In.Diff;
}
