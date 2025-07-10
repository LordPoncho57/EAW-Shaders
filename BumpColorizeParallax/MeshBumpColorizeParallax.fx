string _ALAMO_RENDER_PHASE = "Opaque";
string _ALAMO_VERTEX_PROC = "Mesh";
string _ALAMO_VERTEX_TYPE = "alD3dVertNU2U3U3";
bool _ALAMO_TANGENT_SPACE = true; 
bool _ALAMO_SHADOW_VOLUME = false;

#include "BumpColorizeParallax.fxh"

vertexshader sph_bump_spec_vs_main_bin = compile vs_1_1 sph_bump_spec_vs_main();
pixelshader bump_spec_colorize_ps_main_bin = compile ps_3_0 bump_spec_colorize_ps_main();

//////////////////////////////////////
// Techniques follow
//////////////////////////////////////
technique max_viewport
{
    pass max_viewport_p0
    {
        SB_START
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
<
	string LOD="DX9";
>
{
    pass sph_t2_p0
    {
        SB_START
    		ZWriteEnable = true;
    		ZFunc = LESSEQUAL;
    		DestBlend = INVSRCALPHA;
    		SrcBlend = SRCALPHA;
            ZEnable = true;
            ZWriteEnable = true;
            CullMode = CW;
            AlphaBlendEnable = false; 
        SB_END        

        // shaders 
        VertexShader = (sph_bump_spec_vs_main_bin);
        PixelShader  = (bump_spec_colorize_ps_main_bin);
   		AlphaBlendEnable = (m_lightScale.w < 1.0f); 

    }  
}