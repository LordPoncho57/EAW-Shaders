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

    float3  LightVector     : TEXCOORD2;
    float3  HalfAngleVector : TEXCOORD3;
    float3  ViewVector      : TEXCOORD4;
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
    Out.LightVector     = Compute_Tangent_Space_Light_Vector(m_light0ObjVector, to_tangent_matrix);
    Out.HalfAngleVector = Compute_Tangent_Space_Half_Vector(In.Pos, m_eyePosObj, m_light0ObjVector, to_tangent_matrix);
	Out.ViewVector      = Compute_Tangent_Space_View_Vector(In.Pos, m_eyePosObj, to_tangent_matrix);

    // Calculate game lighting (Fill 1, Fill 2, and Ambient color)
    float3 world_normal = normalize(mul(In.Normal, (float3x3)m_world));
    float3 diff_light = Sph_Compute_Diffuse_Light_Fill(world_normal);
    
    // Output final vertex lighting colors:
    Out.Diff = float4(diff_light * Diffuse.rgb * m_lightScale.rgb + Emissive, m_lightScale.a);  
    Out.Spec = float4(0,0,0,1);

    // Output fog
    Out.Fog = Compute_Fog(Out.Pos.xyz);

    return Out;
}

float4 CookTorrance(float NdotL, float NdotV, float NdotH, float VdotH, float rough1, float specFactor)
{
    rough1 = specFactor;
    rough1 *= 3.0f;

    float G1 = (2.0f * NdotH * NdotV) / VdotH;
    float G2 = (2.0f * NdotH * NdotL) / VdotH;
    float G  = min(1.0f, max(0.0f, min(G1,G2)));

    // Fresnel
    
    float F0 = lerp(0.04, 0.6, specFactor);
    float F  = F0 + (1.0f - F0) * pow(1.0f - NdotV, 5.0f);

    float roughSquare = rough1 * rough1;
    float NdotHSquare = NdotH * NdotH;
    float A = 1.0f / (4.0f * roughSquare * NdotHSquare * NdotHSquare);
    float B = exp(-(1.0f - NdotHSquare) / (roughSquare * NdotHSquare));
    float R = A * B;

    return ((G * F * R) / (NdotL * NdotV));
}

float4 bump_spec_colorize_ps_main(VS_OUTPUT In): COLOR // Pixel
{
    float4 baseTexel = tex2D(BaseSampler,In.Tex0);
    float4 normalTexel = tex2D(NormalSampler,In.Tex1);

    // Blend team color
    float3 surface_color = lerp(baseTexel.rgb, (Colorization * baseTexel.rgb), baseTexel.a);
    
    // Build vectors
    // Normal, Lighting, Half-Angle, and View
    float3 N = 2.0f * (normalTexel.rgb - 0.5f);
    float3 L = 2.0f * (In.LightVector - 0.5f);
    float3 H = 2.0f * (In.HalfAngleVector - 0.5f);
    float3 V = 2.0f * (In.ViewVector - 0.5f);

    float NdotL = dot(N,L);
    float NdotH = dot(N,H);
    float NdotV = dot(N,V);
    float VdotH = dot(V,H);
    float diffuseLight = saturate(NdotL);


    float3 diff = baseTexel * (NdotL * Diffuse * m_light0Diffuse * m_lightScale.rgb + In.Diff.rgb) * 2.0;
    float3 spec = m_light0Specular * Specular * pow(NdotH,16) * normalTexel.a;
    return float4(diff + spec, In.Diff.a);

    float3 specFactor = m_light0Specular * Specular * pow(NdotH,16) * normalTexel.a;
    float4 specularColor = CookTorrance(NdotL, NdotV, NdotH, VdotH, 1, specFactor);
    return float4( surface_color + specularColor, 1);
}


vertexshader sph_bump_spec_vs_main_bin = compile vs_1_1 sph_bump_spec_vs_main();
pixelshader bump_spec_colorize_ps_main_bin = compile ps_2_0 bump_spec_colorize_ps_main();

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