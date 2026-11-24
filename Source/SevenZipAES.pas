unit SevenZipAES;

// 7zAES (method 06F10701): AES-256-CBC with the 7-Zip key derivation.
// Uses Wolfgang Ehrhardt's AES and SHA-256 units (CRC/Hash + AES packages);
// kept in its own unit so the LZMA units stay usable without them.
// Adding this unit to the project is enough: it registers itself with
// SevenZipIn (encrypted files and encrypted headers, -mhe) and SevenZipOut.
//
// Key derivation (7zAes.cpp): NumCyclesPower = 0x3F -> key = salt + password
// bytes, zero padded; otherwise SHA-256 over 2^NumCyclesPower rounds of
// ( salt + password UTF-16LE + 8-byte little-endian round counter ).
// Props: b0 = NumCyclesPower | (saltSize > 0) shl 7 | (ivSize > 0) shl 6,
//        b1 = (saltSize-1) shl 4 | (ivSize-1), then salt, then IV.

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_CAST OFF}

uses
  Types, LzmaTypes; // LzmaTypes: NativeUInt for D7

type
  T7zAesKey = array [ 0..31 ] of Byte;
  T7zAesIV  = array [ 0..15 ] of Byte;

const
  k7zAesDefaultCyclesPower = 19; // 7-Zip default

// False: NumCyclesPower > 24 (7-Zip's limit) or invalid parameters
function Sz7zAesDeriveKey( Salt : PByte; SaltSize : Integer; Password : PWideChar; PasswordLen : Integer;
  NumCyclesPower : Integer; out Key : T7zAesKey ) : Boolean;

// In place, Len must be a multiple of 16. Result 0 = OK.
function Sz7zAesDecrypt( const Key : T7zAesKey; const IV : T7zAesIV; Data : Pointer; Len : NativeUInt ) : Integer;
function Sz7zAesEncrypt( const Key : T7zAesKey; const IV : T7zAesIV; Data : Pointer; Len : NativeUInt ) : Integer;

// Props for the writer: b0, b1, IV (16 bytes, no salt - as 7-Zip writes it)
function Sz7zAesMakeProps( NumCyclesPower : Integer; const IV : T7zAesIV; out Props : TByteDynArray ) : Integer;

implementation

uses
  Windows, SysUtils, SevenZipIn, BTypes, uHash, SHA256, AES_Type, AES_CBC;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
var
  // last derived key (archives use the same key for the header and all folders)
  CacheLock  : TRTLCriticalSection;
  CacheValid : Boolean = False;
  CacheSalt  : array [ 0..15 ] of Byte;
  CacheSaltN : Integer;
  CachePower : Integer;
  CachePwd   : array of WideChar;
  CacheKey   : T7zAesKey;

function Sz7zAesDeriveKey( Salt : PByte; SaltSize : Integer; Password : PWideChar; PasswordLen : Integer;
  NumCyclesPower : Integer; out Key : T7zAesKey ) : Boolean;
var
  Buf    : array of Byte;
  Pre, n : Integer;
  Rounds, r : Int64;
  Ctx    : THashContext;
  Digest : TSHA256Digest;
  Ctr    : PInt64;
  i      : Integer;
begin
  result := False;
  FillChar( Key, SizeOf( Key ), 0 );
  if ( SaltSize < 0 ) or ( SaltSize > 16 ) or ( PasswordLen < 0 ) or ( NumCyclesPower < 0 ) or
     ( ( NumCyclesPower > 24 ) and ( NumCyclesPower <> $3F ) ) then
    Exit;

  EnterCriticalSection( CacheLock );
  try
    if CacheValid and ( CachePower = NumCyclesPower ) and ( CacheSaltN = SaltSize ) and
       ( Length( CachePwd ) = PasswordLen ) and
       ( ( SaltSize = 0 ) or CompareMem( @CacheSalt[ 0 ], Salt, SaltSize ) ) and
       ( ( PasswordLen = 0 ) or CompareMem( @CachePwd[ 0 ], Password, PasswordLen*2 ) ) then
      begin
      Key := CacheKey;
      result := True;
      Exit;
      end;
  finally
    LeaveCriticalSection( CacheLock );
  end;

  Pre := SaltSize+PasswordLen*2;
  if ( NumCyclesPower = $3F ) then
    begin
    SetLength( Buf, Pre+1 );
    if ( SaltSize > 0 ) then
      Move( Salt^, Buf[ 0 ], SaltSize );
    if ( PasswordLen > 0 ) then
      Move( Password^, Buf[ SaltSize ], PasswordLen*2 );
    n := Pre;
    if ( n > 32 ) then
      n := 32;
    for i := 0 to n-1 do
      Key[ i ] := Buf[ i ];
    end
  else
    begin
    // one buffer per round like 7-Zip: salt + password + counter, the counter in place
    SetLength( Buf, Pre+8 );
    if ( SaltSize > 0 ) then
      Move( Salt^, Buf[ 0 ], SaltSize );
    if ( PasswordLen > 0 ) then
      Move( Password^, Buf[ SaltSize ], PasswordLen*2 );
    Ctr := PInt64( @Buf[ Pre ] );
    Ctr^ := 0;
    Rounds := Int64( 1 ) shl NumCyclesPower;
    SHA256Init( Ctx );
    r := 0;
    while ( r < Rounds ) do
      begin
      SHA256UpdateXL( Ctx, @Buf[ 0 ], Pre+8 );
      Inc( Ctr^ );
      Inc( r );
      end;
    SHA256Final( Ctx, Digest );
    Move( Digest[ 0 ], Key[ 0 ], 32 );
    end;

  EnterCriticalSection( CacheLock );
  try
    CacheValid := True;
    CachePower := NumCyclesPower;
    CacheSaltN := SaltSize;
    if ( SaltSize > 0 ) then
      Move( Salt^, CacheSalt[ 0 ], SaltSize );
    SetLength( CachePwd, PasswordLen );
    if ( PasswordLen > 0 ) then
      Move( Password^, CachePwd[ 0 ], PasswordLen*2 );
    CacheKey := Key;
  finally
    LeaveCriticalSection( CacheLock );
  end;
  result := True;
end;

function Sz7zAesDecrypt( const Key : T7zAesKey; const IV : T7zAesIV; Data : Pointer; Len : NativeUInt ) : Integer;
var
  Ctx : TAESContext;
  B   : TAESBlock;
  K   : T7zAesKey;
begin
  result := SZ_ERROR_PARAM;
  if ( Len mod 16 <> 0 ) or ( Len > NativeUInt( MaxInt ) ) then
    Exit;
  K := Key;
  Move( IV, B, 16 );
  if ( AES_CBC_Init_Decr( K, 256, B, Ctx ) <> 0 ) then
    Exit;
  if ( Len > 0 ) and ( AES_CBC_Decrypt( Data, Data, Len, Ctx ) <> 0 ) then
    Exit;
  FillChar( Ctx, SizeOf( Ctx ), 0 );
  result := SZ_OK;
end;

function Sz7zAesEncrypt( const Key : T7zAesKey; const IV : T7zAesIV; Data : Pointer; Len : NativeUInt ) : Integer;
var
  Ctx : TAESContext;
  B   : TAESBlock;
  K   : T7zAesKey;
begin
  result := SZ_ERROR_PARAM;
  if ( Len mod 16 <> 0 ) or ( Len > NativeUInt( MaxInt ) ) then
    Exit;
  K := Key;
  Move( IV, B, 16 );
  if ( AES_CBC_Init_Encr( K, 256, B, Ctx ) <> 0 ) then
    Exit;
  if ( Len > 0 ) and ( AES_CBC_Encrypt( Data, Data, Len, Ctx ) <> 0 ) then
    Exit;
  FillChar( Ctx, SizeOf( Ctx ), 0 );
  result := SZ_OK;
end;

function Sz7zAesMakeProps( NumCyclesPower : Integer; const IV : T7zAesIV; out Props : TByteDynArray ) : Integer;
begin
  SetLength( Props, 2+16 );
  Props[ 0 ] := Byte( NumCyclesPower and $3F ) or $40; // IV present, no salt
  Props[ 1 ] := 16-1;                                   // ivSize-1 in the low nibble
  Move( IV, Props[ 2 ], 16 );
  result := Length( Props );
end;

function RandomBytes( P : Pointer; Len : Cardinal ) : Boolean;
type
  TRtlGenRandom = function( Buf : Pointer; Len : Cardinal ) : ByteBool; stdcall;
var
  Lib : HMODULE;
  F   : TRtlGenRandom;
begin
  result := False;
  Lib := LoadLibrary( 'advapi32.dll' );
  if ( Lib = 0 ) then
    Exit;
  @F := GetProcAddress( Lib, 'SystemFunction036' ); // RtlGenRandom (cryptographic RNG)
  if Assigned( F ) then
    result := F( P, Len );
  FreeLibrary( Lib );
end;

// Encoder hook for SevenZipOut: random IV, no salt, 2^19 rounds (like 7-Zip)
function AesEncodeHook( Data : PByte; Len : NativeUInt; Password : PWideChar; PasswordLen : Integer;
  out Props : TByteDynArray ) : Integer;
var
  IV  : T7zAesIV;
  Key : T7zAesKey;
begin
  SetLength( Props, 0 );
  result := SZ_ERROR_FAIL;
  if not RandomBytes( @IV, SizeOf( IV ) ) then
    Exit;
  if not Sz7zAesDeriveKey( nil, 0, Password, PasswordLen, k7zAesDefaultCyclesPower, Key ) then
    Exit;
  Sz7zAesMakeProps( k7zAesDefaultCyclesPower, IV, Props );
  result := Sz7zAesEncrypt( Key, IV, Data, Len );
  FillChar( Key, SizeOf( Key ), 0 );
end;

// Decoder hook for SevenZipIn
function AesDecodeHook( Props : PByte; PropsSize : Cardinal; Data : PByte; DataLen : NativeUInt;
  Password : PWideChar; PasswordLen : Integer ) : Integer;
var
  P        : PByteArray7z;
  b0, b1   : Byte;
  SaltSize, IVSize : Integer;
  Power    : Integer;
  IV       : T7zAesIV;
  Key      : T7zAesKey;
begin
  result := SZ_ERROR_UNSUPPORTED;
  P := PByteArray7z( Props );
  if ( PropsSize = 0 ) then
    Exit;
  b0 := P^[ 0 ];
  Power := b0 and $3F;
  SaltSize := 0;
  IVSize := 0;
  if ( b0 and $C0 <> 0 ) then
    begin
    if ( PropsSize < 2 ) then
      Exit;
    b1 := P^[ 1 ];
    SaltSize := ( ( b0 shr 7 ) and 1 )+( b1 shr 4 );
    IVSize   := ( ( b0 shr 6 ) and 1 )+( b1 and $0F );
    if ( Cardinal( 2+SaltSize+IVSize ) <> PropsSize ) then
      Exit;
    end
  else if ( PropsSize <> 1 ) then
    Exit;
  FillChar( IV, SizeOf( IV ), 0 );
  if ( IVSize > 0 ) then
    Move( P^[ 2+SaltSize ], IV[ 0 ], IVSize );
  if not Sz7zAesDeriveKey( @P^[ 2 ], SaltSize, Password, PasswordLen, Power, Key ) then
    Exit;
  result := Sz7zAesDecrypt( Key, IV, Data, DataLen );
  FillChar( Key, SizeOf( Key ), 0 );
end;

initialization
  InitializeCriticalSection( CacheLock );
  Sz7zAesDecode := AesDecodeHook;
  Sz7zAesEncode := AesEncodeHook;

finalization
  Sz7zAesDecode := nil;
  Sz7zAesEncode := nil;
  FillChar( CacheKey, SizeOf( CacheKey ), 0 );
  DeleteCriticalSection( CacheLock );

end.
