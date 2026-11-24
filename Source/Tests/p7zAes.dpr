program p7zAes;
// 7zAES: encrypted 7z archives created by 7z.exe (-p, -mhe=on), read with
// SevenZipIn + SevenZipAES (Ehrhardt AES/SHA-256, built from source with
// {$R+}{$Q+} by build_run.ps1). Covers the 8-coder folder BCJ2 + LZMA2 +
// 2x LZMA + 4x AES that 7-Zip writes for an exe, an encrypted header,
// non-solid archives, a Unicode password, and wrong/missing passwords
// (clean E7Z_PASSWORD, no data, no exception).
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
  SevenZipAES in '..\SevenZipAES.pas',
  t7zUtil in 't7zUtil.pas';

function AllIdentical( R : T7zReader; out Bad : string ) : Boolean;
var
  i, Idx, n : Integer;
  Orig, Got : TMemoryStream;
begin
  result := True;
  Bad := '';
  Orig := TMemoryStream.Create;
  Got := TMemoryStream.Create;
  try
    for i := 0 to High( Names ) do
      begin
      Idx := R.IndexOf( Names[ i ] );
      ReadFileW( Src+'\'+Names[ i ], Orig );
      Got.Clear;
      if ( Idx < 0 ) then
        n := -1
      else
        n := R.Extract( Idx, Got );
      if ( n <> 0 ) or not SameMem( Orig, Got ) then
        begin
        result := False;
        Bad := Bad+' '+string( Names[ i ] )+'='+IntToStr( n );
        end;
      end;
  finally
    Got.Free;
    Orig.Free;
  end;
end;

procedure TestEncrypted( const Tag, Switches : WideString; const Pwd : WideString; HeaderEncrypted : Boolean );
var
  Arc : WideString;
  R   : T7zReader;
  n   : Integer;
  Got : TMemoryStream;
  Bad : string;
  T0  : Cardinal;
begin
  Arc := Work+'\'+Tag+'.7z';
  if ( RunWait( '"'+SevenZip+'" a -t7z -r "'+Arc+'" * '+Switches+' "-p'+Pwd+'"', Src ) <> 0 ) then
    begin
    Check( Tag+': 7z.exe created the archive', False );
    Exit;
    end;
  R := T7zReader.Create;
  Got := TMemoryStream.Create;
  try
    // no password
    n := R.OpenFile( Arc );
    if HeaderEncrypted then
      Check( Tag+': no password -> open fails with E7Z_PASSWORD', n = E7Z_PASSWORD )
    else
      begin
      Check( Tag+': no password -> list works', ( n = 0 ) and ( R.IndexOf( 'a.txt' ) >= 0 ) );
      n := R.Extract( R.IndexOf( 'a.txt' ), Got );
      Check( Tag+': no password -> extract E7Z_PASSWORD, no data', ( n = E7Z_PASSWORD ) and ( Got.Size = 0 ) );
      end;
    R.Close;

    // wrong password
    n := R.OpenFile( Arc, 'wrong' );
    if HeaderEncrypted then
      Check( Tag+': wrong password -> open fails with E7Z_PASSWORD', n = E7Z_PASSWORD )
    else
      begin
      Got.Clear;
      n := R.Extract( R.IndexOf( 'bin\prog.exe' ), Got );
      Check( Tag+': wrong password -> extract E7Z_PASSWORD, no data', ( n = E7Z_PASSWORD ) and ( Got.Size = 0 ) );
      end;
    R.Close;

    // right password
    T0 := GetTickCount;
    n := R.OpenFile( Arc, Pwd );
    Check( Tag+': right password -> open', n = 0 );
    if ( n = 0 ) then
      begin
      Check( Tag+': all files byte-identical', AllIdentical( R, Bad ) );
      if ( Bad <> '' ) then
        Writeln( '         failed:', Bad );
      end;
    Writeln( '         (', GetTickCount-T0, ' ms incl. key derivation)' );
  finally
    Got.Free;
    R.Free;
  end;
end;

procedure HexTo( const S : AnsiString; var Dest; Len : Integer );
var
  i : Integer;
begin
  for i := 0 to Len-1 do
    PByteArray( @Dest )^[ i ] := StrToInt( '$'+string( Copy( S, i*2+1, 2 ) ) );
end;

var
  IV : T7zAesIV;
  Blk, Expect : array [ 0..31 ] of Byte;
  UPwd : WideString;
  Key1, Key2 : T7zAesKey;
  Salt : array [ 0..3 ] of Byte;

begin
  try
    // key derivation: deterministic, password-dependent, $3F = plain copy
    if not Sz7zAesDeriveKey( nil, 0, 'abc', 3, 10, Key1 ) then
      Check( 'derive key', False );
    Sz7zAesDeriveKey( nil, 0, 'abc', 3, 10, Key2 );
    Check( 'key derivation deterministic', CompareMem( @Key1, @Key2, 32 ) );
    Sz7zAesDeriveKey( nil, 0, 'abd', 3, 10, Key2 );
    Check( 'key depends on password', not CompareMem( @Key1, @Key2, 32 ) );
    Salt[ 0 ] := 1; Salt[ 1 ] := 2; Salt[ 2 ] := 3; Salt[ 3 ] := 4;
    Sz7zAesDeriveKey( @Salt, 4, 'ab', 2, $3F, Key2 );
    Check( 'NumCyclesPower $3F: salt + password bytes', ( Key2[ 0 ] = 1 ) and ( Key2[ 3 ] = 4 ) and
      ( Key2[ 4 ] = Ord( 'a' ) ) and ( Key2[ 5 ] = 0 ) and ( Key2[ 6 ] = Ord( 'b' ) ) and ( Key2[ 8 ] = 0 ) );
    Check( 'NumCyclesPower 25 rejected (7-Zip limit 24)', not Sz7zAesDeriveKey( nil, 0, 'a', 1, 25, Key2 ) );

    // AES-256-CBC known answer (NIST SP 800-38A, F.2.5), 2 blocks, in place
    HexTo( '603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4', Key1, 32 );
    HexTo( '000102030405060708090a0b0c0d0e0f', IV, 16 );
    HexTo( '6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51', Blk, 32 );
    Sz7zAesEncrypt( Key1, IV, @Blk, 32 );
    HexTo( 'f58c4c04d6e5f1ba779eabfb5f7bfbd69cfc4e967edb808d679f777bc6702c7d', Expect, 32 );
    Check( 'AES-256-CBC encrypt in place = NIST vector', CompareMem( @Blk, @Expect, 32 ) );
    Sz7zAesDecrypt( Key1, IV, @Blk, 32 );
    HexTo( '6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51', Expect, 32 );
    Check( 'AES-256-CBC decrypt in place = plaintext', CompareMem( @Blk, @Expect, 32 ) );

    if not Have7z then
      begin
      Writeln( 'ALL OK' );
      Exit;
      end;
    InitWork( 'p7zAes' );

    TestEncrypted( 'enc', '-mx9', 'Secret', False );                       // 8-coder folder for the exe
    TestEncrypted( 'enchdr', '-mx9 -mhe=on', 'Secret', True );             // encrypted header
    TestEncrypted( 'encns', '-m0=LZMA -ms=off -mhe=on', 'x', True );       // non-solid, one AES folder per file
    // Unicode password: P + a-umlaut + "ss" + CJK
    UPwd := 'P';
    UPwd := UPwd+WideChar( $00E4 );
    UPwd := UPwd+'ss';
    UPwd := UPwd+WideChar( $6F22 );
    TestEncrypted( 'encuni', '-mx5 -mhe=on', UPwd, True );

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
