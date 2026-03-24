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

///////////////////////////////////////////////////////
// Vertex Shaders
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
	Out.HalfAngleVector = Compute_Tangent_Space_Half_Vector(In.Pos,m_eyePosObj, m_light0ObjVector, to_tangent_matrix);

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
/* NOTES
Out.Diff - Calculated lignting

diff_light - Sphere harmonics
	Fill lights 1 and 2
	Ambient light
m_lightScale - Unknown, engine comments mention lighting adjustments, and fading. 
	However, no effects can be seen in the model viewer
*/

float4 bump_spec_colorize_ps_main(VS_OUTPUT In): COLOR {
	float4 baseTexel = tex2D(BaseSampler, In.Tex0);
	float4 normalTexel = tex2D(NormalSampler, In.Tex1);

	// lerp the colorization
	float3 surface_color = lerp(baseTexel.rgb, Colorization*baseTexel.rgb, baseTexel.a);
	
	// compute lighting
	float3 norm_vec  = 2.0f*(normalTexel.rgb - 0.5f);
	float3 light_vec = 2.0f*(In.LightVector - 0.5f);
	float3 half_vec  = 2.0f*(In.HalfAngleVector - 0.5f);
	//half_vec = normalize(half_vec);
	//light_vec = normalize(light_vec);
	
	float ndotl = saturate(dot(norm_vec, light_vec));
	float ndoth = saturate(dot(norm_vec, half_vec));

	// put it all together
	//float3 diff = surface_color * (ndotl * Diffuse * m_light0Diffuse * m_lightScale.rgb + In.Diff.rgb) * 2.0;
	//float3 spec = m_light0Specular * Specular * pow(ndoth, 16) * normalTexel.a;

	float3 diff = surface_color * (ndotl * m_light0Diffuse * m_lightScale.rgb + In.Diff.rgb) * 2.0;
	float3 spec = m_light0Specular * pow(ndoth, 16) * normalTexel.a;
	return float4(diff + spec, In.Diff.a);
}

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

vertexshader vertex_main = compile vs_1_1 sph_bump_spec_vs_main();
pixelshader pixel_main = compile ps_2_b bump_spec_colorize_ps_main();

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