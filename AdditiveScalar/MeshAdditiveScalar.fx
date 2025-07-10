/*
	Simple additive shader, now with a intensity scalar
*/

string _ALAMO_RENDER_PHASE = "Transparent";
string _ALAMO_VERTEX_PROC = "Mesh";
string _ALAMO_VERTEX_TYPE = "alD3dVertNU2";
bool _ALAMO_TANGENT_SPACE = false;
bool _ALAMO_SHADOW_VOLUME = false;
bool _ALAMO_Z_SORT = true;

#include "AdditiveScalar.fxh"

// Standard render function
technique t0
<
	string LOD="DX8";
>
{
    pass t0_p0
    {
        SB_START

    		// blend mode
    		ZWriteEnable = FALSE;
    		ZFunc = LESSEQUAL;
    		AlphaBlendEnable = TRUE;
    		DestBlend = ONE;
    		SrcBlend = ONE;
    		AlphaTestEnable = FALSE;
    		
        SB_END        

        // shaders
        VertexShader = compile vs_1_1 vs_main();
        PixelShader  = compile ps_2_0 additive_ps_main(); // Upgraded pixel shader to 2.0 to handle values outside of -1 to 1

    }  
}

// Potato render function
technique t1
<
	string LOD="FIXEDFUNCTION";
>
{
	pass t1_p0
	{
        SB_START

    		// blend mode
    		ZWriteEnable = FALSE;
    		ZFunc = LESSEQUAL;
    		AlphaBlendEnable = TRUE;
    		DestBlend = ONE;
    		SrcBlend = ONE;
    		AlphaTestEnable = FALSE;
    		
            // fixed function vertex pipeline
            FogEnable = false;    // alamo code saves and restores fog state around each effect
            
            // fixed function pixel pipeline
            ColorOp[0]=MODULATE;
    		ColorArg1[0]=TEXTURE;
    		ColorArg2[0]=TFACTOR;
    		AlphaOp[0]=SELECTARG1;
    		AlphaArg1[0]=TEXTURE;
    
    		ColorOp[1]=DISABLE;
    		AlphaOp[1]=DISABLE;

        SB_END        

        // shaders
        VertexShader = NULL;
        PixelShader  = NULL;
        
        Texture[0]=(BaseTexture);
		TextureFactor=(float4(
                                Color.r * m_lightScale.r * m_lightScale.a,
                                Color.g * m_lightScale.g * m_lightScale.a,
                                Color.b * m_lightScale.b * m_lightScale.a,
                                1.0f
                       ) * DistortionScale); // Added distortion scalar
	}
}