unit t7zUtil;
// Shared helpers of the 7z tests (p7zRead, p7zAes, p7zWrite): test data, 7z.exe, files.

interface

uses
  Windows, SysUtils, Classes;

var
  Fails : Integer = 0;
  SevenZip : WideString = 'C:\Program Files\7-Zip\7z.exe';
  Work, Src : WideString;
  Names : array of WideString; // relative names of the test files
  Uni   : WideString;
  KnownTime : TFileTime;

procedure Check( const aName : string; Cond : Boolean );
function RunWait( const Cmd, Dir : WideString ) : Cardinal;
procedure WriteFileW( const Name : WideString; const Data; Len : Integer );
function ReadFileW( const Name : WideString; var Data : TMemoryStream ) : Boolean;
function SameMem( A, B : TMemoryStream ) : Boolean;
procedure MakeSource;
procedure DelTree( const Dir : WideString );
function Have7z : Boolean;
procedure InitWork( const Tag : string );

implementation

procedure Check( const aName : string; Cond : Boolean );
begin
  if Cond then
    Writeln( '  [ok]   ', aName )
  else
    begin
    Writeln( '  [FAIL] ', aName );
    Inc( Fails );
    end;
end;

function RunWait( const Cmd, Dir : WideString ) : Cardinal;
var
  SI : TStartupInfo; // same layout as STARTUPINFOW (D7 has no TStartupInfoW)
  PI : TProcessInformation;
  C  : WideString;
begin
  result := Cardinal( -1 );
  FillChar( SI, SizeOf( SI ), 0 );
  SI.cb := SizeOf( SI );
  SI.dwFlags := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  C := Cmd;
  UniqueString( C );
  if not CreateProcessW( nil, PWideChar( C ), nil, nil, False, CREATE_NO_WINDOW, nil, PWideChar( Dir ), SI, PI ) then
    Exit;
  WaitForSingleObject( PI.hProcess, INFINITE );
  GetExitCodeProcess( PI.hProcess, result );
  CloseHandle( PI.hThread );
  CloseHandle( PI.hProcess );
end;

procedure WriteFileW( const Name : WideString; const Data; Len : Integer );
var
  H : THandle;
  W : Cardinal;
begin
  H := CreateFileW( PWideChar( Name ), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0 );
  if ( H = INVALID_HANDLE_VALUE ) then
    raise Exception.Create( 'cannot create test file '+IntToStr( Length( Name ) )+' '+string( Name )+' err '+IntToStr( GetLastError ) );
  if ( Len > 0 ) then
    WriteFile( H, Data, Len, W, nil );
  CloseHandle( H );
end;

function ReadFileW( const Name : WideString; var Data : TMemoryStream ) : Boolean;
var
  H : THandle;
  Sz, R : Cardinal;
begin
  Data.Clear;
  H := CreateFileW( PWideChar( Name ), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0 );
  result := H <> INVALID_HANDLE_VALUE;
  if not result then
    Exit;
  Sz := GetFileSize( H, nil );
  Data.Size := Sz;
  if ( Sz > 0 ) then
    ReadFile( H, Data.Memory^, Sz, R, nil );
  CloseHandle( H );
end;

function SameMem( A, B : TMemoryStream ) : Boolean;
begin
  result := ( A.Size = B.Size ) and ( ( A.Size = 0 ) or CompareMem( A.Memory, B.Memory, A.Size ) );
end;


procedure MakeSource;
var
  Buf : array of Byte;
  i   : Integer;
  Me  : TMemoryStream;
  H   : THandle;
  ST  : TSystemTime;
begin
  CreateDirectoryW( PWideChar( Src ), nil );
  CreateDirectoryW( PWideChar( Src+'\bin' ), nil );
  CreateDirectoryW( PWideChar( Src+'\sub' ), nil );
  CreateDirectoryW( PWideChar( Src+'\sub\deep' ), nil );
  CreateDirectoryW( PWideChar( Src+'\emptydir' ), nil );

  SetLength( Buf, 200000 );
  for i := 0 to High( Buf ) do
    Buf[ i ] := Byte( Ord( 'a' )+( ( i * 7 ) mod 26 ) );
  WriteFileW( Src+'\a.txt', Buf[ 0 ], Length( Buf ) );
  RandSeed := 3;
  SetLength( Buf, 300000 );
  for i := 0 to High( Buf ) do
    Buf[ i ] := Byte( Random( 256 ) );
  WriteFileW( Src+'\sub\deep\random.bin', Buf[ 0 ], Length( Buf ) );
  WriteFileW( Src+'\empty.txt', Buf[ 0 ], 0 );
  // 16-bit samples for Delta
  SetLength( Buf, 100000 );
  for i := 0 to High( Buf ) do
    Buf[ i ] := Byte( ( i div 2 ) * 3 + ( i and 1 ) * 17 );
  WriteFileW( Src+'\sub\wave.raw', Buf[ 0 ], Length( Buf ) );
  Me := TMemoryStream.Create;
  try
    Me.LoadFromFile( ParamStr( 0 ) );
    WriteFileW( Src+'\bin\prog.exe', Me.Memory^, Me.Size );
  finally
    Me.Free;
  end;
  // Unicode name: "Gruesse_" + u-umlaut + "_" + CJK "name" + ".txt"
  // D7: build it char by char - a mixed literal expression is evaluated as AnsiString there
  Uni := 'Gr';
  Uni := Uni+WideChar( $00FC );
  Uni := Uni+'sse_';
  Uni := Uni+WideChar( $540D );
  Uni := Uni+WideChar( $524D );
  Uni := Uni+'.txt';
  WriteFileW( Src+'\'+Uni, PAnsiChar( 'unicode' )^, 7 );

  // known mtime on a.txt, read-only on random.bin
  FillChar( ST, SizeOf( ST ), 0 );
  ST.wYear := 2021; ST.wMonth := 3; ST.wDay := 4; ST.wHour := 5; ST.wMinute := 6; ST.wSecond := 7;
  SystemTimeToFileTime( ST, KnownTime );
  H := CreateFileW( PWideChar( Src+'\a.txt' ), $100 {FILE_WRITE_ATTRIBUTES}, 0, nil, OPEN_EXISTING, 0, 0 );
  SetFileTime( H, nil, nil, @KnownTime );
  CloseHandle( H );
  SetFileAttributesW( PWideChar( Src+'\sub\deep\random.bin' ), FILE_ATTRIBUTE_READONLY );

  SetLength( Names, 6 );
  Names[ 0 ] := 'a.txt';
  Names[ 1 ] := 'sub\deep\random.bin';
  Names[ 2 ] := 'empty.txt';
  Names[ 3 ] := 'sub\wave.raw';
  Names[ 4 ] := 'bin\prog.exe';
  Names[ 5 ] := Uni;
end;

procedure DelTree( const Dir : WideString );
var
  F : TWin32FindDataW;
  H : THandle;
  N : WideString;
begin
  H := FindFirstFileW( PWideChar( Dir+'\*' ), F );
  if ( H <> INVALID_HANDLE_VALUE ) then
    begin
    repeat
      N := F.cFileName;
      if ( N <> '.' ) and ( N <> '..' ) then
        begin
        SetFileAttributesW( PWideChar( Dir+'\'+N ), FILE_ATTRIBUTE_NORMAL );
        if ( F.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY <> 0 ) then
          DelTree( Dir+'\'+N )
        else
          DeleteFileW( PWideChar( Dir+'\'+N ) );
        end;
    until not FindNextFileW( H, F );
    Windows.FindClose( H );
    end;
  RemoveDirectoryW( PWideChar( Dir ) );
end;

function Have7z : Boolean;
begin
  result := GetFileAttributesW( PWideChar( SevenZip ) ) <> Cardinal( -1 );
  if not result then
    Writeln( '  [SKIP] 7z.exe not found: ', string( SevenZip ) );
end;

procedure InitWork( const Tag : string );
begin
  Work := GetEnvironmentVariable( 'TEMP' )+'\'+Tag+'_'+IntToStr( GetCurrentProcessId );
  Src := Work+'\src';
  CreateDirectoryW( PWideChar( Work ), nil );
  MakeSource;
end;

end.
