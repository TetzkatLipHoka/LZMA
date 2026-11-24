program pExe;
// Branch filters for executables (Bra.c/Bra86.c BCJ, Bcj2.c/Bcj2Enc.c BCJ2)
// and the LZMAExe format 'lzx2'. Test data: this test exe itself (PE i386
// resp. AMD64). Optional ParamStr(1) = a PE file -> prints the sizes for
// comparison with 7z (plain LZMA2, BCJ+LZMA2, BCJ2+LZMA2+LZMA lc0 lp2).
{$APPTYPE CONSOLE}

{$IFNDEF Win64} // like LZMA.inc
  {$DEFINE UNDERSCORE}
{$ENDIF}

uses
  SysUtils, Classes, Types,
  LzmaTypes in '..\LzmaTypes.pas',
  LzFind in '..\LzFind.pas',
  LzFindMt in '..\LzFindMt.pas',
  LzmaEnc in '..\LzmaEnc.pas',
  LzmaDec in '..\LzmaDec.pas',
  Lzma2Enc in '..\Lzma2Enc.pas',
  Lzma2Dec in '..\Lzma2Dec.pas',
  MtCoder in '..\MtCoder.pas',
  MtDec in '..\MtDec.pas',
  Threads in '..\Threads.pas',
  LZMA2 in '..\LZMA2.pas',
  Bra in '..\Bra.pas',
  Bcj2 in '..\Bcj2.pas',
  LZMAExe in '..\LZMAExe.pas';

var
  Fails: Integer = 0;

procedure Check(const aName: string; Cond: Boolean);
begin
  if Cond then
    Writeln('  [ok]   ', aName)
  else
  begin
    Writeln('  [FAIL] ', aName);
    Inc(Fails);
  end;
end;

function LoadFile(const FileName: string): TByteDynArray;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[0], F.Size);
  finally
    F.Free;
  end;
end;

function Same(const A, B: TByteDynArray): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

// LZMA (not LZMA2) with lc/lp as 7z uses it for the BCJ2 CALL/JUMP streams
function LzmaSize(const Data: TByteDynArray; lc, lp: Integer): Int64;
var
  Enc: TCLzmaEncHandle;
  Props: TCLzmaEncProps;
  Buf: TByteDynArray;
  OutLen: NativeInt;
begin
  Result := 0;
  if Length(Data) = 0 then
    Exit;
  Enc := {$IFDEF UNDERSCORE}_LzmaEnc_Create{$ELSE}LzmaEnc_Create{$ENDIF}(TISzAllocDefault);
  {$IFDEF UNDERSCORE}_LzmaEncProps_Init{$ELSE}LzmaEncProps_Init{$ENDIF}(Props);
  Props.level := 9;
  Props.lc := lc;
  Props.lp := lp;
  {$IFDEF UNDERSCORE}_LzmaEnc_SetProps{$ELSE}LzmaEnc_SetProps{$ENDIF}(Enc, Props);
  SetLength(Buf, Length(Data) + Length(Data) div 2 + 1024);
  OutLen := Length(Buf);
  if {$IFDEF UNDERSCORE}_LzmaEnc_MemEncode{$ELSE}LzmaEnc_MemEncode{$ENDIF}(Enc, @Buf[0], OutLen, @Data[0], Length(Data),
       0{no end mark, 7z stores sizes}, nil, TISzAllocDefault, TISzAllocDefault) = SZ_OK then
    Result := OutLen;
  {$IFDEF UNDERSCORE}_LzmaEnc_Destroy{$ELSE}LzmaEnc_Destroy{$ENDIF}(Enc, TISzAllocDefault, TISzAllocDefault);
end;

procedure Bcj2Roundtrip(const aName: string; const Data: TByteDynArray);
var
  S: TBcj2Streams;
  Back: TByteDynArray;
begin
  Check(aName + ': Bcj2Encode', Bcj2Encode(@Data[0], Length(Data), S));
  Check(aName + ': MAIN+CALL+JUMP = size',
    Length(S[0]) + Length(S[1]) + Length(S[2]) = Length(Data));
  SetLength(Back, Length(Data));
  Check(aName + ': Bcj2Decode', Bcj2Decode(S, @Back[0], Length(Back)));
  Check(aName + ': BCJ2 roundtrip byte-identical', Same(Back, Data));
end;

procedure Measure(const FileName: string);
var
  Data, Plain, Exe, Main: TByteDynArray;
  S: TBcj2Streams;
  nCall, nJump: Int64;
begin
  Data := LoadFile(FileName);
  Writeln('--- ', FileName, ' (', Length(Data), ' bytes)');
  CompressLZMA2(@Data[0], Length(Data), Plain, False, 9);
  CompressExe(@Data[0], Length(Data), Exe, efAuto, 9);
  Writeln('    LZMA2 9 without filter : ', Length(Plain));
  Writeln('    lzx2 (BCJ + LZMA2 9)   : ', Length(Exe));
  if Bcj2Encode(@Data[0], Length(Data), S) then
  begin
    CompressLZMA2(@S[0][0], Length(S[0]), Main, False, 9);
    nCall := LzmaSize(S[1], 0, 2);
    nJump := LzmaSize(S[2], 0, 2);
    Writeln('    BCJ2 streams M/C/J/RC   : ', Length(S[0]), ' / ', Length(S[1]), ' / ', Length(S[2]), ' / ', Length(S[3]));
    Writeln('    BCJ2 + LZMA2 + LZMA    : ', Int64(Length(Main)) + nCall + nJump + Length(S[3]),
      '  (main ', Length(Main), ', call ', nCall, ', jump ', nJump, ', rc raw ', Length(S[3]), ')');
  end;
end;

var
  Me, Work, Comp, Back, Rnd, Fake: TByteDynArray;
  n: Int64;
  i: Integer;

begin
  try
    Me := LoadFile(ParamStr(0));

    // --- detection by content ---
    Check('DetectExeFilter(own exe) = x86', DetectExeFilter(@Me[0], Length(Me)) = efX86);
    SetLength(Fake, 512);
    FillChar(Fake[0], Length(Fake), 0);
    Fake[0] := Ord('M'); Fake[1] := Ord('Z');
    PCardinal(@Fake[$3C])^ := $80;
    Fake[$80] := Ord('P'); Fake[$81] := Ord('E');
    PWord(@Fake[$84])^ := $AA64;
    Check('DetectExeFilter(PE ARM64) = ARM64', DetectExeFilter(@Fake[0], Length(Fake)) = efARM64);
    PWord(@Fake[$84])^ := $01C4; // ARMNT: no filter
    Check('DetectExeFilter(PE ARMNT) = none', DetectExeFilter(@Fake[0], Length(Fake)) = efNone);
    PCardinal(@Fake[$3C])^ := $7FFFFFF0; // e_lfanew outside the buffer
    Check('DetectExeFilter(bad e_lfanew) = none', DetectExeFilter(@Fake[0], Length(Fake)) = efNone);
    Check('DetectExeFilter(MZ only, 2 bytes) = none', DetectExeFilter(@Fake[0], 2) = efNone);
    SetLength(Rnd, 1024 * 1024);
    RandSeed := 42;
    for i := 0 to High(Rnd) do
      Rnd[i] := Byte(Random(256));
    Check('DetectExeFilter(random) = none', DetectExeFilter(@Rnd[0], Length(Rnd)) = efNone);

    // --- BCJ in place ---
    Work := Copy(Me, 0, Length(Me));
    ExeFilterEncode(@Work[0], Length(Work), efX86);
    Check('x86 filter changes the code', not Same(Work, Me));
    ExeFilterDecode(@Work[0], Length(Work), efX86);
    Check('x86 filter roundtrip byte-identical', Same(Work, Me));
    Work := Copy(Rnd, 0, Length(Rnd));
    ExeFilterEncode(@Work[0], Length(Work), efARM64);
    Check('ARM64 filter changes random data', not Same(Work, Rnd));
    ExeFilterDecode(@Work[0], Length(Work), efARM64);
    Check('ARM64 filter roundtrip byte-identical', Same(Work, Rnd));

    // --- lzx2 = filter + LZMA2 ---
    n := CompressExe(@Me[0], Length(Me), Comp);
    Check('CompressExe(auto) > 0, filter byte x86', (n > 0) and (n = Length(Comp)) and (Comp[4] = 1));
    Check('CompressExe leaves the source untouched', Same(Me, LoadFile(ParamStr(0))));
    CompressLZMA2(@Me[0], Length(Me), Work, False, 9);
    Check('BCJ+LZMA2 smaller than LZMA2 alone', Length(Comp) < Length(Work));
    n := ExtractExe(@Comp[0], Length(Comp), Back);
    Check('ExtractExe roundtrip byte-identical', (n = Length(Me)) and Same(Back, Me));
    for i := Ord(efNone) to Ord(efARM64) do
    begin
      CompressExe(@Rnd[0], 300000, Comp, TExeFilter(i), 5);
      n := ExtractExe(@Comp[0], Length(Comp), Back);
      Check('ExtractExe forced filter ' + IntToStr(i) + ' roundtrip',
        (n = 300000) and CompareMem(@Back[0], @Rnd[0], 300000));
    end;
    CompressExe(@Me[0], Length(Me), Comp);
    Comp[4] := 9;
    n := ExtractExe(@Comp[0], Length(Comp), Back);
    Check('ExtractExe unknown filter -> error, no data', (n < 0) and (Length(Back) = 0));
    CompressExe(@Me[0], Length(Me), Comp);
    n := ExtractExe(@Comp[0], Length(Comp) - 16, Back);
    Check('ExtractExe truncated -> error, no data', (n < 0) and (Length(Back) = 0));
    n := ExtractExe(@Me[0], Length(Me), Back);
    Check('ExtractExe without lzx2 header -> error', (n < 0) and (Length(Back) = 0));

    // --- BCJ2 ---
    Bcj2Roundtrip('own exe', Me);
    Bcj2Roundtrip('random 1 MB', Rnd);
    SetLength(Work, 5); // marker at the very end, no room for an address
    FillChar(Work[0], 5, $E8);
    Bcj2Roundtrip('5 bytes E8', Work);
    SetLength(Work, 1);
    Bcj2Roundtrip('1 byte', Work);

    if (ParamCount > 0) and FileExists(ParamStr(1)) then
      Measure(ParamStr(1));

    if Fails = 0 then
      Writeln('ALL OK')
    else
      Writeln(Fails, ' FAILURES');
    ExitCode := Fails;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      ExitCode := 99;
      Exit;
    end;
  end;
end.
