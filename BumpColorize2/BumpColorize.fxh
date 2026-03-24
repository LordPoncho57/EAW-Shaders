
#include "AlamoEngine.fxh"

/////////////////////////////////////////////////////////////////////
//
// Material parameters
//
/////////////////////////////////////////////////////////////////////
float3 Emissive < string UIName="Emissive"; string UIType = "ColorSwatch"; > = {0.0f, 0.0f, 0.0f };
float3 Diffuse < string UIName="Diffuse"; string UIType = "ColorSwatch"; > = {1.0f, 1.0f, 1.0f };
float3 Specular < string UIName="Specular"; string UIType = "ColorSwatch"; > = {1.0f, 1.0f, 1.0f };
float  Shininess < string UIName="Shininess"; > = 32.0f;
float4 Colorization < string UIName="Colorization"; string UIType = "ColorSwatch"; > = {0.0f, 1.0f, 0.0f, 1.0f};
float4 UVOffset < string UIName="UVOffset"; > = {0.0f, 0.0f, 0.0f, 0.0f};

texture BaseTexture 
< 
	string UIName = "BaseTexture";
	string UIType = "bitmap"; 
>;

texture NormalTexture
<
	string UIName = "NormalTexture";
	string UIType = "bitmap";
	bool DiscardableBump = true;
>;


/////////////////////////////////////////////////////////////////////
//
// Samplers
//
/////////////////////////////////////////////////////////////////////
sampler BaseSampler = sampler_state
{
    Texture   = (BaseTexture);
	MipFilter = ANISOTROPIC;
    MinFilter = ANISOTROPIC;
    MagFilter = ANISOTROPIC;
	MaxAnisotropy = 16;
    AddressU  = WRAP;        
    AddressV  = WRAP;
};

sampler NormalSampler = sampler_state
{
    Texture   = (NormalTexture);
	MipFilter = ANISOTROPIC;
    MinFilter = ANISOTROPIC;
    MagFilter = ANISOTROPIC;
	MaxAnisotropy = 16;
    AddressU  = WRAP;        
    AddressV  = WRAP;
};

/////////////////////////////////////////////////////////////////////
//
// Input and Output Structures
//
/////////////////////////////////////////////////////////////////////
struct VS_INPUT_MESH
{
	float4 Pos  	: POSITION;
	float3 Normal 	: NORMAL;
	float2 Tex  	: TEXCOORD0;
	float3 Tangent 	: TANGENT0;
	float3 Binormal : BINORMAL0;
};

struct VS_INPUT_SKIN
{
	float4  Pos			: POSITION;
	float4  Normal		: NORMAL;		// Normal.w = skin binding
	float2  Tex			: TEXCOORD0;
	float3  Tangent		: TANGENT0;
	float3  Binormal	: BINORMAL0;
};

struct VS_OUTPUT
{
	float4  Pos     		: POSITION;
	float3	Fill			: COLOR0;
	float3	FillSpec		: COLOR1;
	float2  Tex0    		: TEXCOORD0;
	float3  LightVector		: TEXCOORD1;
	float3  HalfAngleVector	: TEXCOORD2;
	float3	View			: TEXCOORD3;
	float   Fog				: FOG;
};


/////////////////////////////////////////////////////////////////////
//
// Shared Shader Code
//
/////////////////////////////////////////////////////////////////////
VS_OUTPUT sph_bump_spec_vs_main(VS_INPUT_MESH In)
{
    VS_OUTPUT Out = (VS_OUTPUT)0;

   	Out.Pos = mul(In.Pos,m_worldViewProj);
    Out.Tex0 = In.Tex + UVOffset;                                       

	// Compute the tangent-space light vector and half-angle vector for per-pixel lighting
	// Note that we are doing everything in object space here.
	float3x3 to_tangent_matrix;
	to_tangent_matrix = Compute_To_Tangent_Matrix(In.Tangent,In.Binormal,In.Normal);
	Out.LightVector = Compute_Tangent_Space_Light_Vector(m_light0ObjVector,to_tangent_matrix);
	Out.HalfAngleVector = Compute_Tangent_Space_Half_Vector(In.Pos, m_eyePosObj, m_light0ObjVector, to_tangent_matrix);
	Out.View = Compute_Tangent_Space_View_Vector(In.Pos, m_eyePosObj, to_tangent_matrix);
	
	float3 world_normal = normalize(mul(In.Normal, (float3x3)m_world));	
	Out.Fill = AdjustFill(counteract_gamma(Sph_Compute_Diffuse_Light_Fill(world_normal)));
	
	float3 r = reflect(normalize(In.Pos - m_eyePosObj.xyz), world_normal);
	Out.FillSpec = AdjustFillSpecular(counteract_gamma(Sph_Compute_Diffuse_Light_Fill(r)));

	// Output fog
	Out.Fog = Compute_Fog(Out.Pos.xyz);

    return Out;
}

float4 bump_spec_colorize_ps_main(VS_OUTPUT In): COLOR
{	
	float4 baseTexel = tex2D(BaseSampler,In.Tex0);
	baseTexel.rgb = counteract_gamma(baseTexel.rgb);
	float4 normalTexel = tex2D(NormalSampler,In.Tex0);
	
	// Diffuse surface color
	float3 surface_color = lerp(baseTexel.rgb * counteract_gamma(Diffuse), counteract_gamma(Colorization) * baseTexel.rgb, baseTexel.a);
	
	// compute lighting vectors
	float3 n = 2 * normalTexel.rgb - 1;

	float nDotl = saturate(dot(n, In.LightVector));
	float nDoth = saturate(dot(n, In.HalfAngleVector));
	float nDotv = saturate(dot(n, In.View));
	
	float spec_value = specular_remap(normalTexel.a);
    float3 specHighlight = m_light0Specular * Specular * pow(nDoth,20) * normalTexel.a;
	float3 color = Custom_Shading(nDotv, nDoth, nDotl, surface_color, In.Fill, spec_value, In.FillSpec);
	color = Tonemapping(color);


	return float4(color + specHighlight, m_lightScale.a);
}