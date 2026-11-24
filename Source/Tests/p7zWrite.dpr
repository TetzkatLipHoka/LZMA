program p7zWrite;
// Writing 7z archives (SevenZipOut) - the archives are checked by 7z.exe
// ("t", "l -slt", "x") and by our own reader:
//   solid -mx9 like (BCJ2 for the exe), non-solid, level 0 (Copy), forced
//   filter off, password with and without encrypted header, Unicode password,
//   memory/stream items, empty file/dir, archive without streams, empty archive.
// Size check: within 1 % of 7z -mx9 for the same files.
// Optional ParamStr(1) = a file: prints our size vs. 7z -mx9 for it alone.
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
  SevenZipOut in '..\SevenZipOut.pas',
  SevenZipAES in '..\SevenZipAES.pas',
  t7zUtil in 't7zUtil.pas';

function FileSize64( const Name : WideString ) : Int64;
var
  D : TWin32FileAttributeData;
begin
  result := -1;
  if GetFileAttributesExW( PWideChar( Name ), GetFileExInfoStandard, @D ) then
    result := ( Int64( D.nFileSizeHigh ) shl 32 ) or D.nFileSizeLow;
end;

function RunCapture( const Cmd : WideString; out Output : AnsiString ) : Cardinal;
var
  SA : TSecurityAttributes;
  R, W : THandle;
  SI : TStartupInfo;
  PI : TProcessInformation;
  C  : WideString;
  Buf : array [ 0..4095 ] of AnsiChar;
  n  : Cardinal;
begin
  result := Cardinal( -1 );
  Output := '';
  SA.nLength := SizeOf( SA ); SA.bInheritHandle := True; SA.lpSecurityDescriptor := nil;
  if not CreatePipe( R, W, @SA, 0 ) then Exit;
  SetHandleInformation( R, HANDLE_FLAG_INHERIT, 0 );
  FillChar( SI, SizeOf( SI ), 0 );
  SI.cb := SizeOf( SI );
  SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  SI.hStdOutput := W; SI.hStdError := W; SI.hStdInput := 0;
  C := Cmd;
  UniqueString( C );
  if not CreateProcessW( nil, PWideChar( C ), nil, nil, True, CREATE_NO_WINDOW, nil, PWideChar( Work ), SI, PI ) then
    begin
    CloseHandle( R ); CloseHandle( W );
    Exit;
    end;
  CloseHandle( W );
  while ReadFile( R, Buf, SizeOf( Buf ), n, nil ) and ( n > 0 ) do
    Output := Output+Copy( AnsiString( Buf ), 1, n );
  CloseHandle( R );
  WaitForSingleObject( PI.hProcess, INFINITE );
  GetExitCodeProcess( PI.hProcess, result );
  CloseHandle( PI.hThread );
  CloseHandle( PI.hProcess );
end;

function CompareTree( const OutDir : WideString ) : Boolean;
var
  i : Integer;
  A, B : TMemoryStream;
begin
  result := True;
  A := TMemoryStream.Create;
  B := TMemoryStream.Create;
  try
    for i := 0 to High( Names ) do
      begin
      ReadFileW( Src+'\'+Names[ i ], A );
      if not ReadFileW( OutDir+'\'+Names[ i ], B ) or not SameMem( A, B ) then
        begin
        Writeln( '         differs: ', string( Names[ i ] ) );
        result := False;
        end;
      end;
  finally
    B.Free;
    A.Free;
  end;
end;

// write the src tree, check with 7z.exe (t, l -slt, x) and our reader
function WriteAndCheck( const Tag : string; Level : Integer; Solid : Boolean; F : TExeFilter;
  const Pwd : WideString; EncHdr : Boolean; const ExpectMethods : AnsiString = '' ) : Int64;
var
  W   : T7zWriter;
  Arc, OutDir, PSw : WideString;
  n   : Integer;
  O   : AnsiString;
  R   : T7zReader;
  FT, CT, AT : TFileTime;
  H   : THandle;
  Attr : Cardinal;
begin
  result := -1;
  Arc := Work+'\w_'+Tag+'.7z';
  W := T7zWriter.Create;
  try
    W.Level := Level;
    W.Solid := Solid;
    W.Filter := F;
    W.Password := Pwd;
    W.EncryptHeader := EncHdr;
    Check( Tag+': AddDirectory', W.AddDirectory( Src ) );
    n := W.SaveToFile( Arc );
    Check( Tag+': SaveToFile', n = 0 );
    if ( n <> 0 ) then
      begin
      Writeln( '         result ', n );
      Exit;
      end;
  finally
    W.Free;
  end;
  result := FileSize64( Arc );
  if ( Pwd <> '' ) then PSw := ' "-p'+Pwd+'"' else PSw := ' -p-';

  n := RunCapture( '"'+SevenZip+'" t "'+Arc+'"'+PSw, O );
  Check( Tag+': 7z.exe t accepts the archive', ( n = 0 ) and ( Pos( 'Everything is Ok', string( O ) ) > 0 ) );
  if ( n <> 0 ) then Writeln( string( O ) );
  if ( Pwd <> '' ) then
    begin
    n := RunCapture( '"'+SevenZip+'" t "'+Arc+'" -pwrong', O );
    Check( Tag+': 7z.exe t with wrong password fails', n <> 0 );
    end;
  n := RunCapture( '"'+SevenZip+'" l -slt "'+Arc+'"'+PSw, O );
  Check( Tag+': 7z.exe l -slt', n = 0 );
  if ( ExpectMethods <> '' ) then
    begin
    Check( Tag+': methods contain "'+string( ExpectMethods )+'"', Pos( string( ExpectMethods ), string( O ) ) > 0 );
    end;

  OutDir := Work+'\x_'+Tag;
  n := RunCapture( '"'+SevenZip+'" x -y "-o'+OutDir+'" "'+Arc+'"'+PSw, O );
  Check( Tag+': 7z.exe x', n = 0 );
  Check( Tag+': files extracted by 7z.exe identical', CompareTree( OutDir ) );
  H := CreateFileW( PWideChar( OutDir+'\a.txt' ), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0 );
  GetFileTime( H, @CT, @AT, @FT );
  CloseHandle( H );
  Check( Tag+': mtime kept (via 7z.exe)', ( FT.dwLowDateTime = KnownTime.dwLowDateTime ) and ( FT.dwHighDateTime = KnownTime.dwHighDateTime ) );
  Attr := GetFileAttributesW( PWideChar( OutDir+'\sub\deep\random.bin' ) );
  Check( Tag+': read-only attribute kept (via 7z.exe)', ( Attr <> Cardinal( -1 ) ) and ( Attr and FILE_ATTRIBUTE_READONLY <> 0 ) );
  Attr := GetFileAttributesW( PWideChar( OutDir+'\emptydir' ) );
  Check( Tag+': empty dir (via 7z.exe)', ( Attr <> Cardinal( -1 ) ) and ( Attr and FILE_ATTRIBUTE_DIRECTORY <> 0 ) );

  R := T7zReader.Create;
  try
    n := R.OpenFile( Arc, Pwd );
    Check( Tag+': own reader opens', n = 0 );
    if ( n = 0 ) then
      begin
      n := R.ExtractToDir( OutDir+'_own' );
      Check( Tag+': own reader extracts identical', ( n = 0 ) and CompareTree( OutDir+'_own' ) );
      end;
  finally
    R.Free;
  end;
end;

procedure TestSpecial;
var
  W : T7zWriter;
  R : T7zReader;
  M : TMemoryStream;
  Arc : WideString;
  n : Integer;
  O : AnsiString;
  S : AnsiString;
  Got : TMemoryStream;
begin
  // memory + stream items, empty file, nested empty dir, names with '/'
  Arc := Work+'\w_mem.7z';
  W := T7zWriter.Create;
  M := TMemoryStream.Create;
  Got := TMemoryStream.Create;
  R := T7zReader.Create;
  try
    S := 'hello 7z';
    W.AddMemory( PAnsiChar( S ), Length( S ), 'docs/hello.txt' );
    M.WriteBuffer( PAnsiChar( S )^, Length( S ) );
    M.Position := 2;
    W.AddStream( M, 'docs\tail.txt' );
    W.AddMemory( nil, 0, 'empty.bin' );
    W.AddEmptyDir( 'a/b/c' );
    n := W.SaveToFile( Arc );
    Check( 'mem: SaveToFile', n = 0 );
    n := RunCapture( '"'+SevenZip+'" t "'+Arc+'"', O );
    Check( 'mem: 7z.exe t', n = 0 );
    n := R.OpenFile( Arc );
    Check( 'mem: own reader, 4 items', ( n = 0 ) and ( R.Count = 4 ) );
    Got.Clear;
    Check( 'mem: hello.txt content', ( R.Extract( R.IndexOf( 'docs\hello.txt' ), Got ) = 0 ) and ( Got.Size = 8 ) and CompareMem( Got.Memory, PAnsiChar( S ), 8 ) );
    Got.Clear;
    Check( 'mem: tail.txt from stream position', ( R.Extract( R.IndexOf( 'docs\tail.txt' ), Got ) = 0 ) and ( Got.Size = 6 ) );
    Check( 'mem: empty dir a\b\c', ( R.IndexOf( 'a\b\c' ) >= 0 ) and R.Item( R.IndexOf( 'a\b\c' ) ).IsDir );
    Check( 'mem: empty file', ( R.IndexOf( 'empty.bin' ) >= 0 ) and not R.Item( R.IndexOf( 'empty.bin' ) ).IsDir and ( R.Item( R.IndexOf( 'empty.bin' ) ).Size = 0 ) );
    R.Close;

    // only empty entries (no packed streams at all)
    W.Clear;
    W.AddEmptyDir( 'onlydir' );
    W.AddMemory( nil, 0, 'zero.txt' );
    Arc := Work+'\w_nostreams.7z';
    n := W.SaveToFile( Arc );
    Check( 'no streams: SaveToFile', n = 0 );
    n := RunCapture( '"'+SevenZip+'" t "'+Arc+'"', O );
    Check( 'no streams: 7z.exe t', n = 0 );
    Check( 'no streams: own reader', ( R.OpenFile( Arc ) = 0 ) and ( R.Count = 2 ) );
    R.Close;

    // empty archive
    W.Clear;
    Arc := Work+'\w_empty.7z';
    n := W.SaveToFile( Arc );
    Check( 'empty archive: SaveToFile', n = 0 );
    n := RunCapture( '"'+SevenZip+'" t "'+Arc+'"', O );
    Check( 'empty archive: 7z.exe t', n = 0 );
    Check( 'empty archive: own reader, 0 items', ( R.OpenFile( Arc ) = 0 ) and ( R.Count = 0 ) );
    R.Close;

    // to a TMemoryStream, read back from memory
    W.Clear;
    W.AddMemory( PAnsiChar( S ), Length( S ), 'x.txt' );
    M.Clear;
    Check( 'SaveToStream (memory)', W.SaveToStream( M ) = 0 );
    Got.Clear;
    Check( 'read back from memory', ( R.OpenMemory( M.Memory, M.Size ) = 0 ) and ( R.Extract( 0, Got ) = 0 ) and ( Got.Size = 8 ) );
  finally
    R.Free;
    Got.Free;
    M.Free;
    W.Free;
  end;
end;

// BCJ2 + AES: 7z.exe rejected our coder order at random (depends on the random IV,
// 2026-11-24: 4 of 10 / 1 of 10 accepted) - 8 runs with fresh IVs must all pass
procedure TestBcj2AesRepeated;
var
  W : T7zWriter;
  Arc : WideString;
  i, Good : Integer;
  O : AnsiString;
begin
  Good := 0;
  Arc := Work+'\w_bcj2aes.7z';
  for i := 1 to 8 do
    begin
    W := T7zWriter.Create;
    try
      W.AddFile( Src+'\bin\prog.exe' );
      W.Password := 'Secret';
      W.EncryptHeader := Odd( i );
      if ( W.SaveToFile( Arc ) = 0 ) and ( RunCapture( '"'+SevenZip+'" t "'+Arc+'" -pSecret', O ) = 0 ) then
        Inc( Good );
    finally
      W.Free;
    end;
    end;
  Check( 'BCJ2 + AES: 8 of 8 archives accepted by 7z.exe (random IVs)', Good = 8 );
end;

procedure CompareWith7z( const FileName : WideString );
var
  W : T7zWriter;
  Ours, Theirs : WideString;
  O : AnsiString;
begin
  Ours := Work+'\one_ours.7z';
  Theirs := Work+'\one_7z.7z';
  W := T7zWriter.Create;
  try
    W.AddFile( FileName );
    W.SaveToFile( Ours );
  finally
    W.Free;
  end;
  RunCapture( '"'+SevenZip+'" a -t7z -mx9 "'+Theirs+'" "'+FileName+'"', O );
  Writeln( '--- ', string( FileName ), ' (', FileSize64( FileName ), ' bytes)' );
  Writeln( '    SevenZipOut level 9 : ', FileSize64( Ours ) );
  Writeln( '    7z.exe -mx9         : ', FileSize64( Theirs ) );
end;

var
  SzOurs, Sz7z : Int64;
  UPwd : WideString;
  O : AnsiString;

begin
  try
    if not Have7z then
      begin
      Writeln( 'ALL OK' );
      Exit;
      end;
    InitWork( 'p7zWrite' );

    SzOurs := WriteAndCheck( 'solid9', 9, True, efAuto, '', True, 'BCJ2' );
    WriteAndCheck( 'nonsolid5', 5, False, efAuto, '', True, 'LZMA2' );
    WriteAndCheck( 'copy', 0, True, efAuto, '', True, 'Copy' );
    WriteAndCheck( 'nofilter', 9, True, efNone, '', True );
    WriteAndCheck( 'arm64', 6, True, efARM64, '', True, 'ARM64' );
    WriteAndCheck( 'pwdhdr', 9, True, efAuto, 'Secret', True, '7zAES' );
    WriteAndCheck( 'pwd', 7, False, efAuto, 'Secret', False, '7zAES' );
    UPwd := 'K';
    UPwd := UPwd+WideChar( $00F6 );
    UPwd := UPwd+WideChar( $9375 );
    WriteAndCheck( 'pwduni', 5, True, efAuto, UPwd, True );

    // size vs. 7z -mx9 for the same tree
    RunCapture( '"'+SevenZip+'" a -t7z -mx9 -r "'+Work+'\ref.7z" "'+Src+'\*"', O );
    Sz7z := FileSize64( Work+'\ref.7z' );
    Writeln( '         size: ours ', SzOurs, ', 7z -mx9 ', Sz7z );
    Check( 'size within 1 % of 7z -mx9', ( SzOurs > 0 ) and ( SzOurs <= Sz7z+Sz7z div 100 ) );

    TestSpecial;
    TestBcj2AesRepeated;

    if ( ParamCount > 0 ) and FileExists( ParamStr( 1 ) ) then
      CompareWith7z( ParamStr( 1 ) );

    if Fails = 0 then DelTree( Work );
    if Fails = 0 then
      Writeln( 'ALL OK' )
    else
      Writeln( Fails, ' FAILURES' );
    ExitCode := Fails;
  except
    on E : Exception do
      begin
      Writeln( 'EXCEPTION: ', E.ClassName, ': ', E.Message, ' at $', IntToHex( Cardinal( ExceptAddr ), 8 ) );
      ExitCode := 99;
      end;
  end;
end.
