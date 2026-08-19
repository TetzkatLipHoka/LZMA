program pSizes;
// Struct layout guard for the LZMA include (SDK 26.02).
// Expected values come from sizeof() measurements of the C structs (MSVC cl,
// x86 and x64, defines Z7_LZMA_PROB32) - see finding LZMA1: a layout drift
// between C objects and Pascal records went unnoticed for years because only
// the LZMA2 decode path was affected.
// On an SDK update: re-measure the C side (sizes26.c pattern) and update
// the constants here.
{$APPTYPE CONSOLE}

uses
  LzmaTypes in '..\LzmaTypes.pas',
  LzmaDec in '..\LzmaDec.pas',
  Lzma2Dec in '..\Lzma2Dec.pas',
  LzmaEnc in '..\LzmaEnc.pas',
  Lzma2Enc in '..\Lzma2Enc.pas',
  LzFind in '..\LzFind.pas',
  LzFindMt in '..\LzFindMt.pas',
  MtCoder in '..\MtCoder.pas',
  MtDec in '..\MtDec.pas',
  Threads in '..\Threads.pas';

var
  Fails: Integer = 0;

procedure Check(const aName: string; Actual, Expected: Integer);
begin
  if Actual = Expected then
    Writeln('  [ok]   ', aName, ' = ', Actual)
  else
  begin
    Writeln('  [FAIL] ', aName, ' = ', Actual, ', expected ', Expected);
    Inc(Fails);
  end;
end;

begin
  Check('SizeOf(TCLzmaProps)',     SizeOf(TCLzmaProps),     8);
  Check('SizeOf(TCLzmaDec)',       SizeOf(TCLzmaDec),       {$IFDEF Win64}128{$ELSE}100{$ENDIF});
  Check('SizeOf(TCLzma2Dec)',      SizeOf(TCLzma2Dec),      {$IFDEF Win64}144{$ELSE}116{$ENDIF});
  Check('SizeOf(TCLzmaEncProps)',  SizeOf(TCLzmaEncProps),  80);
  Check('SizeOf(TCLzma2EncProps)', SizeOf(TCLzma2EncProps), 104);
  Check('SizeOf(TCThreadNextGroup)', SizeOf(TCThreadNextGroup), 8);
  Check('SizeOf(TISzAlloc)',       SizeOf(TISzAlloc),       {$IFDEF Win64}16{$ELSE}8{$ENDIF});

  if Fails = 0 then
    Writeln('ALL OK')
  else
    Writeln(Fails, ' FAILURES');
  ExitCode := Fails;
end.
