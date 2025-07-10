#include "AlamoEngine.fxh"

// **********************
// Material Parameters
// **********************
float3 Emissive      <string UIName = "Emissive";     string UIType = "ColorSwatch";> = {0.0f, 0.0f, 0.0f };
float3 Diffuse       <string UIName = "Diffuse";      string UIType = "ColorSwatch";> = {1.0f, 1.0f, 1.0f };
float3 Specular      <string UIName = "Specular";     string UIType = "ColorSwatch";> = {1.0f, 1.0f, 1.0f };
float  UVOffsetX     <string UIName = "UV Offset X";> = 0.0f;
float  UVOffsetY     <string UIName = "UV Offset Y";> = 0.0f;
float  ParallaxPower <string UIName = "Parallax Power";>  = 1.0f;
int    ParallaxLayer <string UIName = "Parallax Layers";> = 10;

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
    float4  Pos         : POSITION;
    float4  Diff        : COLOR0;
    float4  Spec        : COLOR1;
    float2  Tex0        : TEXCOORD0;
    float2  Tex1        : TEXCOORD1;
    float  Fog         : FOG;

    float3 LightVector     : TEXCOORD2;
    float3 HalfAngleVector : TEXCOORD3;
    float3 ViewVector      : TEXCOORD4;
};

// **********************
// DX 9 Functions
// **********************
// Vertex Shader
VS_OUTPUT sph_bump_spec_vs_main(VS_INPUT_MESH In)
{
    VS_OUTPUT Out = (VS_OUTPUT)0;

	Out.Pos = mul(In.Pos,m_worldViewProj);
	Out.Tex0 = In.Tex + float2(UVOffsetX, UVOffsetY);                                       
	Out.Tex1 = In.Tex + float2(UVOffsetX, UVOffsetY);

    // Compute the tangent-space light vector and half-angle vector for per-pixel lighting
    // Note that we are doing everything in object space here.
    float3x3 to_tangent_matrix;
    to_tangent_matrix = Compute_To_Tangent_Matrix(In.Tangent,In.Binormal,In.Normal);
    Out.LightVector = Compute_Tangent_Space_Light_Vector(m_light0ObjVector,to_tangent_matrix);
    Out.HalfAngleVector = Compute_Tangent_Space_Half_Vector(In.Pos,m_eyePosObj,m_light0ObjVector,to_tangent_matrix);

    // Get view vector - Code orrowed from grass shader
    float3 view_vec = (float3)m_worldViewInv[2];
    Out.ViewVector = float3(view_vec.x,-view_vec.y,0.0f);
    Out.ViewVector = normalize(Out.ViewVector);

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

float2 ParallaxCalculation(float2 texCoord, float3 viewDir)
{
    // Establish steep parallax values
    //int numLayers = ParallaxStep;
    float layerSize = 1.0 / (float)ParallaxLayer;
    float layerDepth = 0.0;

    // Layer shift
    float2 coordOffset = viewDir.xy * ((float)ParallaxPower / 10.0); // Divide by 10 to reduce power
    float2 coordDelta  = coordOffset / (float)ParallaxLayer;

    // Initial Values
    float2 currentCoords = texCoord;
    float  currentHeightDepth = tex2D(BaseSampler, currentCoords).a;

    // Loop to build layers
    bool isComplete = false;
    for (int i = 0; i < ParallaxLayer; ++i)
    {
        if(!isComplete)
        {
            if (layerDepth >= currentHeightDepth)
            {
                isComplete = true;
            }
            else
            {
                currentCoords += coordDelta;
                currentHeightDepth = tex2D(BaseSampler, currentCoords).a;
                layerDepth += layerSize;
            }
        }
    }
    
    /*
    // Parallax Occlusion Mapping - Trying to blend layers, but this looks bad
    float2 prevCoords = currentCoords + coordDelta;

    float afterDepth  = currentHeightDepth - layerDepth;
    float beforeDepth = tex2D(BaseSampler, prevCoords).a - currentHeightDepth + layerSize;

    float weight = afterDepth / (afterDepth - beforeDepth);

    currentCoords = prevCoords * weight + currentCoords * (1.0 - weight);
    */
    return currentCoords;
}

// Pixel Shader
float4 bump_spec_colorize_ps_main(VS_OUTPUT In): COLOR
{
    // Calculate parallaxed adjusted UVs
    float2 parallaxCoord = ParallaxCalculation(In.Tex0, normalize(In.ViewVector));

    // Sample color and normal based off parallax
    float4 baseTexel = tex2D(BaseSampler,parallaxCoord);
    float4 normalTexel = tex2D(NormalSampler,parallaxCoord);

    // compute lighting
    float3 norm_vec = 2.0f*(normalTexel.rgb - 0.5f);
    float3 light_vec = 2.0f*(In.LightVector - 0.5f);
    float3 half_vec = 2.0f*(In.HalfAngleVector - 0.5f);

    float ndotl = saturate(dot(norm_vec,light_vec));
    float ndoth = saturate(dot(norm_vec,half_vec));

    // put it all together
    float3 diff = baseTexel * (ndotl*Diffuse*m_light0Diffuse*m_lightScale.rgb + In.Diff.rgb) * 2.0;
    float3 spec = m_light0Specular*Specular*pow(ndoth,16)*normalTexel.a;
    return float4(diff + spec, In.Diff.a);
}