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
	float3	ReflectionVector : TEXCOORD5;	// reflection vector in world space
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
	float3 world_pos = mul(In.Pos,m_world);
    float3 world_normal = normalize(mul(In.Normal, (float3x3)m_world));
    float3 diff_light = Sph_Compute_Diffuse_Light_Fill(world_normal);

    // Reflection vector for environment mapping
	float3 V = normalize(m_eyePos - world_pos);
	float3 R = -V + 2.0f * dot(V, world_normal) * world_normal;
    Out.ReflectionVector = normalize(R);

    // Output final vertex lighting colors:
    Out.Diff = float4(diff_light * Diffuse.rgb * m_lightScale.rgb + Emissive, m_lightScale.a);  
    Out.Spec = float4(0,0,0,1);

    // Output fog
    Out.Fog = Compute_Fog(Out.Pos.xyz);

    return Out;
}

// Helper functions for Cook-Torrance
const float PI = 3.14159265f;
float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    return a2 / (PI * denom * denom);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx1 = GeometrySchlickGGX(NdotV, roughness);
    float ggx2 = GeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

float4 bump_spec_colorize_ps_main(VS_OUTPUT In): COLOR // Pixel
{
    // Get texture and cube map samples
    float4 baseTexel   = tex2D(BaseSampler, In.Tex0);
    float4 normalTexel = tex2D(NormalSampler, In.Tex1);
	float3 reflectTexel = texCUBE(SkyCubeSampler, In.ReflectionVector);

    // Blend team color
    baseTexel.rgb = lerp(baseTexel.rgb, (Colorization.rgb * baseTexel.rgb), baseTexel.a);

    float Metallic = normalTexel.b;
    //float Roughness = 1.0f - normalTexel.a;
    float Roughness = saturate(1.0f - normalTexel.a);
    Roughness = max(Roughness, 0.04); // Prevents division by zero in BRDF calculations
    //Metallic = 1.0f;

    float3 N = normalize(2.0f * (float3(normalTexel.rg, 1.0f) - 0.5f));
    float3 V = normalize(2.0f * (In.ViewVector - 0.5f));
    float3 L = normalize(2.0f * (In.LightVector - 0.5f));
    float3 H = normalize(V + L);

    // Cook-Torrance BRDF
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), baseTexel.rgb, Metallic);
    float NDF = DistributionGGX(N, H, Roughness);
    float   G = GeometrySmith(N, V, L, Roughness);
    float3  F = FresnelSchlick(max(dot(H, V), 0.0), F0);

    float NdotL = max(dot(N, L), 0.0);
    float NdotH = max(dot(N, H), 0.0);

    //float3 kS = F;
    //float3 kD = max((1.0 - kS) * (1.0 - Metallic), 0.05); // Prevents pure black
    //float3 kD = (1.0 - kS) * max((1.0 - Metallic), 0.1); // Prevents pure black

    float3 numerator = NDF * G * F;
    float  denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.001;

    float3 diffuse = baseTexel.rgb * (NdotL * m_light0Diffuse.rgb * Diffuse.rgb + In.Diff.rgb) * 2.0;
    float3 specular = (numerator / denominator) * (NdotL * normalTexel.a * m_light0Specular * Specular * pow(NdotH,16));
    float3 reflection = NdotL * reflectTexel * F * Metallic;

    return float4(diffuse + specular + reflection, In.Diff.a);
}


float4 bump_spec_colorize_ps_main2(VS_OUTPUT In): COLOR
{
	float4 baseTexel = tex2D(BaseSampler,In.Tex0);
	float4 normalTexel = tex2D(NormalSampler,In.Tex1);

	// lerp the colorization
	float3 surface_color = lerp(baseTexel.rgb,Colorization*baseTexel.rgb,baseTexel.a);
	
	// compute lighting
	float3 norm_vec = 2.0f*(normalTexel.rgb - 0.5f);
	float3 light_vec = 2.0f*(In.LightVector - 0.5f);
	float3 half_vec = 2.0f*(In.HalfAngleVector - 0.5f);
	//half_vec = normalize(half_vec);
	//light_vec = normalize(light_vec);
	
	float ndotl = saturate(dot(norm_vec,light_vec));
	float ndoth = saturate(dot(norm_vec,half_vec));

	// put it all together
	float3 diff = surface_color * (ndotl*Diffuse*m_light0Diffuse*m_lightScale.rgb + In.Diff.rgb) * 2.0;
	float3 spec = m_light0Specular * Specular * pow(ndoth,16) * normalTexel.a;
	return float4(diff + spec, In.Diff.a);
}


vertexshader sph_bump_spec_vs_main_bin = compile vs_1_1 sph_bump_spec_vs_main();
pixelshader bump_spec_colorize_ps_main_bin = compile ps_3_0 bump_spec_colorize_ps_main();

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