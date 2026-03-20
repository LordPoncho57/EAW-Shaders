#include "AlamoEngine.fxh"

string _ALAMO_RENDER_PHASE = "Opaque";
string _ALAMO_VERTEX_PROC = "Mesh";
string _ALAMO_VERTEX_TYPE = "alD3dVertNU2U3U3";
bool _ALAMO_TANGENT_SPACE = true; 
bool _ALAMO_SHADOW_VOLUME = false;

// **********************
// Material Parameters
// **********************
float3 Emissive     <string UIName = "Emissive";     string UIType = "ColorSwatch";> = {0.0f, 0.0f, 0.0f };
float3 Diffuse      <string UIName = "Diffuse";      string UIType = "ColorSwatch";> = {1.0f, 1.0f, 1.0f };
float3 Specular     <string UIName = "Specular";     string UIType = "ColorSwatch";> = {1.0f, 1.0f, 1.0f };
float4 Colorization <string UIName = "Colorization"; string UIType = "ColorSwatch";> = {0.0f, 1.0f, 0.0f, 1.0f};
float4 UVOffset     <string UIName = "UVOffset"; > = {0.0f, 0.0f, 0.0f, 0.0f};

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

samplerCUBE SkyCubeSampler = sampler_state 
{ 
    texture = (m_skyCubeTexture); 
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
    float4  Pos  : POSITION;
    float4  Diff : COLOR0;
    float4  Spec : COLOR1;
    float2  Tex0 : TEXCOORD0;
    float2  Tex1 : TEXCOORD1;
    float   Fog  : FOG;

    float3  LightVector      : TEXCOORD2;
    float3  HalfAngleVector  : TEXCOORD3;
    float3  ViewVector       : TEXCOORD4;
    float3  ReflectionVector : TEXCOORD5;  // reflection vector in world space
};

VS_OUTPUT sph_bump_spec_vs_main(VS_INPUT_MESH In) // Vertex
{
    VS_OUTPUT Out = (VS_OUTPUT)0;

    Out.Pos = mul(In.Pos,m_worldViewProj);
    Out.Tex0 = In.Tex + UVOffset;
    Out.Tex1 = In.Tex + UVOffset;

    // Compute the tangent-space light vector and half-angle vector for per-pixel lighting
    // Note that we are doing everything in object space here.
    float3x3 to_tangent_matrix = Compute_To_Tangent_Matrix(In.Tangent, In.Binormal, In.Normal);
    Out.LightVector = Compute_Tangent_Space_Light_Vector(m_light0ObjVector, to_tangent_matrix);
    Out.ViewVector = Compute_Tangent_Space_View_Vector(In.Pos, m_eyePosObj, to_tangent_matrix);
    Out.HalfAngleVector = Compute_Tangent_Space_Half_Vector(In.Pos, m_eyePosObj, m_light0ObjVector, to_tangent_matrix);

    // Calculate game lighting (Fill 1, Fill 2, and Ambient color)
    float3 worldPosition = mul(In.Pos,m_world);
    float3 worldNormal = normalize(mul(In.Normal, (float3x3)m_world));
    float3 worldLight = Sph_Compute_Diffuse_Light_Fill(worldNormal);

    // Reflection vector for environment mapping
    float3 V = normalize(m_eyePos - worldPosition);
    float3 R = -V + 2.0f * dot(V, worldNormal) * worldNormal;
    Out.ReflectionVector = normalize(R);

    // Output final vertex lighting colors:
    Out.Diff = float4(worldLight * Diffuse.rgb * m_lightScale.rgb + Emissive, m_lightScale.a);  
    Out.Spec = float4(0,0,0,1);

    // Output fog
    Out.Fog = Compute_Fog(Out.Pos.xyz);

    return Out;
}

// Helper functions for Cook-Torrance
const float PI = 3.14159265f;
float DistributionGGX(float NdotH, float alpha, float NdotH2)
{
    float alpha2 = alpha * alpha;
    float denom = (NdotH2 * (alpha2 - 1.0) + 1.0);
    return alpha2 / (PI * denom * denom);
}

float GeometrySchlickGGX(float dotProd, float geoFactor, float geoMinus)
{
    return dotProd / (dotProd * geoMinus + geoFactor);
}

float GeometrySmith(float NdotV, float NdotL, float roughness, float roughness2)
{
    float geoFactor = roughness2 / 8.0f;
    float geoMinus  = 1.0f - geoFactor;
    roughness = roughness + 1.0f;

    float ggx1 = GeometrySchlickGGX(NdotV, geoFactor, geoMinus);
    float ggx2 = GeometrySchlickGGX(NdotL, geoFactor, geoMinus);
    return ggx1 * ggx2;
}

float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

float4 bump_spec_colorize_ps_main(VS_OUTPUT In): COLOR
{
    float4 texelBase = tex2D(BaseSampler, In.Tex0);
    float4 texelNorm = tex2D(NormalSampler, In.Tex1);
    float3 texelCube = texCUBE(SkyCubeSampler, In.ReflectionVector);

    texelBase.rgb = lerp(texelBase.rgb, (Colorization.rgb * texelBase.rgb), texelBase.a); // Faction tinting

    // Build Vectors - Skipping pack/unpack to save on instructions, may cause inaccuracies
    /*
    float3 N = 2.0f*(texelNorm.rgb - 0.5f);
    float3 L = In.LightVector;
    float3 H = In.HalfAngleVector;
    float3 V = In.ViewVector;

    // The inaccuracies really are inaccurate, wow
    float3 N = normalize(2.0f * (float3(texelNorm.rg, 1.0f) - 0.5f));
    float3 V = normalize(2.0f * (In.ViewVector - 0.5f));
    float3 L = normalize(2.0f * (In.LightVector - 0.5f));
    float3 H = normalize(V + L);
    */

    // Build Vectors - Skipping pack/unpack to save on instructions, may cause inaccuracies but seems fine
    // Need to normalize per pixel to make reflection work correctly however. This cannot be done in the vertex shader
    float3 N = normalize(2.0f * (float3(texelNorm.rg, 1.0f) - 0.5f));
    float3 L = normalize(In.LightVector);
    float3 H = normalize(In.HalfAngleVector);
    float3 V = normalize(In.ViewVector);


    // Pre build dot products - Use max instead of saturate to save an instruction
    /*
    float NdotL = max(dot(N, L), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float HdotV = max(dot(H, V), 0.0);
    */
    // Seems like MAX is skippable, which saves 4 instructions
    float NdotL = dot(N, L);
    float NdotH = dot(N, H);
    float NdotH2 = NdotH * NdotH;

    float NdotV = dot(N, V);
    float HdotV = dot(H, V);

    // Cook-Torrance BRDF
    float metal = texelNorm.b;
    metal = 0.0f; // A static value seems to save 5 instructions for some reason, might need to be removed entirely
    float rough = max((1.0f - texelNorm.a), 0.04); // Prevents division by zero for glossy surfaces
    float alpha = rough * rough;

    // Can't cut this out, very important for energy conservation with specular highlights
    // Unsure what can be optimized here
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), texelBase.rgb, metal);
    float NDF = DistributionGGX(NdotH, alpha, NdotH2);
    float   G = GeometrySmith(NdotV, NdotL, rough, alpha);
    float3  F = FresnelSchlick(HdotV, F0);

    float3 numerator   = NDF * G * F;
    float  denominator = 4.0 * NdotV * NdotL;

    /*
    // Ripped this out to save on a few instructions, might need to rip metal out entirely

    float3 kS = F; // Fresnel term
    float3 kD = (1.0 - F) * (1.0 - metal); // Diffuse fraction
    kD = 1.0;
    kS = 1.0;

    // Use kD for diffuse, kS for specular/reflection
    float3 diffuse   = kD * texelBase.rgb * (NdotL * m_light0Diffuse.rgb * Diffuse.rgb + In.Diff.rgb) * 2.0;
    float3 specular  = kS * (numerator / denominator) * (NdotL * texelNorm.a * m_light0Specular * Specular * pow(NdotH,16)) * 2;
    float3 reflection = kS * NdotL * texelCube * metal;
    */

    float3 diffuse   = texelBase.rgb * (NdotL * m_light0Diffuse.rgb * Diffuse.rgb + In.Diff.rgb) * 2.0;
    float3 specular  = (numerator / denominator) * (NdotL * texelNorm.a * m_light0Specular * Specular * pow(NdotH2,8)) * 2;
    float3 reflection = NdotL * texelCube * metal;

    return float4(diffuse + specular, In.Diff.a);
}




// ***************************************
// Render Technique and Shader Compilation
// ***************************************
vertexshader sph_bump_spec_vs_main_bin = compile vs_1_1 sph_bump_spec_vs_main();
pixelshader bump_spec_colorize_ps_main_bin = compile ps_2_b bump_spec_colorize_ps_main();

technique sph_t2
<string LOD="DX9";>
{
    pass sph_t2_p0
    {
        SB_START
            ZWriteEnable = true;
            ZFunc = LESSEQUAL;
            DestBlend = INVSRCALPHA;
            SrcBlend = SRCALPHA;
        SB_END        

        // shaders 
        VertexShader = (sph_bump_spec_vs_main_bin);
        PixelShader  = (bump_spec_colorize_ps_main_bin);
        AlphaBlendEnable = (m_lightScale.w < 1.0f); 
    }  
}