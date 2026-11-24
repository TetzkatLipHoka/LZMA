program p7zRead;
// Reading 7z archives (SevenZipIn: 7zArcIn.c + Pascal folder decoder).
// The archives are created on the fly by 7z.exe from generated test data:
// LZMA2 -mx9 solid (BCJ2 for the exe), LZMA non-solid, Copy, Delta+LZMA,
// ARM64+LZMA2, BCJ+LZMA2, a packed header, Unicode names, an empty file, an
// empty directory, mtime and read-only attribute. Every file is compared byte
// by byte; corrupt and truncated archives must fail cleanly.
// Without 7z.exe the archive tests are skipped (exit code 0, SKIP lines).
{$APPTYPE CONSOLE}

uses
  Windows, SysUtils, Classes,
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
  LZMA2 in '..\LZMA2.pas',
  Bra in '..\Bra.pas',
  Bcj2 in '..\Bcj2.pas',
  LZMAExe in '..\LZMAExe.pas',
  SevenZipIn in '..\SevenZipIn.pas',
  t7zUtil in 't7zUtil.pas';

procedure TestArchive( const Tag, Switches : WideString; ExpectMethodOk : Boolean = True );
var
  Arc : WideString;
  R   : T7zReader;
  i, n, Idx : Integer;
  Orig, Got : TMemoryStream;
  It  : T7zItem;
  Ok  : Boolean;
  Out_ : WideString;
  Attr : Cardinal;
  H : THandle;
  FT, CT, AT : TFileTime;
  FS : TFileStream;
begin
  Arc := Work+'\'+Tag+'.7z';
  DeleteFileW( PWideChar( Arc ) );
  if ( RunWait( '"'+SevenZip+'" a -t7z -r "'+Arc+'" * '+Switches, Src ) <> 0 ) then
    begin
    Check( Tag+': 7z.exe created the archive', False );
    Exit;
    end;
  R := T7zReader.Create;
  Orig := TMemoryStream.Create;
  Got := TMemoryStream.Create;
  try
    n := R.OpenFile( Arc );
    Check( Tag+': open', n = 0 );
    if ( n <> 0 ) then
      begin
      Writeln( '         open result ', n );
      Exit;
      end;
    Check( Tag+': 8 items (6 files, emptydir, plus dirs)', R.Count >= 8 );
    Ok := True;
    for i := 0 to High( Names ) do
      begin
      Idx := R.IndexOf( Names[ i ] );
      if ( Idx < 0 ) then
        begin
        Writeln( '         missing: ', string( Names[ i ] ) );
        Ok := False;
        Continue;
        end;
      ReadFileW( Src+'\'+Names[ i ], Orig );
      Got.Clear;
      n := R.Extract( Idx, Got );
      if not ExpectMethodOk then
        begin
        if ( n = 0 ) and ( Orig.Size > 0 ) then Ok := False;
        Continue;
        end;
      if ( n <> 0 ) or not SameMem( Orig, Got ) then
        begin
        Writeln( '         ', string( Names[ i ] ), ': result ', n, ', size ', Got.Size, '/', Orig.Size );
        Ok := False;
        end;
      end;
    if not ExpectMethodOk then
      begin
      Check( Tag+': unsupported method -> error, no data', Ok );
      Exit;
      end;
    Check( Tag+': all files byte-identical', Ok );
    Idx := R.IndexOf( 'emptydir' );
    Check( Tag+': empty directory listed as dir', ( Idx >= 0 ) and R.Item( Idx ).IsDir );
    It := R.Item( R.IndexOf( 'a.txt' ) );
    Check( Tag+': mtime of a.txt', It.HasMTime and ( It.MTime.dwLowDateTime = KnownTime.dwLowDateTime ) and
      ( It.MTime.dwHighDateTime = KnownTime.dwHighDateTime ) );
    It := R.Item( R.IndexOf( 'sub\deep\random.bin' ) );
    Check( Tag+': read-only attribute, CRC, size', It.HasAttrib and ( It.Attrib and FILE_ATTRIBUTE_READONLY <> 0 ) and
      It.HasCRC and ( It.Size = 300000 ) );

    // extract everything to a directory and compare from disk
    Out_ := Work+'\out_'+Tag;
    n := R.ExtractToDir( Out_ );
    Check( Tag+': ExtractToDir', n = 0 );
    Ok := True;
    for i := 0 to High( Names ) do
      begin
      ReadFileW( Src+'\'+Names[ i ], Orig );
      if not ReadFileW( Out_+'\'+Names[ i ], Got ) or not SameMem( Orig, Got ) then
        Ok := False;
      end;
    Check( Tag+': extracted files identical on disk', Ok );
    Attr := GetFileAttributesW( PWideChar( Out_+'\sub\deep\random.bin' ) );
    Check( Tag+': read-only restored', ( Attr <> Cardinal( -1 ) ) and ( Attr and FILE_ATTRIBUTE_READONLY <> 0 ) );
    H := CreateFileW( PWideChar( Out_+'\a.txt' ), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0 );
    GetFileTime( H, @CT, @AT, @FT );
    CloseHandle( H );
    Check( Tag+': mtime restored', ( FT.dwLowDateTime = KnownTime.dwLowDateTime ) and ( FT.dwHighDateTime = KnownTime.dwHighDateTime ) );
    Attr := GetFileAttributesW( PWideChar( Out_+'\emptydir' ) );
    Check( Tag+': empty directory created', ( Attr <> Cardinal( -1 ) ) and ( Attr and FILE_ATTRIBUTE_DIRECTORY <> 0 ) );
    R.Close;

    // same archive from memory
    FS := TFileStream.Create( string( Arc ), fmOpenRead or fmShareDenyNone );
    try
      Orig.Clear;
      Orig.CopyFrom( FS, 0 );
    finally
      FS.Free;
    end;
    n := R.OpenMemory( Orig.Memory, Orig.Size );
    Got.Clear;
    if ( n = 0 ) then
      n := R.Extract( R.IndexOf( 'bin\prog.exe' ), Got );
    ReadFileW( Src+'\bin\prog.exe', Orig );
    Check( Tag+': open from memory + extract', ( n = 0 ) and SameMem( Orig, Got ) );
  finally
    Got.Free;
    Orig.Free;
    R.Free;
  end;
end;

procedure TestBroken;
var
  Arc : WideString;
  M   : TMemoryStream;
  R   : T7zReader;
  n, i, Bad : Integer;
  Got : TMemoryStream;
  FS  : TFileStream;
begin
  Arc := Work+'\lzma2.7z';
  M := TMemoryStream.Create;
  Got := TMemoryStream.Create;
  R := T7zReader.Create;
  try
    FS := TFileStream.Create( string( Arc ), fmOpenRead or fmShareDenyNone );
    try
      M.CopyFrom( FS, 0 );
    finally
      FS.Free;
    end;
    // flip bytes in the packed data (behind the 32-byte start header)
    for i := 100 to 140 do
      PByteArray( M.Memory )^[ i ] := PByteArray( M.Memory )^[ i ] xor $A5;
    n := R.OpenMemory( M.Memory, M.Size );
    Check( 'corrupt data: archive still opens (header intact)', n = 0 );
    Bad := 0;
    for i := 0 to R.Count-1 do
      begin
      Got.Clear;
      if ( R.Item( i ).Size > 0 ) and ( R.Extract( i, Got ) <> 0 ) then
        Inc( Bad );
      end;
    Check( 'corrupt data: extraction fails (no silent garbage)', Bad > 0 );
    R.Close;

    FS := TFileStream.Create( string( Arc ), fmOpenRead or fmShareDenyNone );
    try
      M.Clear;
      M.CopyFrom( FS, 0 );
    finally
      FS.Free;
    end;
    n := R.OpenMemory( M.Memory, M.Size-20 );
    Check( 'truncated archive: open fails with negative code', n < 0 );
    n := R.OpenMemory( M.Memory, 10 );
    Check( '10 bytes: open fails', n < 0 );
    PAnsiChar( M.Memory )[ 0 ] := 'X';
    n := R.OpenMemory( M.Memory, M.Size );
    Check( 'no signature: open fails', n < 0 );
    Check( 'extract without open archive -> E7Z_NOTOPEN', R.Extract( 0, Got ) = E7Z_NOTOPEN );
  finally
    R.Free;
    Got.Free;
    M.Free;
  end;
end;

begin
  try
    if not Have7z then
      begin
      Writeln( 'ALL OK' );
      Exit;
      end;
    InitWork( 'p7zRead' );

    TestArchive( 'lzma2', '-mx9' );                                    // LZMA2 solid + BCJ2 for the exe
    TestArchive( 'lzma', '-m0=LZMA -ms=off -mf=off' );                 // non-solid, one folder per file
    TestArchive( 'copy', '-m0=Copy' );
    TestArchive( 'delta', '-m0=Delta:2 -m1=LZMA -ms=on -mf=off' );
    TestArchive( 'arm64', '-m0=ARM64 -m1=LZMA2 -mf=off' );
    TestArchive( 'bcj', '-m0=BCJ -m1=LZMA2 -mf=off -mhc=off' );        // header not compressed
    TestArchive( 'ppmd', '-m0=PPMd -mf=off', False );                  // not supported -> clean error
    TestBroken;

    DelTree( Work );
    if Fails = 0 then
      Writeln( 'ALL OK' )
    else
      Writeln( Fails, ' FAILURES' );
    ExitCode := Fails;
  except
    on E : Exception do
      begin
      Writeln( 'EXCEPTION: ', E.ClassName, ': ', E.Message );
      ExitCode := 99;
      end;
  end;
end.
