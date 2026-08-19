program pRoundtrip;
// Functional roundtrip for the LZMA include (SDK 26.02):
// 1) buffer API  CompressLZMA/ExtractLZMA        (LzmaEnc/LzFind/CpuArch + LzmaDec)
// 2) stream API  CompressStreamLZMA/Extract      (LZMAStream)
// 3) stream API  CompressStreamLZMA2/Extract     (Lzma2Enc/MtCoder/Threads + Lzma2Dec/MtDec)
// Step 3 is the regression test for finding LZMA1 (struct layout drift:
// Win64 crashed with heap corruption, Win32 returned wrong sizes).
{$APPTYPE CONSOLE}

{$IFNDEF Win64} // like LZMA.inc
  {$DEFINE UNDERSCORE}
{$ENDIF}

uses
  SysUtils, Classes, Types,
  LzFind in '..\LzFind.pas',
  LzFindMt in '..\LzFindMt.pas',
  LZMA in '..\LZMA.pas',
  LZMA2 in '..\LZMA2.pas',
  Lzma2Dec in '..\Lzma2Dec.pas',
  Lzma2Enc in '..\Lzma2Enc.pas',
  LZMA2Stream in '..\LZMA2Stream.pas',
  LzmaDec in '..\LzmaDec.pas',
  LzmaEnc in '..\LzmaEnc.pas',
  LZMAStream in '..\LZMAStream.pas',
  LzmaTypes in '..\LzmaTypes.pas',
  MtCoder in '..\MtCoder.pas',
  MtDec in '..\MtDec.pas',
  Threads in '..\Threads.pas';

var
  Data, Back: TByteDynArray;
  Comp: TByteDynArray;
  i: Integer;
  n: Int64;
  Fails: Integer = 0;
  InS, OutS, BackS: TMemoryStream;
  NrmProps: TCLzma2EncProps;

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

begin
  try
    // --- 0) __aulldiv regression (finding LZMA3): the UInt64 division inside
    // Lzma2EncProps_Normalize (numBlocks = reduceSize / blockSize) compiles to
    // the clang helper __aulldiv on Win32, which LzmaTypes.pas must provide
    // with the MSVC convention (all 4 dwords on the stack, ret 16). The
    // original jmp-thunk to System.@_lludiv shifted the stack by 8 bytes -
    // and this path was never executed by the other roundtrip tests.
    {$IFDEF UNDERSCORE}_Lzma2EncProps_Init{$ELSE}Lzma2EncProps_Init{$ENDIF}( NrmProps );
    NrmProps.blockSize := 1 shl 20;                       // 1 MB, fixed
    NrmProps.numBlockThreads := 16;                       // t2 > numBlocks
    NrmProps.lzmaProps.reduceSize := Int64(11) * (1 shl 20); // 11 blocks exactly
    {$IFDEF UNDERSCORE}_Lzma2EncProps_Normalize{$ELSE}Lzma2EncProps_Normalize{$ENDIF}( NrmProps );
    Check('Normalize UInt64 division (__aulldiv) = 11 blocks',
      NrmProps.numBlockThreads_Reduced = 11);

    // test data: 1 MB, half compressible (pattern), half pseudo-random
    SetLength(Data, 1024 * 1024);
    for i := 0 to High(Data) div 2 do
      Data[i] := Byte(i div 251);
    RandSeed := 42;
    for i := (High(Data) div 2) + 1 to High(Data) do
      Data[i] := Byte(Random(256));

    // --- 1) buffer API: CompressLZMA / ExtractLZMA ---
    n := CompressLZMA(@Data[0], Length(Data), Comp, True{Header});
    Check('CompressLZMA > 0', n > 0);
    Check('CompressLZMA compresses (< source)', (n > 0) and (n < Length(Data)));
    if n > 0 then
    begin
      SetLength(Comp, n);
      n := ExtractLZMA(@Comp[0], Length(Comp), Back);
      Check('ExtractLZMA = source size', n = Length(Data));
      Check('LZMA roundtrip byte-identical',
        (n = Length(Data)) and CompareMem(@Data[0], @Back[0], Length(Data)));
    end;

    // --- 2) stream API LZMA ---
    InS := TMemoryStream.Create;
    OutS := TMemoryStream.Create;
    BackS := TMemoryStream.Create;
    try
      InS.WriteBuffer(Data[0], Length(Data));
      InS.Position := 0;
      n := CompressStreamLZMA(InS, OutS, True{Header});
      Check('CompressStreamLZMA > 0', n > 0);
      OutS.Position := 0;
      n := ExtractStreamLZMA(OutS, BackS);
      Check('LZMAStream roundtrip byte-identical',
        (n = Length(Data)) and CompareMem(@Data[0], BackS.Memory, Length(Data)));
    finally
      BackS.Free;
      OutS.Free;
      InS.Free;
    end;

    // --- 3) stream API LZMA2 (multithreaded encoder; LZMA1 regression test) ---
    InS := TMemoryStream.Create;
    OutS := TMemoryStream.Create;
    BackS := TMemoryStream.Create;
    try
      InS.WriteBuffer(Data[0], Length(Data));
      InS.Position := 0;
      n := CompressStreamLZMA2(InS, OutS, True{Header});
      Check('CompressStreamLZMA2 > 0', n > 0);
      OutS.Position := 0;
      n := ExtractStreamLZMA2(OutS, BackS);
      Check('ExtractStreamLZMA2 = source size', n = Length(Data));
      Check('LZMA2 roundtrip byte-identical',
        (n = Length(Data)) and CompareMem(@Data[0], BackS.Memory, Length(Data)));
    finally
      BackS.Free;
      OutS.Free;
      InS.Free;
    end;

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
    end;
  end;
end.
