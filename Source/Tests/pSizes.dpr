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
  Threads in '..\Threads.pas',
  Bcj2 in '..\Bcj2.pas',
  LZMA2 in '..\LZMA2.pas',
  Bra in '..\Bra.pas',
  LZMAExe in '..\LZMAExe.pas',
  SevenZipIn in '..\SevenZipIn.pas';

var
  Fails: Integer = 0;
  PCBcj2EncDummy: ^TCBcj2Enc = nil; // offsetof via nil pointer
  PCBcj2DecDummy: ^TCBcj2Dec = nil;
  PArEx: ^TCSzArEx = nil;
  PLook: ^TCLookToRead2 = nil;

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
  Check('SizeOf(TCBcj2Dec)',       SizeOf(TCBcj2Dec),       {$IFDEF Win64}616{$ELSE}576{$ENDIF});
  Check('SizeOf(TCBcj2Enc)',       SizeOf(TCBcj2Enc),       {$IFDEF Win64}672{$ELSE}632{$ENDIF});
  Check('TCBcj2Enc.low offset',    NativeInt(@PCBcj2EncDummy^.low), {$IFDEF Win64}96{$ELSE}56{$ENDIF});
  Check('TCBcj2Enc.probs offset',  NativeInt(@PCBcj2EncDummy^.probs), {$IFDEF Win64}156{$ELSE}116{$ENDIF});
  Check('TCBcj2Dec.probs offset',  NativeInt(@PCBcj2DecDummy^.probs), {$IFDEF Win64}100{$ELSE}60{$ENDIF});
  Check('SizeOf(TCSzAr)',          SizeOf(TCSzAr),          {$IFDEF Win64}88{$ELSE}56{$ENDIF});
  Check('SizeOf(TCSzArEx)',        SizeOf(TCSzArEx),        {$IFDEF Win64}224{$ELSE}136{$ENDIF});
  Check('TCSzAr.RangeLimit offset',  NativeInt(@PArEx^.db.RangeLimit), {$IFDEF Win64}80{$ELSE}48{$ENDIF});
  Check('TCSzArEx.NumFiles offset',  NativeInt(@PArEx^.NumFiles), {$IFDEF Win64}104{$ELSE}72{$ENDIF});
  Check('TCSzArEx.MTime offset',     NativeInt(@PArEx^.MTime), {$IFDEF Win64}160{$ELSE}100{$ENDIF});
  Check('TCSzArEx.FileNames offset', NativeInt(@PArEx^.FileNames), {$IFDEF Win64}216{$ELSE}128{$ENDIF});
  Check('SizeOf(TCLookToRead2)',   SizeOf(TCLookToRead2),   {$IFDEF Win64}72{$ELSE}36{$ENDIF});
  Check('TCLookToRead2.buf offset',  NativeInt(@PLook^.buf), {$IFDEF Win64}56{$ELSE}28{$ENDIF});
  Check('SizeOf(TISzAlloc)',       SizeOf(TISzAlloc),       {$IFDEF Win64}16{$ELSE}8{$ENDIF});

  if Fails = 0 then
    Writeln('ALL OK')
  else
    Writeln(Fails, ' FAILURES');
  ExitCode := Fails;
end.
