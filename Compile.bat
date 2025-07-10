@echo off
title Shader Compiler

:: Fetch the file path of this file
set "scriptDir=%~dp0"
cd %scriptDir%

:: Get shader name, omit the mesh prefix
echo Enter Folder Name: 
set /p fileName=

:CompileShader
echo.
fxc.exe /Tfx_2_0 /LD /Fo"_Compiled/Mesh%fileName%.fxo" "%fileName%/Mesh%fileName%.fx"

echo.
echo Recompile? (Y/N): 
set /p recompileChar=

if /i "%recompileChar%"=="y" (
    echo Rebuilding...
    goto CompileShader
) else (
    echo Exiting Program...
)