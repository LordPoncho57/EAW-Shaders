/*
    Fork of the vanilla EaW BumpColorize.fxh

    Changes:
    -Removed unused Shininess parameter
    -Changed UVOffset from a float4 into two float parameters
    -Added UVScaleFactor to control how many times BaseTexture and NormalTexture tile
    -Added MaskTexture to handle AO and faction tinting
    -Added Tex2 to VS_OUTPUT to handle MaskTexture
    -Adjusted Tex0 and Tex1 UV projection calculations in vertex shader to handle new parameters 
    -Added AO and base color mixing in pixel shader
    -Replaced BaseTexture alpha references with MaskTexture green to handle faction tint mask
*/
#include "AlamoEngine.fxh"

// **********************
// Material Parameters
// **********************
float3 Emissive     <string UIName = "Emissive";     string UIType = "ColorSwatch";> = {0.0f, 0.0f, 0.0f };
float3 Diffuse      <string UIName = "Diffuse";      string UIType = "ColorSwatch";> = {1.0f, 1.0f, 1.0f };
float3 Specular     <string UIName = "Specular";     string UIType = "ColorSwatch";> = {1.0f, 1.0f, 1.0f };
float4 Colorization <string UIName = "Colorization"; string UIType = "ColorSwatch";> = {0.0f, 1.0f, 0.0f, 1.0f};
float  UVOffsetX    <string UIName = "UV Offset X";>   = 0.0f;
float  UVOffsetY    <string UIName = "UV Offset Y";>   = 0.0f;
float  UVScaleFactor <string UIName = "Texture Scale";> = 1.0f;

// BaseTexture   : RGB - Color map
// NormalTexture : RG  - Normal map
//                 A   - Gloss map
// MaskTexture   : R   - Ambient occlusion map
//                 G   - Tint mask

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

texture MaskTexture
<
    string UIName = "MaskTexture";
    string UIType = "bitmap"; 
>;

// **********************
// Texture Samples
// **********************
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

sampler MaskSampler = sampler_state
{
    Texture   = (MaskTexture);
	MipFilter = ANISOTROPIC;
    MinFilter = ANISOTROPIC;
    MagFilter = ANISOTROPIC;
	MaxAnisotropy = 16;
    AddressU  = WRAP;        
    AddressV  = WRAP;
};


// **********************
// IO Data Structs
// **********************
struct VS_INPUT_MESH
{
    float4 Pos      : POSITION;
    float3 Normal   : NORMAL;
    float2 Tex      : TEXCOORD0;
    float3 Tangent  : TANGENT0;
    float3 Binormal : BINORMAL0;
};

struct VS_OUTPUT
{
    float4  Pos         : POSITION;
    float4  Diff        : COLOR0;
    float4  Spec        : COLOR1;
    float2  Tex0        : TEXCOORD0; // Base Color
    float2  Tex1        : TEXCOORD1; // Normal
    float2  Tex2        : TEXCOORD2; // Mask
    float3  LightVector : TEXCOORD3;
    float3  HalfAngleVector : TEXCOORD4;
    float   Fog         : FOG;
};

// **********************
// Vertex Shader Functions
// **********************
VS_OUTPUT sph_bump_spec_vs_main(VS_INPUT_MESH In) // DX 9
{
    VS_OUTPUT Out = (VS_OUTPUT)0;

    // Texture Projection controls
    Out.Pos = mul(In.Pos,m_worldViewProj);
    Out.Tex0 = (In.Tex + float2(UVOffsetX, UVOffsetY)) * UVScaleFactor;
    Out.Tex1 = (In.Tex + float2(UVOffsetX, UVOffsetY)) * UVScaleFactor;
    Out.Tex2 = In.Tex;

    // Compute the tangent-space light vector and half-angle vector for per-pixel lighting
    // Note that we are doing everything in object space here.
    float3x3 to_tangent_matrix;
    to_tangent_matrix = Compute_To_Tangent_Matrix(In.Tangent,In.Binormal,In.Normal);
    Out.LightVector = Compute_Tangent_Space_Light_Vector(m_light0ObjVector,to_tangent_matrix);
    Out.HalfAngleVector = Compute_Tangent_Space_Half_Vector(In.Pos,m_eyePosObj,m_light0ObjVector,to_tangent_matrix);

    // Fill lighting is applied per-vertex.  This must be computed in
    // world space for spherical harmonics to work.
    float3 world_pos = mul(In.Pos,m_world);
    float3 world_normal = normalize(mul(In.Normal, (float3x3)m_world));
    float3 diff_light = Sph_Compute_Diffuse_Light_Fill(world_normal);
    
    // Output final vertex lighting colors:
    Out.Diff = float4(diff_light * Diffuse.rgb * m_lightScale.rgb + Emissive, m_lightScale.a);  
    Out.Spec = float4(0,0,0,1);

    // Output fog
    Out.Fog = Compute_Fog(Out.Pos.xyz);

    return Out;
}

VS_OUTPUT sph_bump_vs_main(VS_INPUT_MESH In) // DX 8
{
    VS_OUTPUT Out = (VS_OUTPUT)0;

    Out.Pos = mul(In.Pos,m_worldViewProj);
    Out.Tex0 = (In.Tex + float2(UVOffsetX, UVOffsetY)) * UVScaleFactor;
    Out.Tex1 = (In.Tex + float2(UVOffsetX, UVOffsetY)) * UVScaleFactor;
    Out.Tex2 = In.Tex;

    // Compute the tangent-space light vector
    float3x3 to_tangent_matrix;
    to_tangent_matrix = Compute_To_Tangent_Matrix(In.Tangent,In.Binormal,In.Normal);
    Out.LightVector = Compute_Tangent_Space_Light_Vector(m_light0ObjVector,to_tangent_matrix);

    // Vertex lighting, diffuse fill lights + spec for main light
    float3 world_pos = mul(In.Pos,m_world);
    float3 world_normal = normalize(mul(In.Normal, (float3x3)m_world));
    float3 diff_light = Sph_Compute_Diffuse_Light_Fill(world_normal);
    float3 spec_light = Compute_Specular_Light(world_pos,world_normal);
    
    // Output final vertex lighting colors:
    Out.Diff = float4(diff_light * Diffuse.rgb * m_lightScale.rgb + Emissive, m_lightScale.a);
    Out.Spec = float4(spec_light * Specular, 1);

    // Output fog
    Out.Fog = Compute_Fog(Out.Pos.xyz);
    
    return Out;
}

// **********************
// Pixel Shader Functions
// **********************
float4 bump_spec_colorize_ps_main(VS_OUTPUT In): COLOR // DX 9
{
    // Texture Samples
    float4 baseTexel = tex2D(BaseSampler,In.Tex0);
    float4 normalTexel = tex2D(NormalSampler,In.Tex1);
    float2 maskTexel = tex2D(MaskSampler,In.Tex2);

    // Faction Tinting
    float3 surface_color = lerp(baseTexel.rgb,Colorization*baseTexel.rgb,maskTexel.y);
    surface_color = surface_color * maskTexel.x;

    // Lighting Calculations
    float3 norm_vec = 2.0f*(normalTexel.rgb - 0.5f);
    float3 light_vec = 2.0f*(In.LightVector - 0.5f);
    float3 half_vec = 2.0f*(In.HalfAngleVector - 0.5f);

    float ndotl = saturate(dot(norm_vec,light_vec));
    float ndoth = saturate(dot(norm_vec,half_vec));

    // put it all together
    float3 diff = surface_color * (ndotl*Diffuse*m_light0Diffuse*m_lightScale.rgb + In.Diff.rgb) * 2.0;
    float3 spec = m_light0Specular*Specular*pow(ndoth,16)*normalTexel.a;
    return float4(diff + spec, In.Diff.a);
}

half4 bump_colorize_ps_main(VS_OUTPUT In) : COLOR // DX 8
{
    // Texture Samples
    half4 base_texel = tex2D(BaseSampler,In.Tex0);
    half4 norm_texel = tex2D(NormalSampler,In.Tex1);
    half2 mask_texel = tex2D(MaskSampler,In.Tex2);

    // Faction Tinting
    half3 surface_color = lerp(base_texel.rgb,Colorization*base_texel.rgb,mask_texel.y);
    surface_color = surface_color * mask_texel.x;

    // Lighting Calculations
    half3 norm_vec = 2.0f*(norm_texel.rgb - 0.5f);
    half3 light_vec = 2.0f*(In.LightVector - 0.5f);
    half ndotl = saturate(dot(norm_vec,light_vec));  

    // put it all together
    half3 diffuse = surface_color * (ndotl*Diffuse*m_light0Diffuse*m_lightScale.rgb + In.Diff.rgb) * 2.0;
    half3 specular = In.Spec * norm_texel.a;
    return half4(diffuse + specular, In.Diff.a);
}