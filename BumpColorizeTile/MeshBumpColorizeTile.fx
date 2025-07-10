/*
    Fork of the vanilla EaW MeshBumpColorize

    Changes:
    -Moved vertex functions into header file
    -Upgraded bump_colorize_ps_main_bin from PS_1_1 to PS_2_0

*/
string _ALAMO_RENDER_PHASE = "Opaque";
string _ALAMO_VERTEX_PROC = "Mesh";
string _ALAMO_VERTEX_TYPE = "alD3dVertNU2U3U3";
bool _ALAMO_TANGENT_SPACE = true; 
bool _ALAMO_SHADOW_VOLUME = false;

#include "BumpColorizeTile.fxh"

// DX 9
vertexshader sph_bump_spec_vs_main_bin = compile vs_1_1 sph_bump_spec_vs_main();
pixelshader bump_spec_colorize_ps_main_bin = compile ps_2_0 bump_spec_colorize_ps_main();

// DX 8 - Pointless nowadays?
vertexshader sph_bump_vs_main_bin = compile vs_1_1 sph_bump_vs_main();
pixelshader bump_colorize_ps_main_bin = compile ps_2_0 bump_colorize_ps_main();

// ******************
// Techniques follow
// ******************
technique max_viewport
{
    pass max_viewport_p0
    {
        SB_START
            // blend mode
            ZWriteEnable = true;
            ZFunc = LESSEQUAL;
            DestBlend = INVSRCALPHA;
            SrcBlend = SRCALPHA;
            AlphaBlendEnable = false;
        SB_END        

        // shaders 
        VertexShader = (sph_bump_spec_vs_main_bin);
        PixelShader  = (bump_spec_colorize_ps_main_bin);
    }  
}

technique sph_t2
<string LOD="DX9";>
{
    pass sph_t2_p0
    {
        SB_START

            // blend mode
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

technique sph_t1
<string LOD="DX8";>
{
    pass sph_t1_p0
    {
        SB_START
            // blend mode
            ZWriteEnable = true;
            ZFunc = LESSEQUAL;
            DestBlend = INVSRCALPHA;
            SrcBlend = SRCALPHA;
        SB_END        

        // shaders
        VertexShader = (sph_bump_vs_main_bin);
        PixelShader  = (bump_colorize_ps_main_bin);
        AlphaBlendEnable = (m_lightScale.w < 1.0f); 
    }  
}


technique t0
<string LOD="FIXEDFUNCTION";>
{
    pass t0_p0
    {
        SB_START
            // blend mode
            ZWriteEnable = true;
            ZFunc = LESSEQUAL;
            DestBlend = INVSRCALPHA;
            SrcBlend = SRCALPHA;
        SB_END        

        // shaders
        VertexShader = (sph_bump_vs_main_bin);
        PixelShader  = (bump_colorize_ps_main_bin);
        AlphaBlendEnable = (m_lightScale.w < 1.0f); 
    }  
}


/*
technique t0
<string LOD="FIXEDFUNCTION";>
{
    pass t0_p0 
    {
        SB_START
            // blend mode
            ZWriteEnable = true;
            ZFunc = LESSEQUAL;
            DestBlend = INVSRCALPHA;
            SrcBlend = SRCALPHA;
            
            // fixed function pixel pipeline
            Lighting=true;
             
            MinFilter[0]=LINEAR;
            MagFilter[0]=LINEAR;
            MipFilter[0]=LINEAR;
            AddressU[0]=wrap;
            AddressV[0]=wrap;
            TexCoordIndex[0]=0;
    
            ColorOp[0]=BLENDTEXTUREALPHA;
            ColorArg1[0]=TFACTOR;
            ColorArg2[0]=TEXTURE; 
            AlphaOp[0]=SELECTARG1;
            AlphaArg1[0]=TEXTURE;
    
            ColorOp[1]=MODULATE2X;
            ColorArg1[1]=DIFFUSE;
            ColorArg2[1]=CURRENT;
            AlphaOp[1]=SELECTARG1;
            AlphaArg1[1]=DIFFUSE;
            
            ColorOp[2] = DISABLE;
            AlphaOp[2] = DISABLE;
        SB_END

        // shaders
        VertexShader = NULL;
        PixelShader  = NULL;
        
        AlphaBlendEnable = (m_lightScale.w < 1.0f); 
        MaterialAmbient = (Diffuse);
        MaterialDiffuse = (float4(Diffuse.rgb*m_lightScale.rgb,m_lightScale.a));
        MaterialSpecular = (Specular);
        MaterialEmissive = (Emissive);
        MaterialPower = 32.0f;
        Texture[0]=(BaseTexture);
        TextureFactor=(Colorization);
    }  
}
*/