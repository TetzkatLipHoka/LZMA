SDK 26.02 (sync 2026-08-10):

The old hex-editor patch (LzFindMt.o x64: 'exit' -> 'fxit') is OBSOLETE -
the exit reference is gone from the sources since SDK 26.02.
(If it ever comes back: use the compiler switch -Dexit=fxit instead of
a hex editor.)

Build: compile.bat (Win32 = OMF/bcc32c portable, Win64 = COFF/MSVC cl).
One Win64 COFF set covers classic Win64 AND Win64x.
After every rebuild run ..\Source\Tests\build_run.ps1
(struct layout guard + roundtrip of all three APIs, W32+W64, optional -D7).

Old 21.07 sources: .\C_21.07, old objects: ..\Source\_backup_21.07
