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
  P: Pointer;
  Big: TByteDynArray;

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

    // --- 4) high compression ratio (2026-11-24): ExtractLZMA/ExtractLZMA2 returned the data silently truncated to
    // 4 x compressed size (real scan file 14.7 MB at ratio 9.7:1 came back with 6.1 MB). 20 MB pattern, both
    // overloads, both formats, level parameter; a truncated stream must fail instead of returning partial data.
    SetLength(Big, 20 * 1024 * 1024);
    for i := 0 to High(Big) do
      Big[i] := Byte(i mod 7);
    n := CompressLZMA(@Big[0], Length(Big), Comp, True{Header}, 1{Level});
    Check('LZMA level 1, ratio > 4:1', (n > 0) and (n * 4 < Length(Big)));
    n := ExtractLZMA(@Comp[0], Length(Comp), Back);
    Check('ExtractLZMA high ratio complete (array)',
      (n = Length(Big)) and (Length(Back) = Length(Big)) and CompareMem(@Back[0], @Big[0], Length(Big)));
    P := nil;
    n := ExtractLZMA(@Comp[0], Length(Comp), P);
    Check('ExtractLZMA high ratio complete (pointer)', (n = Length(Big)) and CompareMem(P, @Big[0], Length(Big)));
    FreeMem(P);
    n := ExtractLZMA(@Comp[0], Length(Comp) - 16, Back);
    Check('ExtractLZMA truncated stream -> error, no data', Length(Back) = 0);
    n := CompressLZMA2(@Big[0], Length(Big), Comp, True{Header}, 1{Level});
    Check('LZMA2 level 1, ratio > 4:1', (n > 0) and (n * 4 < Length(Big)));
    n := ExtractLZMA2(@Comp[0], Length(Comp), Back);
    Check('ExtractLZMA2 high ratio complete (array)',
      (n = Length(Big)) and (Length(Back) = Length(Big)) and CompareMem(@Back[0], @Big[0], Length(Big)));
    P := nil;
    n := ExtractLZMA2(@Comp[0], Length(Comp), P);
    Check('ExtractLZMA2 high ratio complete (pointer)', (n = Length(Big)) and CompareMem(P, @Big[0], Length(Big)));
    FreeMem(P);
    n := ExtractLZMA2(@Comp[0], Length(Comp) - 16, Back);
    Check('ExtractLZMA2 truncated stream -> error, no data', Length(Back) = 0);
    SetLength(Big, 0);

    // --- 4b) stream API, same cases (2026-11-24): the stream decoders stopped at the end of the input even while
    // the decoder still had output pending, and reported truncated or corrupt streams as success (partial size).
    SetLength(Big, 20 * 1024 * 1024);
    for i := 0 to High(Big) do
      Big[i] := Byte(i mod 7);
    InS := TMemoryStream.Create;
    OutS := TMemoryStream.Create;
    BackS := TMemoryStream.Create;
    try
      InS.WriteBuffer(Big[0], Length(Big));
      InS.Position := 0;
      CompressStreamLZMA(InS, OutS, True);
      OutS.Position := 0;
      n := ExtractStreamLZMA(OutS, BackS);
      Check('ExtractStreamLZMA high ratio complete',
        (n = Length(Big)) and (BackS.Size = Length(Big)) and CompareMem(BackS.Memory, @Big[0], Length(Big)));
      OutS.Size := OutS.Size - 16;
      OutS.Position := 0;
      BackS.Clear;
      n := ExtractStreamLZMA(OutS, BackS);
      Check('ExtractStreamLZMA truncated stream -> error', n < 0);
      InS.Position := 0;
      OutS.Clear;
      CompressStreamLZMA2(InS, OutS, True);
      OutS.Position := 0;
      BackS.Clear;
      n := ExtractStreamLZMA2(OutS, BackS);
      Check('ExtractStreamLZMA2 high ratio complete',
        (n = Length(Big)) and (BackS.Size = Length(Big)) and CompareMem(BackS.Memory, @Big[0], Length(Big)));
      OutS.Size := OutS.Size - 16;
      OutS.Position := 0;
      BackS.Clear;
      n := ExtractStreamLZMA2(OutS, BackS);
      Check('ExtractStreamLZMA2 truncated stream -> error', n < 0);
      // in place (InStream = OutStream): on error the input must stay untouched
      OutS.Position := 0;
      i := OutS.Size;
      n := ExtractStreamLZMA2(TStream(OutS), TStream(OutS));
      Check('ExtractStreamLZMA2 in place, error -> input unchanged', (n < 0) and (OutS.Size = i));
    finally
      BackS.Free;
      OutS.Free;
      InS.Free;
    end;
    SetLength(Big, 0);

    // --- 4c) buffer API: errors are negative (2026-11-24; before: positive SZ_ERROR_* like a 1..17 byte result)
    SetLength(Comp, 64);
    FillChar(Comp[0], 64, $FF);
    PWord(@Comp[0])^ := 5; // LZMA props length ok, props invalid ($FF)
    n := ExtractLZMA(@Comp[0], Length(Comp), Back);
    Check('ExtractLZMA invalid props -> negative', (n < 0) and (Length(Back) = 0));
    Comp[0] := $FF; // LZMA2 property byte > 40 is invalid
    n := ExtractLZMA2(@Comp[0], Length(Comp), Back);
    Check('ExtractLZMA2 invalid prop byte -> negative', (n < 0) and (Length(Back) = 0));
    n := CompressLZMA(@Data[0], Length(Data), Comp, True, 9);
    Comp[High(Comp) div 2] := Comp[High(Comp) div 2] xor $55;
    n := ExtractLZMA(@Comp[0], Length(Comp), Back);
    Check('ExtractLZMA corrupt data -> negative or detected', (n < 0) or not ((n = Length(Data)) and CompareMem(@Back[0], @Data[0], Length(Data))));

    // --- 5) incompressible data (2026-11-24): CompressLZMA2 used an output buffer of exactly the input size and
    // failed on random data; the pointer overload additionally allocated Offset bytes too little.
    SetLength(Big, 300000);
    RandSeed := 7;
    for i := 0 to High(Big) do
      Big[i] := Byte(Random(256));
    n := CompressLZMA2(@Big[0], Length(Big), Comp, True{Header}, 5);
    Check('CompressLZMA2 random data (array) succeeds', (n > Length(Big)) and (n = Length(Comp)));
    n := ExtractLZMA2(@Comp[0], Length(Comp), Back);
    Check('LZMA2 random data roundtrip (array)', (n = Length(Big)) and CompareMem(@Back[0], @Big[0], Length(Big)));
    P := nil;
    n := CompressLZMA2(@Big[0], Length(Big), P, True{Header}, 5);
    Check('CompressLZMA2 random data (pointer) succeeds', n > Length(Big));
    if n > 0 then
    begin
      SetLength(Comp, n);
      Move(P^, Comp[0], n);
    end;
    FreeMem(P);
    n := ExtractLZMA2(@Comp[0], Length(Comp), Back);
    Check('LZMA2 random data roundtrip (pointer)', (n = Length(Big)) and CompareMem(@Back[0], @Big[0], Length(Big)));
    n := CompressLZMA(@Big[0], Length(Big), Comp, True{Header}, 5);
    Check('CompressLZMA random data succeeds', (n > Length(Big)) and (n = Length(Comp)));
    n := ExtractLZMA(@Comp[0], Length(Comp), Back);
    Check('LZMA random data roundtrip', (n = Length(Big)) and CompareMem(@Back[0], @Big[0], Length(Big)));
    SetLength(Big, 0);

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
