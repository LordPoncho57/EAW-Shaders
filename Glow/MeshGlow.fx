/*
	Unlit diffuse shader, with diffuse brightness control
*/

string _ALAMO_RENDER_PHASE = "Transparent";
string _ALAMO_VERTEX_PROC = "Mesh";
string _ALAMO_VERTEX_TYPE = "alD3dVertNU2";
bool _ALAMO_TANGENT_SPACE = false;
bool _ALAMO_SHADOW_VOLUME = false;

#include "Glow.fxh"


// Vertex Shader Code

VS_OUTPUT sph_vs_main(VS_INPUT_MESH In)
{
    VS_OUTPUT Out = (VS_OUTPUT)0;

	Out.Pos = mul(In.Pos,m_worldViewProj);
    Out.Tex0 = In.Tex;

   	Out.Diff.rgb = m_lightScale.rgb;
    Out.Diff *= m_lightScale.a;
    Out.Diff.a = 1.0f;

	// Output fog
	Out.Fog = Compute_Fog(Out.Pos.xyz);

    return Out;
}

vertexshader sph_vs_main_1_1 = compile vs_1_1 sph_vs_main();
pixelshader ps_main_1_1 = compile ps_1_1 gloss_ps_main();

// Techniques
technique max_viewport
{
    pass max_viewport_p0
    {
        SB_START
    		// blend mode
    		ZWriteEnable = TRUE;
    		ZFunc = LESSEQUAL;
    		DestBlend = INVSRCALPHA;
    		SrcBlend = SRCALPHA;
        SB_END        

        // shaders
        VertexShader = (sph_vs_main_1_1); 
        PixelShader  = (ps_main_1_1); 
   		AlphaBlendEnable = (m_lightScale.w < 1.0f); 

    }  
}

technique sph_t0
<
	string LOD="DX8";
>
{
    pass sph_t0_p0
    {
        SB_START
    		// blend mode
    		ZWriteEnable = TRUE;
    		ZFunc = LESSEQUAL;
    		DestBlend = INVSRCALPHA;
    		SrcBlend = SRCALPHA;
        SB_END        

        // shaders
        VertexShader = (sph_vs_main_1_1);
        PixelShader  = (ps_main_1_1); 
   		AlphaBlendEnable = (m_lightScale.w < 1.0f); 
    }  
}

technique sph_t1
<
	string LOD="FIXEDFUNCTION";
>
{
    pass sph_t1_p0
    {
        SB_START

    		// blend mode
    		ZWriteEnable = TRUE;
    		ZFunc = LESSEQUAL;
    		DestBlend = INVSRCALPHA;
    		SrcBlend = SRCALPHA;
    		
            // fixed function pixel pipeline
    		Lighting=false;
    		
    		ColorOp[0]=MODULATE2X;
    		ColorArg1[0]=DIFFUSE;
    		ColorArg2[0]=TEXTURE;
    		AlphaOp[0]=SELECTARG1;
    		AlphaArg1[0]=DIFFUSE;
    		
    		ColorOp[1]=DISABLE;
    		AlphaOp[1]=DISABLE;

        SB_END        

        // shaders
        VertexShader = NULL;
        PixelShader  = NULL; 

   		AlphaBlendEnable = (m_lightScale.w < 1.0f); 

		MaterialAmbient = (float3(1.0f, 1.0f, 1.0f));
        MaterialDiffuse = (float4(m_lightScale.rgb * (DistortionScale * 30), m_lightScale.a)); // Multiply by 15 to boost diffuse power
		MaterialSpecular = (float3(1.0f, 1.0f, 1.0f));
		MaterialEmissive = (float3(0.0f, 0.0f, 0.0f));
		MaterialPower = 32.0f;

		Texture[0]=(BaseTexture);

    }  
}


