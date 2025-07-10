# EAW Shaders
A collection of custom Empire at War shaders in HLSL.

# Compilation
In order to compile, you can either use the Compile.bat file. Or run the command fxc.exe /Tfx_2_0 /LD /Fo"OUTPUT_SHADER_NAME.fxo" "INPUT_SHADER_NAME.fx".

Note: you will need the fxc.exe compiler to do either, as well as the AlamoEngine.fxh library from Empire at War.

# Shader Overview

### AdditiveScalar
This shader exposes a scalar parameter to control the emissive power. Otherwise, it is idential to the vanilla Additive shader

### BumpColorizeParallax
A WIP parallax shader built off the vanilla BumpColorize shader. Utilizes a steep parallax method to achieve the effect.

### BumpColorizeTile
Allows scaling of the color and normal maps in the shader directly. Which enables blending the color map with an embient occlusion and team color mask.

### Glow
An unlit version of the vanilla Gloss shader, with a parameter to control the diffuse color.
