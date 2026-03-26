///////////////////////////////////////////////////////////////////////////////////////////////////
// Petroglyph Confidential Source Code -- Do Not Distribute
///////////////////////////////////////////////////////////////////////////////////////////////////
//
//          $File: //depot/Projects/StarWars_Steam/FOC/Art/Shaders/MeshBumpColorize.fx $
//          $Author: Brian_Hayes $
//          $DateTime: 2017/03/22 10:16:16 $
//          $Revision: #1 $
//
///////////////////////////////////////////////////////////////////////////////////////////////////
/*
    2x Diffuse+Spec lighting, colorization.
    First directional light does dot3 diffuse bump mapping.
    Colorization mask is in the alpha channel of the base texture.
    Spec is modulated by alpha channel of the normal map (gloss)
*/

string _ALAMO_RENDER_PHASE = "Opaque";
string _ALAMO_VERTEX_PROC = "Mesh";
string _ALAMO_VERTEX_TYPE = "alD3dVertNU2U3U3";
bool _ALAMO_TANGENT_SPACE = true; 
bool _ALAMO_SHADOW_VOLUME = false;

#include "BumpColorize.fxh"

float3 RotateZ(float3 v, float angle) {
    float s = sin(angle);
    float c = cos(angle);

    return float3(
        v.x * c - v.y * s,
        v.x * s + v.y * c,
        v.z
    );
}

///////////////////////////////////////////////////////
// Pixel Shader
//
/* NOTES
Diffuse - Shader based color scalar
Specular - Shader based specular highlights
Emissive - Shader bases color addition

m_lightScale - Unknown, engine comments mention lighting adjustments, and fading.
    However, no effects can be seen in the model viewer

m_light0Specular - Map based specular highlight color
m_light0Diffuse - Map based diffuse sun light color

In.Diff - Sphere harmonic lighting passed from vertex shader

2.0 - Magic diffuse color booster
*/
///////////////////////////////////////////////////////
const float PI = 3.14159265f;

// Normal Distribution Function - D
// (alpha^2) / PI((NdotH^2)(alpha^2)+1)^2
float GGX_Distribution(float roughness, float NdotH) {
    float alpha2 = roughness * roughness * roughness * roughness;
    float denom = (NdotH * NdotH) * (alpha2 - 1.0) + 1.0;
    float D = alpha2 / (PI * denom * denom);
    return D;
}

// Schlick’s formula
float3 Fresnel(float3 F0, float VdotH) {
    float3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
    return F;
}

// Geometry Function - G
// Smith GGX
float GGX_Smith(float roughness, float NdotV, float NdotL) {
    float k = (roughness + 1.0);
    k = (k * k) / 8.0;

    float Gv = NdotV / (NdotV * (1.0 - k) + k);
    float Gl = NdotL / (NdotL * (1.0 - k) + k);
    float G = Gv * Gl;
    return G;
}

float4 bump_spec_colorize_ps_main(VS_OUTPUT In): COLOR {
    float4 baseTexel = tex2D(BaseSampler, In.Tex0);
    float4 normalTexel = tex2D(NormalSampler, In.Tex1);

    // Lerp team color
    float3 surface_color = lerp(baseTexel.rgb, Colorization*baseTexel.rgb, baseTexel.a);
    
    float3 N = (2.0f * (float3(normalTexel.rg, 1.0f) - 0.5f));
    float3 V = 2.0f*(In.ViewVector - 0.5f);

    float3 L = 2.0f*(In.LightVector - 0.5f);
    float3 L_Inv = 2.0f*(In.LightVectorInv - 0.5f);

    float3 H = normalize(L + V);
    float3 H_Inv = normalize(L_Inv + V);

    float NdotV = normalize(saturate(dot(N, V)));

    // Convert maps for legacy support
    // Normal.Alpha - Usually houses gloss, this converts to roughness with a minimum of 0.04 to prevent reflections breaking
    // Normal.Blue  - Technically the Z of the normal, but this causes rendering issues so it should normally be 255 white.
        // If someone is lazy and left the Z data, this may cause issues because 255 is 
        // assumed to be non-metal, meaning 0 has to be metal. (Technically making this a dielectric mask)
        // Regardless, this inverts the blue channel for legacy support
        // 1 = dielectric | 0 = metal
    float roughness = 1.0 - normalTexel.a;
    roughness = max(roughness, 0.04f);

    float metallic = normalTexel.b;
    //metallic = 1.0f;
    metallic = max((1.0f - metallic), 0.04);


    float NdotL = saturate(dot(N, L));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    float NdotL_Inv = saturate(dot(N, L_Inv));
    float NdotH_Inv = saturate(dot(N, H_Inv));
    float VdotH_Inv = saturate(dot(V, H_Inv));

    // Rotate about the surface normal
    // V = 2 * dot(V, N) / ||V|| * N - V;
    // Where V is an arbitrary vector being rotated about the surface normal
    float3 L_180 = 2 * NdotL / (L.x * L.x + L.y * L.y + L.z * L.z) * N - L;
    float3 L_Inv180 = 2 * NdotL_Inv / (L_Inv.x * L_Inv.x + L_Inv.y * L_Inv.y + L_Inv.z * L_Inv.z) * N - L_Inv;

    float3 H_180 = normalize(L_180 + V);
    float3 H_Inv180 = normalize(L_Inv180 + V);

    float NdotL_180 = saturate(dot(N, L_180));
    float NdotH_180 = saturate(dot(N, H_180));
    float VdotH_180 = saturate(dot(V, H_180));

    float NdotL_Inv180 = saturate(dot(N, L_Inv180));
    float NdotH_Inv180 = saturate(dot(N, H_Inv180));
    float VdotH_Inv180 = saturate(dot(V, H_Inv180));

    float3 F0 = lerp(float3(0.04,0.04,0.04), surface_color, metallic);

    float D = GGX_Distribution(roughness, NdotH);
    float3 F = Fresnel(F0, VdotH);
    float G = GGX_Smith(roughness, NdotV, NdotL);

    float D2 = GGX_Distribution(roughness, NdotH_180);
    float3 F2 = Fresnel(F0, VdotH_180);
    float G2 = GGX_Smith(roughness, NdotV, NdotL_180);

    float D3 = GGX_Distribution(roughness, NdotH_Inv);
    float3 F3 = Fresnel(F0, VdotH_Inv);
    float G3 = GGX_Smith(roughness, NdotV, NdotL_Inv);

    float D4 = GGX_Distribution(roughness, NdotH_Inv180);
    float3 F4 = Fresnel(F0, VdotH_Inv180);
    float G4 = GGX_Smith(roughness, NdotV, NdotL_Inv180);

    // Put it all together or something
    float3 kd = (1.0 - F0) * (1.0 - metallic); // Mask out metal areas
    float3 term = (NdotL * m_light0Diffuse * m_lightScale.rgb + m_lightAmbient.rgb + In.Diff.rgb);
    float3 diffuse = kd * surface_color / PI * term;
    //float3 diffuse = kd * surface_color / PI;
    //diffuse = kd * surface_color * (NdotL * m_light0Diffuse * m_lightScale.rgb + In.Diff.rgb) * 2.0;

    // Specular
    float3 spec1 = (D * F * G) / max(4.0 * NdotL * NdotV, 0.001);
    float3 spec2 = (D2 * F2 * G2) / max(4.0 * NdotL_180 * NdotV, 0.001);
    float3 spec3 = (D3 * F3 * G3) / max(4.0 * NdotL_Inv * NdotV, 0.001);
    float3 spec4 = (D4 * F4 * G4) / max(4.0 * NdotL_Inv180 * NdotV, 0.001);

    float3 specColor = lerp(m_light0Specular, float3(1,1,1) + m_light0Specular / 5.0f, (metallic));
    spec1 = saturate(spec1) * specColor;
    spec2 = saturate(spec2) * specColor;
    spec3 = saturate(spec3) * specColor;
    spec4 = saturate(spec4) * specColor;

    float3 spec = spec1 + spec2 + spec3 + spec4;

    //spec = spec + F * In.Diff; // Something weird here in the F*diff term causes strange lighting from -Z up

    //float3 spec_env = F0 * (4.0f * In.Diff.rgb) * NdotV;
    //spec_env = F0 + (In.Diff.rgb * 0.5f + 0.5f);
    //spec_env = alpha2 * In.Diff.rgb;
    //float3 spec_indirect = F * In.Diff.rgb;
    float3 spec_indirect = F0 * In.Diff.rgb;

    // Incredibly important for metallic surfaces
    // Without this, at glancing angles surfaces are nearly black
    // However, on non metallic surfaces when viewing from bottom up
    // will cause a spot a to appear when ambient light is cranked from the sphere harmonics

    // Sphere harmonic is partially fixed by removing the ambient light value
    // Now I need a better way to blend the remaining fill lights

    // Note: spec_indirect & diffuse are more or less mutually exclusive
    // Spec_indirect is the reflections used by metal surfaces, so normal diffuse surfaces won't be visible normally


    //float3 color = (diffuse + spec) * m_light0Diffuse * NdotL + surface_color * In.Diff.rgb;
    //float3 color = (diffuse * 2.0f + spec);
    //float3 color = diffuse * 4.0f + spec;
    //color = diffuse * 4.0f + spec;

    // diffuse has a magic booster
        // Primarily for non metal surfaces
    // spec_indirect remaps from 0 to 1 to 0.05 to 1 to aleviate black crush
        // Primarily for metal surfaces

    //return float4(spec_indirect, In.Diff.a);

    float rim = 1.0 - saturate(dot(N, V));
    rim = pow(rim, 2.0); // control sharpness
    float3 rim2 = rim * In.Diff.rgb * 4.0f;

    //return float4(spec, In.Diff.a);
    return float4((diffuse * 4.0f) + spec + (spec_indirect * 0.95 + 0.05), In.Diff.a);
    //return float4((diffuse * 4.0f) + spec + (spec_indirect * 0.95 + 0.05) + rim2, In.Diff.a);
}

///////////////////////////////////////////////////////
// Vertex Shader
//
/* NOTES
Out.Diff - Calculated lignting

diff_light - Sphere harmonics
    Fill lights 1 and 2
    Ambient light
m_lightScale - Unknown, engine comments mention lighting adjustments, and fading. 
    However, no effects can be seen in the model viewer
*/
///////////////////////////////////////////////////////
VS_OUTPUT sph_bump_spec_vs_main(VS_INPUT_MESH In) {
    VS_OUTPUT Out = (VS_OUTPUT)0;

       Out.Pos = mul(In.Pos, m_worldViewProj);
    Out.Tex0 = In.Tex + UVOffset;
    Out.Tex1 = In.Tex + UVOffset;

    // Compute the tangent-space light vector and half-angle vector for per-pixel lighting
    // Note that we are doing everything in object space here.
    float3x3 to_tangent_matrix;
    to_tangent_matrix = Compute_To_Tangent_Matrix(In.Tangent, In.Binormal, In.Normal);
    Out.LightVector = Compute_Tangent_Space_Light_Vector(m_light0ObjVector, to_tangent_matrix);
    Out.LightVectorInv = Compute_Tangent_Space_Light_Vector(-m_light0ObjVector, to_tangent_matrix);
    Out.ViewVector = Compute_Tangent_Space_View_Vector(In.Pos, m_eyePosObj, to_tangent_matrix);
    //Out.HalfVector  = Compute_Tangent_Space_Half_Vector(In.Pos, m_eyePosObj, m_light0ObjVector, to_tangent_matrix);

    // Fill lighting is applied per-vertex.  This must be computed in
    // world space for spherical harmonics to work.
    float3 world_pos = mul(In.Pos, m_world);
    float3 world_normal = normalize(mul(In.Normal, (float3x3)m_world));
    float3 diff_light = Sph_Compute_Diffuse_Light_Fill(world_normal);
    
    // Output final vertex lighting colors:
    //Out.Diff = float4(diff_light * Diffuse.rgb * m_lightScale.rgb + Emissive, m_lightScale.a);  
    //Out.Diff = float4(diff_light * m_lightScale.rgb, m_lightScale.a);
    Out.Diff = float4(diff_light * m_lightScale.rgb, m_lightScale.a);
    Out.Spec = float4(0,0,0,1);

    // Output fog
    Out.Fog = Compute_Fog(Out.Pos.xyz);
    return Out;
}

pixelshader pixel_main = compile ps_2_b bump_spec_colorize_ps_main();
vertexshader vertex_main = compile vs_1_1 sph_bump_spec_vs_main();

//////////////////////////////////////
// Techniques follow
//////////////////////////////////////
technique max_viewport {
    pass max_viewport_p0 {
        SB_START
            // blend mode
            ZWriteEnable = true;
            ZFunc = LESSEQUAL;
            DestBlend = INVSRCALPHA;
            SrcBlend = SRCALPHA;
            AlphaBlendEnable = false;
        SB_END        

        // shaders 
        VertexShader = (vertex_main);
        PixelShader  = (pixel_main);
    }  
}

technique sph_t2
<string LOD="DX9";> {
    pass sph_t2_p0 {
        SB_START
            // blend mode
            ZWriteEnable = true;
            ZFunc = LESSEQUAL;
            DestBlend = INVSRCALPHA;
            SrcBlend = SRCALPHA;
               //AlphaBlendEnable = false; 
        SB_END        

        // shaders 
        VertexShader = (vertex_main);
        PixelShader  = (pixel_main);
           AlphaBlendEnable = (m_lightScale.w < 1.0f); 
    }  
}