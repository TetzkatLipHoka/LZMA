@echo off

goto RAD_STUDIO

:RAD_STUDIO
set files=.\C\Threads.c .\C\LzFind.c .\C\LzFindMt.c .\C\LzmaDec.c .\C\LzmaEnc.c .\C\Lzma2Enc.c .\C\Lzma2Dec.c .\C\MtCoder.c .\C\LzFindOpt.c .\C\MtDec.h

set option=-c -nWin32 -q -D_LZMA_PROB32 -D_WIN32
bcc32.exe %option% .\C\*.c

set option=-c -q -D_LZMA_PROB32 -D_WIN64
bcc64.exe %option% .\C\*.c
move *.o Win64
goto :End

:VISUAL_STUDIO
if "%VisualStudioVersion%"=="" call "C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\bin\x86_amd64\vcvarsx86_amd64.bat"

set option=-c -nologo -wd4273 -wd4099 -FoWin64\ -D_LZMA_PROB32 -D_WIN64
cl.exe %option% .\C\Threads.c
cl.exe %option% .\C\LzFind.c
cl.exe %option% .\C\LzFindMt.c
cl.exe %option% .\C\LzmaDec.c
cl.exe %option% .\C\LzmaEnc.c
cl.exe %option% .\C\Lzma2Enc.c
cl.exe %option% .\C\Lzma2Dec.c
cl.exe %option% .\C\MtCoder.c

:End
set option=
set files=