unit SevenZipOut;

// Writing 7z archives without 7z.dll, in Pascal after DOC\7zFormat.txt of the
// LZMA SDK, on top of the C encoders (LZMA, LZMA2, BCJ2, branch filters).
//
// Methods (like 7-Zip):
//   Level 0          : Copy
//   Level 1..9       : LZMA2; executables (content check, see LZMAExe):
//                      x86/x64 -> BCJ2 + LZMA2 + LZMA lc0 lp2 (like 7z -mx9),
//                      ARM64   -> ARM64 + LZMA2
//   Password         : AES-256 on every packed stream (needs unit SevenZipAES)
//   Header           : LZMA-compressed, optionally AES-encrypted (EncryptHeader)
// Solid: one folder for the executables and one for everything else (7-Zip:
// "Blocks = 2"); non-solid: one folder per file. Names UTF-16, mtime/ctime,
// Windows attributes, CRC32 per file, empty files and directories.
//
// ponytail: each folder is built in memory (input + output). Fine for installer
// archives and DLL resources; for multi-GB data a streaming writer would be needed.

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_CAST OFF}

{$I LZMA.inc}

uses
  Windows, SysUtils, Classes, Types, LzmaTypes, LZMAExe, SevenZipIn; // LzmaTypes: NativeInt/NativeUInt for D7

type
  T7zWriterItem = record
    Name       : T7zString;    // name in the archive ('\' separated)
    SourceFile : T7zString;    // '' = Data
    Data       : TByteDynArray;
    IsDir      : Boolean;
    Size       : Int64;
    Attrib     : Cardinal;
    MTime      : TFileTime;
    CTime      : TFileTime;
  end;

  T7zWriter = class
  private
    FItems         : array of T7zWriterItem;
    FCount         : Integer;
    FLevel         : Integer;
    FSolid         : Boolean;
    FFilter        : TExeFilter;
    FPassword      : T7zString;
    FEncryptHeader : Boolean;
    FCompressHeader: Boolean;
    function NewItem : Integer;
  public
    constructor Create;
    procedure Clear;
    // ArchiveName '' = file name only
    function AddFile( const FileName : T7zString; const ArchiveName : T7zString = '' ) : Boolean;
    // copies the data
    procedure AddMemory( Data : Pointer; Len : NativeUInt; const ArchiveName : T7zString );
    procedure AddStream( Stream : TStream; const ArchiveName : T7zString ); // from Position to the end
    procedure AddEmptyDir( const ArchiveName : T7zString );
    // a file or a directory with all subdirectories; ArchiveBase = prefix in the archive.
    // IncludeRoot: the directory itself is the top level entry (like "7z a x.7z dir")
    function AddDirectory( const Dir : T7zString; const ArchiveBase : T7zString = ''; IncludeRoot : Boolean = False ) : Boolean;
    function SaveToStream( Dest : TStream ) : Integer; // 0 = OK, negative = error
    function SaveToFile( const FileName : T7zString ) : Integer;
    property Count : Integer read FCount;
    property Level : Integer read FLevel write FLevel;                    // 0..9, default 9
    property Solid : Boolean read FSolid write FSolid;                    // default True
    property Filter : TExeFilter read FFilter write FFilter;              // efAuto: by content
    property Password : T7zString read FPassword write FPassword;         // '' = no encryption
    property EncryptHeader : Boolean read FEncryptHeader write FEncryptHeader; // default True (with password)
    property CompressHeader : Boolean read FCompressHeader write FCompressHeader; // default True
  end;

// LZMA (1) with explicit lc/lp/dictionary, no end mark (7z stores the size). Props = 5 bytes.
function Lzma7zEncode( Src : PByte; Len : NativeUInt; Level, lc, lp : Integer; DictSize : Cardinal;
  out Props : TByteDynArray; out Packed_ : TByteDynArray ) : Integer;

implementation

uses
  LzmaEnc, LZMA2, Bra, Bcj2;

const
  kEnd                = $00;
  kHeader             = $01;
  kMainStreamsInfo    = $04;
  kFilesInfo          = $05;
  kPackInfo           = $06;
  kUnPackInfo         = $07;
  kSubStreamsInfo     = $08;
  kSize               = $09;
  kCRC                = $0A;
  kFolder             = $0B;
  kCodersUnPackSize   = $0C;
  kNumUnPackStream    = $0D;
  kEmptyStream        = $0E;
  kEmptyFile          = $0F;
  kName               = $11;
  kCTime              = $12;
  kMTime              = $14;
  kWinAttributes      = $15;
  kEncodedHeader      = $17;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Byte buffer
type
  TBuf = record
    D : TByteDynArray;
    N : Integer;
  end;

procedure BufPut( var B : TBuf; P : Pointer; Len : Integer );
var
  Cap : Integer;
begin
  if ( Len <= 0 ) then
    Exit;
  if ( B.N+Len > Length( B.D ) ) then
    begin
    Cap := Length( B.D )*2;
    if ( Cap < B.N+Len ) then
      Cap := B.N+Len+256;
    SetLength( B.D, Cap );
    end;
  Move( P^, B.D[ B.N ], Len );
  Inc( B.N, Len );
end;

procedure BufByte( var B : TBuf; V : Byte );
begin
  BufPut( B, @V, 1 );
end;

procedure BufU32( var B : TBuf; V : Cardinal );
begin
  BufPut( B, @V, 4 );
end;

procedure BufU64( var B : TBuf; V : Int64 );
begin
  BufPut( B, @V, 8 );
end;

// 7z NUMBER: the count of leading 1 bits in the first byte = number of extra bytes
procedure BufNum( var B : TBuf; V : Int64 );
var
  First, Mask : Byte;
  i, j : Integer;
begin
  First := 0;
  Mask := $80;
  i := 0;
  while ( i < 8 ) do
    begin
    if ( V >= 0 ) and ( V < ( Int64( 1 ) shl ( 7*( i+1 ) ) ) ) then
      begin
      First := First or Byte( V shr ( 8*i ) );
      Break;
      end;
    First := First or Mask;
    Mask := Mask shr 1;
    Inc( i );
    end;
  BufByte( B, First );
  for j := 0 to i-1 do
    BufByte( B, Byte( V shr ( 8*j ) ) );
end;

function BufBytes( const B : TBuf ) : TByteDynArray;
begin
  SetLength( result, B.N );
  if ( B.N > 0 ) then
    Move( B.D[ 0 ], result[ 0 ], B.N );
end;

// bit vector, MSB first
procedure BufBits( var B : TBuf; const Bits : array of Boolean );
var
  i : Integer;
  V, Mask : Byte;
begin
  V := 0;
  Mask := $80;
  for i := 0 to High( Bits ) do
    begin
    if Bits[ i ] then
      V := V or Mask;
    Mask := Mask shr 1;
    if ( Mask = 0 ) then
      begin
      BufByte( B, V );
      V := 0;
      Mask := $80;
      end;
    end;
  if ( Mask <> $80 ) then
    BufByte( B, V );
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Encoders
function Lzma7zEncode( Src : PByte; Len : NativeUInt; Level, lc, lp : Integer; DictSize : Cardinal;
  out Props : TByteDynArray; out Packed_ : TByteDynArray ) : Integer;
var
  Enc : TCLzmaEncHandle;
  P   : TCLzmaEncProps;
  PropLen, OutLen : NativeInt;
begin
  SetLength( Props, 5 );
  SetLength( Packed_, 0 );
  result := -SZ_ERROR_MEM;
  Enc := {$IFDEF UNDERSCORE}_LzmaEnc_Create{$ELSE}LzmaEnc_Create{$ENDIF}( TISzAllocDefault );
  if ( Enc = nil ) then
    Exit;
  try
    {$IFDEF UNDERSCORE}_LzmaEncProps_Init{$ELSE}LzmaEncProps_Init{$ENDIF}( P );
    P.level := Level;
    if ( lc >= 0 ) then P.lc := lc;
    if ( lp >= 0 ) then P.lp := lp;
    if ( DictSize > 0 ) then P.dictSize := DictSize;
    PInt64( @P.reduceSize )^ := Len; // no UInt64 arithmetic: D7 + {$R+} = internal error C1118
    P.writeEndMark := 0;
    result := -Abs( {$IFDEF UNDERSCORE}_LzmaEnc_SetProps{$ELSE}LzmaEnc_SetProps{$ENDIF}( Enc, P ) );
    if ( result <> 0 ) then
      Exit;
    PropLen := 5;
    result := -Abs( {$IFDEF UNDERSCORE}_LzmaEnc_WriteProperties{$ELSE}LzmaEnc_WriteProperties{$ENDIF}( Enc, @Props[ 0 ], PropLen ) );
    if ( result <> 0 ) then
      Exit;
    if ( Len = 0 ) then
      begin
      SetLength( Packed_, 16 );
      OutLen := 16;
      result := -Abs( {$IFDEF UNDERSCORE}_LzmaEnc_MemEncode{$ELSE}LzmaEnc_MemEncode{$ENDIF}( Enc, @Packed_[ 0 ], OutLen, @Props[ 0 ], 0, 0, nil, TISzAllocDefault, TISzAllocDefault ) );
      end
    else
      begin
      SetLength( Packed_, Int64( Len )+Int64( Len div 3 )+128 );
      OutLen := Length( Packed_ );
      result := -Abs( {$IFDEF UNDERSCORE}_LzmaEnc_MemEncode{$ELSE}LzmaEnc_MemEncode{$ENDIF}( Enc, @Packed_[ 0 ], OutLen, Src, Len, 0, nil, TISzAllocDefault, TISzAllocDefault ) );
      end;
    if ( result = 0 ) then
      SetLength( Packed_, OutLen )
    else
      SetLength( Packed_, 0 );
  finally
    {$IFDEF UNDERSCORE}_LzmaEnc_Destroy{$ELSE}LzmaEnc_Destroy{$ENDIF}( Enc, TISzAllocDefault, TISzAllocDefault );
  end;
end;

// LZMA2: CompressLZMA2 writes 1 property byte + data
function Lzma2Encode7z( Src : PByte; Len : NativeUInt; Level : Integer; out Prop : Byte; out Packed_ : TByteDynArray ) : Integer;
var
  Tmp : TByteDynArray;
  Dummy : Byte;
  n : Int64;
begin
  SetLength( Packed_, 0 );
  Prop := 0;
  if ( Len = 0 ) then
    begin
    Dummy := 0;
    n := CompressLZMA2( @Dummy, 1, Tmp, False, Level ); // CompressLZMA2 refuses Len = 0: take the props from 1 byte
    if ( n <= 1 ) then begin result := -SZ_ERROR_FAIL; Exit; end;
    Prop := Tmp[ 0 ];
    SetLength( Packed_, 1 );
    Packed_[ 0 ] := 0; // LZMA2 end marker only
    result := 0;
    Exit;
    end;
  n := CompressLZMA2( Src, Len, Tmp, False, Level );
  if ( n <= 1 ) or ( Length( Tmp ) <> n ) then
    begin
    if ( n > 0 ) then n := -n;
    if ( n = 0 ) then n := -SZ_ERROR_FAIL;
    result := n;
    Exit;
    end;
  Prop := Tmp[ 0 ];
  SetLength( Packed_, n-1 );
  Move( Tmp[ 1 ], Packed_[ 0 ], n-1 );
  result := 0;
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Folder model (coders, bonds, packed streams)
type
  TIntArray7z = array of Integer;

  TWCoder = record
    MethodID   : Cardinal;
    IdSize     : Integer;
    NumIn      : Integer;
    Props      : TByteDynArray;
    UnpackSize : Int64;
  end;

  TWFolder = record
    Coders      : array of TWCoder;
    BondIn      : array of Integer;  // in-stream index
    BondOut     : array of Integer;  // coder index
    PackIn      : array of Integer;  // in-stream index of each packed stream
    Packed_     : array of TByteDynArray;
    UnpackCRC   : Cardinal;          // CRC of the folder output
    Files       : TIntArray7z;       // item indices (substreams)
  end;

function MethodIdSize( Id : Cardinal ) : Integer;
begin
  if ( Id = 0 ) then result := 1
  else if ( Id <= $FF ) then result := 1
  else if ( Id <= $FFFF ) then result := 2
  else if ( Id <= $FFFFFF ) then result := 3
  else result := 4;
end;

function AddCoder( var F : TWFolder; Id : Cardinal; NumIn : Integer; const Props : TByteDynArray; UnpackSize : Int64 ) : Integer;
begin
  result := Length( F.Coders );
  SetLength( F.Coders, result+1 );
  F.Coders[ result ].MethodID := Id;
  F.Coders[ result ].IdSize := MethodIdSize( Id );
  F.Coders[ result ].NumIn := NumIn;
  F.Coders[ result ].Props := Props;
  F.Coders[ result ].UnpackSize := UnpackSize;
end;

function FirstIn( const F : TWFolder; Coder : Integer ) : Integer;
var
  i : Integer;
begin
  result := 0;
  for i := 0 to Coder-1 do
    Inc( result, F.Coders[ i ].NumIn );
end;

procedure AddBond( var F : TWFolder; InIndex, OutCoder : Integer );
var
  n : Integer;
begin
  n := Length( F.BondIn );
  SetLength( F.BondIn, n+1 );
  SetLength( F.BondOut, n+1 );
  F.BondIn[ n ] := InIndex;
  F.BondOut[ n ] := OutCoder;
end;

procedure AddPack( var F : TWFolder; InIndex : Integer; const Data : TByteDynArray );
var
  n : Integer;
begin
  n := Length( F.PackIn );
  SetLength( F.PackIn, n+1 );
  SetLength( F.Packed_, n+1 );
  F.PackIn[ n ] := InIndex;
  F.Packed_[ n ] := Data;
end;

// Wrap every packed stream with an AES coder (one per packed stream, like 7-Zip)
function EncryptFolder( var F : TWFolder; const Password : T7zString ) : Integer;
var
  k, c, n : Integer;
  Props, Data : TByteDynArray;
  Len : Int64;
begin
  result := 0;
  if ( Password = '' ) then
    Exit;
  result := E7Z_PASSWORD;
  if not Assigned( Sz7zAesEncode ) then
    Exit; // unit SevenZipAES not linked
  for k := 0 to High( F.Packed_ ) do
    begin
    Len := Length( F.Packed_[ k ] );
    Data := F.Packed_[ k ];
    n := ( Len+15 ) and not 15;
    SetLength( Data, n );
    if ( n > Len ) then
      FillChar( Data[ Len ], n-Len, 0 );
    result := Sz7zAesEncode( PByte( Data ), n, PWideChar( Password ), Length( Password ), Props );
    if ( result <> 0 ) then
      begin
      result := -Abs( result );
      Exit;
      end;
    c := AddCoder( F, k7zIdAES, 1, Props, Len );
    AddBond( F, F.PackIn[ k ], c );           // the former packed stream is now AES output
    F.PackIn[ k ] := FirstIn( F, c );         // AES input is packed
    F.Packed_[ k ] := Data;
    end;
  result := 0;
end;

// Build a folder from the data of its files
function BuildFolder( var F : TWFolder; const Data : TByteDynArray; Len : Int64; Level : Integer;
  Filter : TExeFilter; const Password : T7zString ) : Integer;
var
  Prop : Byte;
  PB, PropsL, Out_, Work : TByteDynArray;
  S : TBcj2Streams;
  cMain, c : Integer;
  i : Integer;
  Empty : TByteDynArray;
begin
  SetLength( Empty, 0 );
  F.UnpackCRC := Crc7z( PByte( Data ), Len );
  if ( Level <= 0 ) then
    begin
    AddCoder( F, k7zIdCopy, 1, Empty, Len );
    AddPack( F, 0, Data );
    result := EncryptFolder( F, Password );
    Exit;
    end;

  if ( Filter = efX86 ) then
    begin
    // BCJ2 (4 in) <- LZMA2 (main), LZMA (call), LZMA (jump), RC stored
    if not Bcj2Encode( PByte( Data ), Len, S ) then
      begin
      result := -SZ_ERROR_FAIL;
      Exit;
      end;
    AddCoder( F, k7zIdBCJ2, 4, Empty, Len );
    result := Lzma2Encode7z( PByte( S[ 0 ] ), Length( S[ 0 ] ), Level, Prop, Out_ );
    if ( result <> 0 ) then Exit;
    SetLength( PB, 1 ); PB[ 0 ] := Prop;
    cMain := AddCoder( F, k7zIdLZMA2, 1, PB, Length( S[ 0 ] ) );
    AddBond( F, 0, cMain );
    AddPack( F, FirstIn( F, cMain ), Out_ );
    for i := 1 to 2 do
      begin
      result := Lzma7zEncode( PByte( S[ i ] ), Length( S[ i ] ), Level, 0, 2, 1 shl 20, PropsL, Out_ );
      if ( result <> 0 ) then Exit;
      c := AddCoder( F, k7zIdLZMA, 1, PropsL, Length( S[ i ] ) );
      AddBond( F, i, c );
      AddPack( F, FirstIn( F, c ), Out_ );
      end;
    AddPack( F, 3, S[ 3 ] );
    result := EncryptFolder( F, Password );
    Exit;
    end;

  if ( Filter = efARM64 ) then
    begin
    Work := Copy( Data, 0, Len );
    ExeFilterEncode( PByte( Work ), Len, efARM64 );
    AddCoder( F, k7zIdARM64, 1, Empty, Len );
    result := Lzma2Encode7z( PByte( Work ), Len, Level, Prop, Out_ );
    if ( result <> 0 ) then Exit;
    SetLength( PB, 1 ); PB[ 0 ] := Prop;
    c := AddCoder( F, k7zIdLZMA2, 1, PB, Len );
    AddBond( F, 0, c );
    AddPack( F, FirstIn( F, c ), Out_ );
    result := EncryptFolder( F, Password );
    Exit;
    end;

  result := Lzma2Encode7z( PByte( Data ), Len, Level, Prop, Out_ );
  if ( result <> 0 ) then Exit;
  SetLength( PB, 1 ); PB[ 0 ] := Prop;
  AddCoder( F, k7zIdLZMA2, 1, PB, Len );
  AddPack( F, 0, Out_ );
  result := EncryptFolder( F, Password );
end;

// 7-Zip stores the coders in reverse order: the main coder (e.g. BCJ2) last, the
// coders next to the packed streams (AES) first. 7z.exe rejects BCJ2 + AES folders
// in our build order at random ("Can't allocate required memory", depends on the
// random IV) - with the 7-Zip order they are accepted. In-stream indices, bonds and
// packed streams are renumbered accordingly; the meaning of the folder is unchanged.
function ReverseCoders( const F : TWFolder ) : TWFolder;
var
  n, c, i, k : Integer;
  OldFirst, NewFirst : array of Integer;

  function MapIn( s : Integer ) : Integer;
  var
    cc : Integer;
  begin
    result := -1;
    for cc := 0 to n-1 do
      if ( s >= OldFirst[ cc ] ) and ( s < OldFirst[ cc ]+F.Coders[ cc ].NumIn ) then
        begin
        result := NewFirst[ n-1-cc ]+( s-OldFirst[ cc ] );
        Exit;
        end;
  end;

begin
  result := F;
  n := Length( F.Coders );
  SetLength( result.Coders, n );
  for c := 0 to n-1 do
    result.Coders[ c ] := F.Coders[ n-1-c ];
  SetLength( OldFirst, n );
  SetLength( NewFirst, n );
  k := 0;
  for c := 0 to n-1 do
    begin
    OldFirst[ c ] := k;
    Inc( k, F.Coders[ c ].NumIn );
    end;
  k := 0;
  for c := 0 to n-1 do
    begin
    NewFirst[ c ] := k;
    Inc( k, result.Coders[ c ].NumIn );
    end;
  result.BondIn := Copy( F.BondIn, 0, MaxInt );
  result.BondOut := Copy( F.BondOut, 0, MaxInt );
  for i := 0 to High( F.BondIn ) do
    begin
    result.BondIn[ i ] := MapIn( F.BondIn[ i ] );
    result.BondOut[ i ] := n-1-F.BondOut[ i ];
    end;
  result.PackIn := Copy( F.PackIn, 0, MaxInt );
  for i := 0 to High( F.PackIn ) do
    result.PackIn[ i ] := MapIn( F.PackIn[ i ] );
end;

procedure WriteFolder( var B : TBuf; const F : TWFolder );
var
  i, j : Integer;
  Flags : Byte;
begin
  BufNum( B, Length( F.Coders ) );
  for i := 0 to High( F.Coders ) do
    begin
    Flags := F.Coders[ i ].IdSize;
    if ( F.Coders[ i ].NumIn <> 1 ) then
      Flags := Flags or $10;
    if ( Length( F.Coders[ i ].Props ) > 0 ) then
      Flags := Flags or $20;
    BufByte( B, Flags );
    for j := F.Coders[ i ].IdSize-1 downto 0 do // big endian
      BufByte( B, Byte( F.Coders[ i ].MethodID shr ( 8*j ) ) );
    if ( F.Coders[ i ].NumIn <> 1 ) then
      begin
      BufNum( B, F.Coders[ i ].NumIn );
      BufNum( B, 1 );
      end;
    if ( Length( F.Coders[ i ].Props ) > 0 ) then
      begin
      BufNum( B, Length( F.Coders[ i ].Props ) );
      BufPut( B, @F.Coders[ i ].Props[ 0 ], Length( F.Coders[ i ].Props ) );
      end;
    end;
  for i := 0 to High( F.BondIn ) do
    begin
    BufNum( B, F.BondIn[ i ] );
    BufNum( B, F.BondOut[ i ] );
    end;
  if ( Length( F.PackIn ) > 1 ) then
    for i := 0 to High( F.PackIn ) do
      BufNum( B, F.PackIn[ i ] );
end;

// PackInfo + UnpackInfo (+ SubStreamsInfo)
procedure WriteStreamsInfo( var B : TBuf; const Folders : array of TWFolder; PackPos : Int64;
  const Sizes : array of Int64; const CRCs : array of Cardinal; WithSubStreams : Boolean );
var
  i, j, NumPack : Integer;
  NeedCounts, NeedSizes : Boolean;
begin
  NumPack := 0;
  for i := 0 to High( Folders ) do
    Inc( NumPack, Length( Folders[ i ].Packed_ ) );

  BufByte( B, kPackInfo );
  BufNum( B, PackPos );
  BufNum( B, NumPack );
  BufByte( B, kSize );
  for i := 0 to High( Folders ) do
    for j := 0 to High( Folders[ i ].Packed_ ) do
      BufNum( B, Length( Folders[ i ].Packed_[ j ] ) );
  BufByte( B, kEnd );

  BufByte( B, kUnPackInfo );
  BufByte( B, kFolder );
  BufNum( B, Length( Folders ) );
  BufByte( B, 0 ); // External
  for i := 0 to High( Folders ) do
    WriteFolder( B, ReverseCoders( Folders[ i ] ) );
  BufByte( B, kCodersUnPackSize );
  for i := 0 to High( Folders ) do
    for j := High( Folders[ i ].Coders ) downto 0 do // reverse order, see ReverseCoders
      BufNum( B, Folders[ i ].Coders[ j ].UnpackSize );
  if not WithSubStreams then
    begin // folder CRCs (encoded header)
    BufByte( B, kCRC );
    BufByte( B, 1 ); // all defined
    for i := 0 to High( Folders ) do
      BufU32( B, Folders[ i ].UnpackCRC );
    end;
  BufByte( B, kEnd );

  if WithSubStreams then
    begin
    BufByte( B, kSubStreamsInfo );
    NeedCounts := False;
    NeedSizes := False;
    for i := 0 to High( Folders ) do
      if ( Length( Folders[ i ].Files ) <> 1 ) then
        begin
        NeedCounts := True;
        NeedSizes := True;
        end;
    if NeedCounts then
      begin
      BufByte( B, kNumUnPackStream );
      for i := 0 to High( Folders ) do
        BufNum( B, Length( Folders[ i ].Files ) );
      end;
    if NeedSizes then
      begin
      BufByte( B, kSize );
      for i := 0 to High( Folders ) do
        for j := 0 to High( Folders[ i ].Files )-1 do // all but the last
          BufNum( B, Sizes[ Folders[ i ].Files[ j ] ] );
      end;
    BufByte( B, kCRC );
    BufByte( B, 1 ); // all defined
    for i := 0 to High( Folders ) do
      for j := 0 to High( Folders[ i ].Files ) do
        BufU32( B, CRCs[ Folders[ i ].Files[ j ] ] );
    BufByte( B, kEnd );
    end;
  BufByte( B, kEnd );
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// T7zWriter
constructor T7zWriter.Create;
begin
  inherited;
  FLevel := 9;
  FSolid := True;
  FFilter := efAuto;
  FEncryptHeader := True;
  FCompressHeader := True;
end;

procedure T7zWriter.Clear;
begin
  SetLength( FItems, 0 );
  FCount := 0;
end;

function T7zWriter.NewItem : Integer;
begin
  if ( FCount = Length( FItems ) ) then
    SetLength( FItems, FCount*2+16 );
  result := FCount;
  Inc( FCount );
  FItems[ result ].Name := '';
  FItems[ result ].SourceFile := '';
  SetLength( FItems[ result ].Data, 0 );
  FItems[ result ].IsDir := False;
  FItems[ result ].Size := 0;
  FItems[ result ].Attrib := FILE_ATTRIBUTE_ARCHIVE;
  GetSystemTimeAsFileTime( FItems[ result ].MTime );
  FItems[ result ].CTime := FItems[ result ].MTime;
end;

function CleanName( const S : T7zString ) : T7zString;
var
  i : Integer;
begin
  result := S;
  for i := 1 to Length( result ) do
    if ( result[ i ] = '/' ) then
      result[ i ] := '\';
  while ( Length( result ) > 0 ) and ( result[ 1 ] = '\' ) do
    Delete( result, 1, 1 );
  while ( Length( result ) > 0 ) and ( result[ Length( result ) ] = '\' ) do
    Delete( result, Length( result ), 1 );
end;

function ExtractNameW( const Path : T7zString ) : T7zString;
var
  i : Integer;
begin
  i := Length( Path );
  while ( i > 0 ) and ( Path[ i ] <> '\' ) and ( Path[ i ] <> '/' ) and ( Path[ i ] <> ':' ) do
    Dec( i );
  result := Copy( Path, i+1, MaxInt );
end;

function T7zWriter.AddFile( const FileName : T7zString; const ArchiveName : T7zString = '' ) : Boolean;
var
  D : TWin32FileAttributeData;
  i : Integer;
begin
  result := GetFileAttributesExW( PWideChar( FileName ), GetFileExInfoStandard, @D ) and
            ( D.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY = 0 );
  if not result then
    Exit;
  i := NewItem;
  FItems[ i ].SourceFile := FileName;
  if ( ArchiveName = '' ) then
    FItems[ i ].Name := ExtractNameW( FileName )
  else
    FItems[ i ].Name := CleanName( ArchiveName );
  FItems[ i ].Size := ( Int64( D.nFileSizeHigh ) shl 32 ) or D.nFileSizeLow;
  FItems[ i ].Attrib := D.dwFileAttributes;
  FItems[ i ].MTime := D.ftLastWriteTime;
  FItems[ i ].CTime := D.ftCreationTime;
end;

procedure T7zWriter.AddMemory( Data : Pointer; Len : NativeUInt; const ArchiveName : T7zString );
var
  i : Integer;
begin
  i := NewItem;
  FItems[ i ].Name := CleanName( ArchiveName );
  SetLength( FItems[ i ].Data, Len );
  if ( Len > 0 ) then
    Move( Data^, FItems[ i ].Data[ 0 ], Len );
  FItems[ i ].Size := Len;
end;

procedure T7zWriter.AddStream( Stream : TStream; const ArchiveName : T7zString );
var
  i : Integer;
  n : Int64;
begin
  i := NewItem;
  FItems[ i ].Name := CleanName( ArchiveName );
  n := Stream.Size-Stream.Position;
  if ( n < 0 ) then
    n := 0;
  SetLength( FItems[ i ].Data, n );
  if ( n > 0 ) then
    Stream.ReadBuffer( FItems[ i ].Data[ 0 ], n );
  FItems[ i ].Size := n;
end;

procedure T7zWriter.AddEmptyDir( const ArchiveName : T7zString );
var
  i : Integer;
begin
  i := NewItem;
  FItems[ i ].Name := CleanName( ArchiveName );
  FItems[ i ].IsDir := True;
  FItems[ i ].Attrib := FILE_ATTRIBUTE_DIRECTORY;
end;

function T7zWriter.AddDirectory( const Dir : T7zString; const ArchiveBase : T7zString = ''; IncludeRoot : Boolean = False ) : Boolean;

  procedure Walk( const Path, Arc : T7zString );
  var
    F : TWin32FindDataW;
    H : THandle;
    N, A : T7zString;
    i : Integer;
  begin
    H := FindFirstFileW( PWideChar( Path+'\*' ), F );
    if ( H = INVALID_HANDLE_VALUE ) then
      Exit;
    try
      repeat
        N := F.cFileName;
        if ( N = '.' ) or ( N = '..' ) then
          Continue;
        if ( Arc = '' ) then A := N else A := Arc+'\'+N;
        if ( F.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY <> 0 ) then
          begin
          i := NewItem;
          FItems[ i ].Name := A;
          FItems[ i ].IsDir := True;
          FItems[ i ].Attrib := F.dwFileAttributes;
          FItems[ i ].MTime := F.ftLastWriteTime;
          FItems[ i ].CTime := F.ftCreationTime;
          if ( F.dwFileAttributes and $400 {FILE_ATTRIBUTE_REPARSE_POINT, not in D7} = 0 ) then // no junction loops
            Walk( Path+'\'+N, A );
          end
        else
          AddFile( Path+'\'+N, A );
      until not FindNextFileW( H, F );
    finally
      Windows.FindClose( H );
    end;
  end;

var
  D : TWin32FileAttributeData;
  Base, Root : T7zString;
  i : Integer;
begin
  result := GetFileAttributesExW( PWideChar( Dir ), GetFileExInfoStandard, @D );
  if not result then
    Exit;
  if ( D.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY = 0 ) then
    begin
    if ( ArchiveBase = '' ) then
      result := AddFile( Dir )
    else
      result := AddFile( Dir, CleanName( ArchiveBase )+'\'+ExtractNameW( Dir ) );
    Exit;
    end;
  Root := Dir;
  while ( Length( Root ) > 3 ) and ( Root[ Length( Root ) ] = '\' ) do
    Delete( Root, Length( Root ), 1 );
  Base := CleanName( ArchiveBase );
  if IncludeRoot then
    begin
    if ( Base = '' ) then Base := ExtractNameW( Root ) else Base := Base+'\'+ExtractNameW( Root );
    i := NewItem;
    FItems[ i ].Name := Base;
    FItems[ i ].IsDir := True;
    FItems[ i ].Attrib := D.dwFileAttributes;
    FItems[ i ].MTime := D.ftLastWriteTime;
    FItems[ i ].CTime := D.ftCreationTime;
    end;
  Walk( Root, Base );
end;

// the first bytes of an item (content check for the filter)
function ReadItemHead( const It : T7zWriterItem; var Buf : TByteDynArray ) : Integer;
var
  H : THandle;
  R : Cardinal;
begin
  result := 0;
  if ( It.SourceFile = '' ) then
    begin
    result := Length( It.Data );
    if ( result > Length( Buf ) ) then result := Length( Buf );
    if ( result > 0 ) then Move( It.Data[ 0 ], Buf[ 0 ], result );
    Exit;
    end;
  H := CreateFileW( PWideChar( It.SourceFile ), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0 );
  if ( H = INVALID_HANDLE_VALUE ) then
    Exit;
  if ReadFile( H, Buf[ 0 ], Length( Buf ), R, nil ) then
    result := R;
  CloseHandle( H );
end;

// the whole item into Buf at Pos (Buf must have room for It.Size bytes)
function LoadItemData( const It : T7zWriterItem; var Buf : TByteDynArray; Pos : Int64 ) : Boolean;
var
  H : THandle;
  R : Cardinal;
  Left, Chunk : Int64;
  P : PByte;
begin
  result := True;
  if ( It.Size = 0 ) then
    Exit;
  if ( It.SourceFile = '' ) then
    begin
    Move( It.Data[ 0 ], Buf[ Pos ], It.Size );
    Exit;
    end;
  result := False;
  H := CreateFileW( PWideChar( It.SourceFile ), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, 0 );
  if ( H = INVALID_HANDLE_VALUE ) then
    Exit;
  try
    P := @Buf[ Pos ];
    Left := It.Size;
    while ( Left > 0 ) do
      begin
      Chunk := Left;
      if ( Chunk > $10000000 ) then Chunk := $10000000;
      if not ReadFile( H, P^, Chunk, R, nil ) or ( R <> Chunk ) then
        Exit; // file changed since AddFile
      Inc( P, R );
      Dec( Left, R );
      end;
    result := True;
  finally
    CloseHandle( H );
  end;
end;

function T7zWriter.SaveToStream( Dest : TStream ) : Integer;
var
  Order    : array of Integer;  // final item order: empty items first, then stream items by folder
  Folders  : array of TWFolder;
  Sizes    : array of Int64;
  CRCs     : array of Cardinal;
  i, j, k, n, NumItems : Integer;
  Group    : array of TExeFilter;
  Data     : TByteDynArray;
  Len      : Int64;
  Kinds    : array [ TExeFilter ] of TIntArray7z;
  K_       : TExeFilter;
  Hb, Eb   : TBuf;
  PackSize : Int64;
  HeaderBytes, NextHeader : TByteDynArray;
  HF       : array of TWFolder;
  Start    : Int64;
  SH       : array [ 0..31 ] of Byte;
  Crc      : Cardinal;
  Bits     : array of Boolean;
  HasEmptyFile : Boolean;
  NumEmpty : Integer;
  Pwd      : T7zString;
  PL       : TByteDynArray;
  NameBuf  : TBuf;
  W        : T7zString;
begin
  result := -SZ_ERROR_PARAM;
  if ( Dest = nil ) then
    Exit;
  if ( FPassword <> '' ) and not Assigned( Sz7zAesEncode ) then
    begin
    result := E7Z_PASSWORD; // SevenZipAES not in the project
    Exit;
    end;
  try
    // --- item order and folders ---
    NumItems := FCount;
    SetLength( Sizes, NumItems );
    SetLength( CRCs, NumItems );
    for i := 0 to NumItems-1 do
      Sizes[ i ] := FItems[ i ].Size;
    SetLength( Group, NumItems );
    for K_ := Low( TExeFilter ) to High( TExeFilter ) do
      SetLength( Kinds[ K_ ], 0 );
    n := 0;
    SetLength( Order, NumItems );
    for i := 0 to NumItems-1 do
      if FItems[ i ].IsDir or ( FItems[ i ].Size = 0 ) then
        begin
        Order[ n ] := i;
        Inc( n );
        end;
    NumEmpty := n;

    // stream items: classify by content (first 4 KB are enough for the PE header)
    for i := 0 to NumItems-1 do
      if not FItems[ i ].IsDir and ( FItems[ i ].Size > 0 ) then
        begin
        if ( FLevel <= 0 ) then
          K_ := efNone
        else if ( FFilter <> efAuto ) then
          K_ := FFilter
        else
          begin
          if ( FItems[ i ].SourceFile = '' ) then
            K_ := DetectExeFilter( PByte( FItems[ i ].Data ), FItems[ i ].Size )
          else
            begin
            SetLength( Data, 4096 );
            Len := ReadItemHead( FItems[ i ], Data );
            K_ := DetectExeFilter( PByte( Data ), Len );
            end;
          end;
        Group[ i ] := K_;
        j := Length( Kinds[ K_ ] );
        SetLength( Kinds[ K_ ], j+1 );
        Kinds[ K_ ][ j ] := i;
        end;
    SetLength( Data, 0 );

    // folders: solid = one per kind (executables first, like 7-Zip), else one per file
    SetLength( Folders, 0 );
    for k := 0 to 2 do
      begin
      case k of
        0 : K_ := efX86;
        1 : K_ := efARM64;
      else
        K_ := efNone;
      end;
      if ( Length( Kinds[ K_ ] ) = 0 ) then
        Continue;
      if FSolid then
        begin
        j := Length( Folders );
        SetLength( Folders, j+1 );
        Folders[ j ].Files := Copy( Kinds[ K_ ], 0, MaxInt );
        end
      else
        for i := 0 to High( Kinds[ K_ ] ) do
          begin
          j := Length( Folders );
          SetLength( Folders, j+1 );
          SetLength( Folders[ j ].Files, 1 );
          Folders[ j ].Files[ 0 ] := Kinds[ K_ ][ i ];
          end;
      end;
    for i := 0 to High( Folders ) do
      for j := 0 to High( Folders[ i ].Files ) do
        begin
        Order[ n ] := Folders[ i ].Files[ j ];
        Inc( n );
        end;

    // --- start header placeholder, then the packed streams ---
    Start := Dest.Position;
    FillChar( SH, SizeOf( SH ), 0 );
    Dest.WriteBuffer( SH, SizeOf( SH ) );
    PackSize := 0;
    for i := 0 to High( Folders ) do
      begin
      Len := 0;
      for j := 0 to High( Folders[ i ].Files ) do
        Inc( Len, FItems[ Folders[ i ].Files[ j ] ].Size );
      SetLength( Data, Len );
      Len := 0;
      for j := 0 to High( Folders[ i ].Files ) do
        begin
        if not LoadItemData( FItems[ Folders[ i ].Files[ j ] ], Data, Len ) then
          begin
          result := E7Z_IO;
          Exit;
          end;
        Inc( Len, FItems[ Folders[ i ].Files[ j ] ].Size );
        end;
      // per file CRC (stored in SubStreamsInfo)
      Len := 0;
      for j := 0 to High( Folders[ i ].Files ) do
        begin
        k := Folders[ i ].Files[ j ];
        CRCs[ k ] := Crc7z( PByte( PAnsiChar( PByte( Data ) )+Len ), FItems[ k ].Size );
        Inc( Len, FItems[ k ].Size );
        end;
      K_ := Group[ Folders[ i ].Files[ 0 ] ];
      result := BuildFolder( Folders[ i ], Data, Len, FLevel, K_, FPassword );
      if ( result <> 0 ) then
        Exit;
      SetLength( Data, 0 );
      for j := 0 to High( Folders[ i ].Packed_ ) do
        begin
        if ( Length( Folders[ i ].Packed_[ j ] ) > 0 ) then
          Dest.WriteBuffer( Folders[ i ].Packed_[ j ][ 0 ], Length( Folders[ i ].Packed_[ j ] ) );
        Inc( PackSize, Length( Folders[ i ].Packed_[ j ] ) );
        end;
      end;

    // --- header ---
    Hb.N := 0; SetLength( Hb.D, 0 );
    BufByte( Hb, kHeader );
    if ( Length( Folders ) > 0 ) then
      begin
      BufByte( Hb, kMainStreamsInfo );
      WriteStreamsInfo( Hb, Folders, 0, Sizes, CRCs, True );
      end;

    if ( NumItems > 0 ) then
      begin
      BufByte( Hb, kFilesInfo );
      BufNum( Hb, NumItems );
      if ( NumEmpty > 0 ) then
        begin
        SetLength( Bits, NumItems );
        for i := 0 to NumItems-1 do
          Bits[ i ] := i < NumEmpty;
        Eb.N := 0; SetLength( Eb.D, 0 );
        BufBits( Eb, Bits );
        BufByte( Hb, kEmptyStream );
        BufNum( Hb, Eb.N );
        BufPut( Hb, @Eb.D[ 0 ], Eb.N );
        SetLength( Bits, NumEmpty );
        HasEmptyFile := False;
        for i := 0 to NumEmpty-1 do
          begin
          Bits[ i ] := not FItems[ Order[ i ] ].IsDir;
          HasEmptyFile := HasEmptyFile or Bits[ i ];
          end;
        if HasEmptyFile then
          begin
          Eb.N := 0;
          BufBits( Eb, Bits );
          BufByte( Hb, kEmptyFile );
          BufNum( Hb, Eb.N );
          BufPut( Hb, @Eb.D[ 0 ], Eb.N );
          end;
        end;

      NameBuf.N := 0; SetLength( NameBuf.D, 0 );
      BufByte( NameBuf, 0 ); // External
      for i := 0 to NumItems-1 do
        begin
        W := FItems[ Order[ i ] ].Name;
        for j := 1 to Length( W ) do // 7z stores '/' as path separator (7-Zip shows a stored '\' as '_')
          if ( W[ j ] = '\' ) then
            W[ j ] := '/';
        if ( Length( W ) > 0 ) then
          BufPut( NameBuf, PWideChar( W ), Length( W )*2 );
        BufByte( NameBuf, 0 );
        BufByte( NameBuf, 0 );
        end;
      BufByte( Hb, kName );
      BufNum( Hb, NameBuf.N );
      BufPut( Hb, @NameBuf.D[ 0 ], NameBuf.N );

      BufByte( Hb, kCTime );
      BufNum( Hb, 2+8*NumItems );
      BufByte( Hb, 1 ); // all defined
      BufByte( Hb, 0 ); // External
      for i := 0 to NumItems-1 do
        BufPut( Hb, @FItems[ Order[ i ] ].CTime, 8 );

      BufByte( Hb, kMTime );
      BufNum( Hb, 2+8*NumItems );
      BufByte( Hb, 1 );
      BufByte( Hb, 0 );
      for i := 0 to NumItems-1 do
        BufPut( Hb, @FItems[ Order[ i ] ].MTime, 8 );

      BufByte( Hb, kWinAttributes );
      BufNum( Hb, 2+4*NumItems );
      BufByte( Hb, 1 );
      BufByte( Hb, 0 );
      for i := 0 to NumItems-1 do
        if FItems[ Order[ i ] ].IsDir then
          BufU32( Hb, FItems[ Order[ i ] ].Attrib or FILE_ATTRIBUTE_DIRECTORY )
        else
          BufU32( Hb, FItems[ Order[ i ] ].Attrib and not FILE_ATTRIBUTE_DIRECTORY );
      BufByte( Hb, kEnd );
      end;
    BufByte( Hb, kEnd );
    HeaderBytes := BufBytes( Hb );

    // --- optionally LZMA-compress (and encrypt) the header ---
    if ( FPassword <> '' ) and FEncryptHeader then
      Pwd := FPassword
    else
      Pwd := '';
    if FCompressHeader or ( Pwd <> '' ) then
      begin
      SetLength( HF, 1 );
      HF[ 0 ].UnpackCRC := Crc7z( PByte( HeaderBytes ), Length( HeaderBytes ) );
      if FCompressHeader then
        begin
        result := Lzma7zEncode( PByte( HeaderBytes ), Length( HeaderBytes ), 9, -1, -1, 1 shl 20, PL, NextHeader );
        if ( result <> 0 ) then Exit;
        AddCoder( HF[ 0 ], k7zIdLZMA, 1, PL, Length( HeaderBytes ) );
        end
      else
        begin
        SetLength( PL, 0 );
        AddCoder( HF[ 0 ], k7zIdCopy, 1, PL, Length( HeaderBytes ) );
        NextHeader := HeaderBytes;
        end;
      AddPack( HF[ 0 ], 0, NextHeader );
      result := EncryptFolder( HF[ 0 ], Pwd );
      if ( result <> 0 ) then Exit;
      if ( Length( HF[ 0 ].Packed_[ 0 ] ) > 0 ) then
        Dest.WriteBuffer( HF[ 0 ].Packed_[ 0 ][ 0 ], Length( HF[ 0 ].Packed_[ 0 ] ) );
      Eb.N := 0; SetLength( Eb.D, 0 );
      BufByte( Eb, kEncodedHeader );
      WriteStreamsInfo( Eb, HF, PackSize, Sizes, CRCs, False );
      Inc( PackSize, Length( HF[ 0 ].Packed_[ 0 ] ) );
      HeaderBytes := BufBytes( Eb );
      end;

    // --- next header + start header ---
    if ( Length( HeaderBytes ) > 0 ) then
      Dest.WriteBuffer( HeaderBytes[ 0 ], Length( HeaderBytes ) );
    SH[ 0 ] := Ord( '7' ); SH[ 1 ] := Ord( 'z' ); SH[ 2 ] := $BC; SH[ 3 ] := $AF; SH[ 4 ] := $27; SH[ 5 ] := $1C;
    SH[ 6 ] := 0; SH[ 7 ] := 4; // version 0.4
    PInt64( @SH[ 12 ] )^ := PackSize;                    // NextHeaderOffset (from byte 32)
    PInt64( @SH[ 20 ] )^ := Length( HeaderBytes );       // NextHeaderSize
    Crc := Crc7z( PByte( HeaderBytes ), Length( HeaderBytes ) );
    PCardinal( @SH[ 28 ] )^ := Crc;                      // NextHeaderCRC
    Crc := Crc7z( @SH[ 12 ], 20 );
    PCardinal( @SH[ 8 ] )^ := Crc;                       // StartHeaderCRC
    Dest.Position := Start;
    Dest.WriteBuffer( SH, SizeOf( SH ) );
    Dest.Seek( 0, soFromEnd );
    result := 0;
  except
    result := E7Z_IO;
  end;
end;

function T7zWriter.SaveToFile( const FileName : T7zString ) : Integer;
var
  H  : THandle;
  S  : THandleStream;
begin
  H := CreateFileW( PWideChar( FileName ), GENERIC_READ or GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0 );
  if ( H = INVALID_HANDLE_VALUE ) then
    begin
    result := E7Z_IO;
    Exit;
    end;
  S := THandleStream.Create( H );
  try
    result := SaveToStream( S );
  finally
    S.Free;
    CloseHandle( H );
  end;
  if ( result <> 0 ) then
    DeleteFileW( PWideChar( FileName ) ); // no half-written archive
end;

end.
