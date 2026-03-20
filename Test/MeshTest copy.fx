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

    // Fill lighting is applied per-vertex.  This must be computed in
    // world space for spherical harmonics to work.
    float3 world_normal = normalize(mul(In.Normal, (float3x3)m_world));
    float3 diff_light = Sph_Compute_Diffuse_Light_Fill(world_normal);
    
    // Output final vertex lighting colors:
    Out.Diff = float4(diff_light * Diffuse.rgb * m_lightScale.rgb + Emissive, m_lightScale.a);  
    Out.Spec = float4(0,0,0,1);

    // Output fog
    Out.Fog = Compute_Fog(Out.Pos.xyz);

    return Out;
}


float PI = 3.1415;
float3 FresnelSchlick(float3 F0, float VdotH)
{
    return F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
}

float DistributionGGX(float NdotH, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = (NdotH * NdotH * (a2 - 1.0) + 1.0);
    return a2 / max(PI * denom * denom, 0.001);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float k = (roughness + 1.0);
    k = (k * k) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(float NdotV, float NdotL, float roughness)
{
    float ggx1 = GeometrySchlickGGX(NdotV, roughness);
    float ggx2 = GeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

float gamma = 2.2;
float3 counteract_gamma(float3 color)
{
	return pow(color, gamma);
}

float4 bump_spec_colorize_ps_main2(VS_OUTPUT In): COLOR
{
    // Sample color and normal based off parallax
    float4 baseTexel   = tex2D(BaseSampler, In.Tex0);
    float4 normalTexel = tex2D(NormalSampler,In.Tex1);

    // compute lighting
    float3 norm_vec = 2.0f*(normalTexel.rgb - 0.5f);
    float3 light_vec = 2.0f*(In.LightVector - 0.5f);
    float3 half_vec = 2.0f*(In.HalfAngleVector - 0.5f);

    float ndotl = saturate(dot(norm_vec,light_vec));
    float ndoth = saturate(dot(norm_vec,half_vec));

    // put it all together
    float3 diff = baseTexel * (ndotl*Diffuse*m_light0Diffuse*m_lightScale.rgb + In.Diff.rgb) * 2.0;
    float3 spec = m_light0Specular*Specular*pow(ndoth,16)*normalTexel.a;

    //return float4(half_vec, In.Diff.a);
    return float4(diff + spec, In.Diff.a);
}

float4 bump_spec_colorize_ps_main(VS_OUTPUT In): COLOR // Pixel
{
    float4 baseTexel = tex2D(BaseSampler,In.Tex0);
    float4 normalTexel = tex2D(NormalSampler,In.Tex1);

    // Blend team color
    float3 surface_color = lerp(baseTexel.rgb, (Colorization * baseTexel.rgb), baseTexel.a);
    
    // Build vectors
    float3 vecNorm  = 2.0f * (normalTexel.rgb - 0.5f);
    float3 vecLight = 2.0f * (In.LightVector - 0.5f);
    float3 vecHalf  = 2.0f * (In.HalfAngleVector - 0.5f);
    float3 vecView  = 2.0f * (In.ViewVector - 0.5f);

    // Dot products
    float nDotL = dot(vecNorm, vecLight);
    float nDotV = dot(vecNorm, vecView);
    float nDotH = dot(vecNorm, vecHalf);
    float vDotH = dot(vecView, vecHalf);

	float3 light = counteract_gamma(m_light0Diffuse) * 2;


    float denom = max(4.0 * nDotV * nDotL, 0.001);

    float roughness = 0.5; // Fixed value or pass as uniform later
    float metalness = 0.0; // Assume non-metal for now

    float3 F0 = lerp(float3(0.04, 0.04, 0.04), Specular.rgb, metalness);
    float   D = DistributionGGX(saturate(nDotH), roughness);
    float   G = GeometrySmith(nDotV, nDotL, roughness);
    float3  F = FresnelSchlick(F0, saturate(vDotH));
    float3 specular = (D * G * F) / denom;

    float3 kS = F;
    float3 kD = 1.0 - kS;
    kD *= 1.0 - metalness;

    float3 diffuse = (Diffuse.rgb * surface_color / PI);
    float3 color = (kD * diffuse + specular) * nDotL * light * m_lightScale.rgb;

    //float3 finalColor = color + In.Diff.rgb; // Add fill light
    float3 finalColor = color; // Not blending world colors at the moment
    //return float4(saturate(dot(vecNorm, vecLight)).xxx, 1.0);

    return float4(finalColor * In.Diff, In.Diff.a);
}


float4 asd(VS_OUTPUT In): COLOR // Pixel
{
    float4 baseTexel = tex2D(BaseSampler,In.Tex0);
    float4 normalTexel = tex2D(NormalSampler,In.Tex1);
    //baseTexel.rgb = counteract_gamma(baseTexel.rgb);

    // lerp the colorization
    float3 surface_color = lerp(baseTexel.rgb,Colorization*baseTexel.rgb,baseTexel.a);
    
    //half_vec = normalize(half_vec);
    //light_vec = normalize(light_vec);
    
    /*
    float ndotl = saturate(dot(vecNorm,light_vec));
    float ndoth = saturate(dot(vecNorm,half_vec));

    // put it all together
    float3 diff = surface_color * (ndotl*Diffuse*m_light0Diffuse*m_lightScale.rgb + In.Diff.rgb) * 2.0;
    float3 spec = m_light0Specular*Specular*pow(ndoth,16)*normalTexel.a;
    return float4(diff + spec, In.Diff.a);
    */

    /*
    float3 V = In.ViewVector;
    float3 L = light_vec;
    float3 H = half_vec;
    float3 N = vecNorm;

    float3 N = normalize(vecNorm);
    float3 L = normalize(light_vec);
    float3 V = normalize(float3(0,0,1)); // Or pass from vertex shader
    float3 H = normalize(L + V);
    */

    // compute lighting
    float3 vecNorm  = 2.0f * (normalTexel.rgb - 0.5f);
    float3 vecLight = 2.0f * (In.LightVector - 0.5f);
    float3 vecHalf  = 2.0f * (In.HalfAngleVector - 0.5f);
    float3 vecView = float3(0, 0, 1);



	float3 light = counteract_gamma(m_light0Diffuse) * 2;

    //float nDotL = saturate(dot(vecNorm, vecLight));
    //float nDotV = saturate(dot(vecNorm, V));
    float nDotL = saturate(dot(vecNorm, vecLight));
    float nDotV = saturate(dot(vecNorm, vecView));
    float nDotH = saturate(dot(vecNorm, vecHalf));
    float vDotH = saturate(dot(vecView, vecHalf));

    float denom = max(4.0 * nDotV * nDotL, 0.001);

    float roughness = 0.5; // Fixed value or pass as uniform later
    float metalness = 0.0; // Assume non-metal for now

    float3 F0 = lerp(float3(0.04, 0.04, 0.04), Specular.rgb, metalness);
    //float   D = DistributionGGX(nDotH, roughness);
    float   D = DistributionGGX(saturate(nDotH), roughness);
    float   G = GeometrySmith(nDotV, nDotL, roughness);
    //float3  F = FresnelSchlick(F0, vDotH);
    float3  F = FresnelSchlick(F0, saturate(vDotH));


    float3 specular = (D * G * F) / denom;

    float3 kS = F;
    float3 kD = 1.0 - kS;
    kD *= 1.0 - metalness;

    float3 diffuse = (Diffuse.rgb * surface_color / PI);
    float3 color = (kD * diffuse + specular) * nDotL * light * m_lightScale.rgb;

    //float3 finalColor = color + In.Diff.rgb; // Add fill light
    float3 finalColor = color; // Not blending world colors at the moment
    return float4(finalColor, In.Diff.a);
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