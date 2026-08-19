@echo off
rem ============================================================================
rem LZMA SDK 26.02 - object build for the Delphi include (sync 2026-08-10)
rem
rem Win32: OMF via bcc32c (portable C++Builder command-line tools 12.2)
rem        -> links with dcc32 from Delphi 7 upwards (OMF)
rem Win64: COFF via MSVC cl (VS 2026 Community)
rem        -> dcc64 links COFF since XE2; ONE set covers Win64 AND Win64x
rem
rem The special handling required by older SDKs is gone with 26.02:
rem  - no more exit->fxit patching (debug macros removed upstream)
rem  - Win64: -GS- removes the MSVC security-cookie symbols,
rem           -DNDEBUG removes the assert paths
rem After EVERY rebuild: run Source\Tests\build_run.ps1 (layout guard+roundtrip)!
rem ============================================================================

set FILES=Threads.c LzFind.c LzFindMt.c LzFindOpt.c LzmaDec.c LzmaEnc.c Lzma2Enc.c Lzma2Dec.c MtCoder.c MtDec.c CpuArch.c 7zStream.c
set DEFS=-DNDEBUG -DZ7_LZMA_PROB32

rem --- adjust paths if needed ---
set BCC=D:\Delphi\___Claude Workspace\uTLH\BorlandComandlineCompiler
set VCVARS=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat

echo ######## Win32 (OMF, bcc32c) ########
pushd "%~dp0"
for %%F in (%FILES%) do (
  "%BCC%\bin\bcc32c.exe" -c -q %DEFS% -D_WIN32 -I"%BCC%\include\windows\crtl" -I"%BCC%\include\windows\sdk" ".\C\%%F"
)
move /Y *.obj Win32\ >nul
popd

echo ######## Win64 (COFF, MSVC cl) ########
call "%VCVARS%" >nul 2>&1
pushd "%~dp0"
for %%F in (%FILES%) do (
  cl -c -nologo -O2 -wd4273 -wd4099 -GS- %DEFS% -D_WIN64 ".\C\%%F"
)
rem Delphi convention: Win64 objects are named .o
for %%F in (*.obj) do move /Y "%%F" "Win64\%%~nF.o" >nul
popd

echo.
echo Done. Copy the objects to ..\Source\Win32 and ..\Source\Win64 and run
echo Source\Tests\build_run.ps1. Check the file SIZES afterwards - a 0-byte
echo object means the compiler aborted silently!
