unit SevenZipIn;

// Reading 7z archives without 7z.dll.
//
// Header parsing, file list and CRC checks: 7zArcIn.c of the LZMA SDK (C objects).
// Folder decoding: SzAr_DecodeFolder is implemented HERE in Pascal and satisfies
// the reference from 7zArcIn.c - instead of 7zDec.c. That way every coder graph
// 7z writes can be handled, including AES (unit SevenZipAES hooks in) and an
// encrypted header (-mhe), which 7zDec.c rejects.
//
// Supported coders: Copy, LZMA, LZMA2, BCJ (x86), BCJ2, ARM64, ARM, ARMT, PPC,
// SPARC, IA64, RISCV, Delta, AES-256 (with SevenZipAES). Not: PPMd, Deflate,
// BZip2 (SZ_ERROR_UNSUPPORTED).
//
// Return values: 0 = OK, negative = -SZ_ERROR_* or one of the E7Z_* codes.

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_CAST OFF}

{$I LZMA.inc}

uses
  Windows, SysUtils, Classes, Types, LzmaTypes;

const
  E7Z_PASSWORD = -1000; // encrypted content: password missing or wrong
  E7Z_INDEX    = -1001; // item index out of range
  E7Z_NOTOPEN  = -1002; // no archive open
  E7Z_IO       = -1003; // writing the output failed

  k7zIdCopy  = $00;
  k7zIdDelta = $03;
  k7zIdLZMA  = $030101;
  k7zIdLZMA2 = $21;
  k7zIdPPMD  = $030401;
  k7zIdBCJ   = $03030103;
  k7zIdBCJ2  = $0303011B;
  k7zIdPPC   = $03030205;
  k7zIdIA64  = $03030401;
  k7zIdARM   = $03030501;
  k7zIdARMT  = $03030701;
  k7zIdSPARC = $03030805;
  k7zIdARM64 = $0A;
  k7zIdRISCV = $0B;
  k7zIdAES   = $06F10701;

type
  {$IF CompilerVersion >= 20}
  T7zString = UnicodeString;
  {$ELSE}
  T7zString = WideString;
  {$IFEND}

  // ---- C structures of 7z.h (layout checked in Tests\pSizes.dpr) ----
  TCSzData = record
    Data : PByte;
    Size : NativeUInt;
  end;

  // Folder description, parsed in Pascal (SzGetNextFolderItem of the SDK allows only 4 coders;
  // 7-Zip writes 8 for BCJ2 + AES: BCJ2, LZMA2, LZMA, LZMA and one AES per packed stream)
  T7zCoderInfo = record
    PropsOffset : NativeUInt;
    MethodID    : Cardinal;
    NumStreams  : Cardinal;
    PropsSize   : Cardinal;
  end;

  T7zBond = record
    InIndex  : Cardinal;
    OutIndex : Cardinal;
  end;

const
  k7zFolderMaxCoders  = 16;
  k7zFolderMaxStreams = 32;

type
  T7zFolder = record
    NumCoders      : Cardinal;
    NumBonds       : Cardinal;
    NumPackStreams : Cardinal;
    UnpackStream   : Cardinal;
    PackStreams    : array [ 0..k7zFolderMaxStreams-1 ] of Cardinal;
    Bonds          : array [ 0..k7zFolderMaxCoders-1 ] of T7zBond;
    Coders         : array [ 0..k7zFolderMaxCoders-1 ] of T7zCoderInfo;
  end;

  TCNtfsFileTime = record
    Low, High : Cardinal;
  end;
  PCNtfsFileTime = ^TCNtfsFileTime;

  TCSzBitUi32s = record
    Defs : PByte;
    Vals : PCardinal;
  end;

  TCSzBitUi64s = record
    Defs : PByte;
    Vals : PCNtfsFileTime;
  end;

  PInt64Array = ^TInt64Array;
  TInt64Array = array [ 0..MaxInt div 16 ] of Int64;
  PCardinalArray = ^TCardinalArray;
  TCardinalArray = array [ 0..MaxInt div 8 ] of Cardinal;
  PNativeUIntArray = ^TNativeUIntArray;
  TNativeUIntArray = array [ 0..MaxInt div 16 ] of NativeUInt;
  PByteArray7z = ^TByteArray7z;
  TByteArray7z = array [ 0..MaxInt-1 ] of Byte;
  PCNtfsFileTimeArray = ^TCNtfsFileTimeArray;
  TCNtfsFileTimeArray = array [ 0..MaxInt div 16 ] of TCNtfsFileTime;

  PCSzAr = ^TCSzAr;
  TCSzAr = record
    NumPackStreams          : Cardinal;
    NumFolders              : Cardinal;
    PackPositions           : PInt64Array;      // NumPackStreams + 1
    FolderCRCs              : TCSzBitUi32s;     // NumFolders
    FoCodersOffsets         : PNativeUIntArray; // NumFolders + 1
    FoStartPackStreamIndex  : PCardinalArray;   // NumFolders + 1
    FoToCoderUnpackSizes    : PCardinalArray;   // NumFolders + 1
    FoToMainUnpackSizeIndex : PByteArray7z;     // NumFolders
    CoderUnpackSizes        : PInt64Array;
    CodersData              : PByteArray7z;
    RangeLimit              : Int64;
  end;

  TCSzArEx = record
    db                  : TCSzAr;
    startPosAfterHeader : Int64;
    dataPos             : Int64;
    NumFiles            : Cardinal;
    UnpackPositions     : PInt64Array;   // NumFiles + 1
    IsDirs              : PByteArray7z;
    CRCs                : TCSzBitUi32s;
    Attribs             : TCSzBitUi32s;
    MTime               : TCSzBitUi64s;
    CTime               : TCSzBitUi64s;
    FolderToFile        : PCardinalArray;
    FileToFolder        : PCardinalArray;
    FileNameOffsets     : PNativeUIntArray;
    FileNames           : PByteArray7z;
  end;

  PISeekInStream = ^TISeekInStream;
  TISeekInStream = record
    Read : function( p : PISeekInStream; buf : Pointer; var size : NativeUInt ) : Integer; cdecl;
    Seek : function( p : PISeekInStream; var pos : Int64; origin : Integer ) : Integer; cdecl;
  end;

  TILookInStream = record
    Look : Pointer;
    Skip : Pointer;
    Read : Pointer;
    Seek : Pointer;
  end;

  TCLookToRead2 = record
    vt         : TILookInStream;
    realStream : PISeekInStream;
    pos        : NativeUInt;
    size       : NativeUInt;
    buf        : PByte;
    bufSize    : NativeUInt;
  end;

  // ISeekInStream over a TStream (vt first: C passes a pointer to it)
  TSeekInStreamTStream = record
    vt     : TISeekInStream;
    Stream : TStream;
  end;

  // AES hook (unit SevenZipAES): decrypt Data in place; DataLen is a multiple of 16
  T7zAesDecodeProc = function( Props : PByte; PropsSize : Cardinal; Data : PByte; DataLen : NativeUInt;
    Password : PWideChar; PasswordLen : Integer ) : Integer;

  T7zItem = record
    Name      : T7zString;
    Size      : Int64;
    IsDir     : Boolean;
    HasCRC    : Boolean;
    CRC       : Cardinal;
    HasAttrib : Boolean;
    Attrib    : Cardinal;
    HasMTime  : Boolean;
    MTime     : TFileTime;
    HasCTime  : Boolean;
    CTime     : TFileTime;
    Folder    : Integer; // -1 = empty file / directory
  end;

  T7zReader = class
  private
    FDb         : TCSzArEx;
    FSeek       : TSeekInStreamTStream;
    FLook       : TCLookToRead2;
    FLookBuf    : array of Byte;
    FStream     : TStream;
    FOwnsStream : Boolean;
    FOpen       : Boolean;
    FPassword   : T7zString;
    FAesUsed    : Boolean;
    // solid block cache of SzArEx_Extract
    FBlockIndex : Cardinal;
    FOutBuffer  : PByte;
    FOutSize    : NativeUInt;
    function GetCount : Integer;
    function MapError( Res : Integer ) : Integer;
  public
    destructor Destroy; override;
    function Open( Stream : TStream; const Password : T7zString = ''; OwnsStream : Boolean = False ) : Integer;
    function OpenFile( const FileName : T7zString; const Password : T7zString = '' ) : Integer;
    function OpenMemory( Data : Pointer; Len : NativeUInt; const Password : T7zString = '' ) : Integer;
    procedure Close;
    function Item( Index : Integer ) : T7zItem;
    function IndexOf( const Name : T7zString ) : Integer; // case-insensitive, '\' or '/'
    function Extract( Index : Integer; Dest : TStream ) : Integer;
    // Data points into the solid block cache: valid until the next Extract/Close
    function ExtractToMemory( Index : Integer; out Data : PByte; out Len : NativeUInt ) : Integer;
    function ExtractToDir( Index : Integer; const Dir : T7zString ) : Integer; overload;
    function ExtractToDir( const Dir : T7zString ) : Integer; overload; // all items
    property Count : Integer read GetCount;
    property Password : T7zString read FPassword write FPassword;
    property IsOpen : Boolean read FOpen;
  end;

  // AES hook for SevenZipOut (unit SevenZipAES): encrypt Data in place (Len multiple of 16),
  // return the coder props (random IV, NumCyclesPower 19, no salt - like 7-Zip)
  T7zAesEncodeProc = function( Data : PByte; Len : NativeUInt; Password : PWideChar; PasswordLen : Integer;
    out Props : TByteDynArray ) : Integer;

var
  Sz7zAesDecode : T7zAesDecodeProc = nil;
  Sz7zAesEncode : T7zAesEncodeProc = nil;

// FILETIME (UTC) -> TDateTime (local time)
function FileTimeToDateTime7z( const FT : TFileTime ) : TDateTime;

// Low level (7zArcIn.c / 7zCrc.c)
{$IFDEF UNDERSCORE}
procedure _SzArEx_Init( var p : TCSzArEx ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_Init'{$IFEND};
procedure _SzArEx_Free( var p : TCSzArEx; alloc : PISzAlloc ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_Free'{$IFEND};
function _SzArEx_Open( var p : TCSzArEx; inStream : Pointer; allocMain, allocTemp : PISzAlloc ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_Open'{$IFEND};
function _SzArEx_Extract( const db : TCSzArEx; inStream : Pointer; fileIndex : Cardinal; var blockIndex : Cardinal; var outBuffer : PByte; var outBufferSize : NativeUInt; var offset : NativeUInt; var outSizeProcessed : NativeUInt; allocMain, allocTemp : PISzAlloc ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_Extract'{$IFEND};
function _SzArEx_GetFileNameUtf16( const p : TCSzArEx; fileIndex : NativeUInt; dest : PWideChar ) : NativeUInt; cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_GetFileNameUtf16'{$IFEND};
procedure _CrcGenerateTable; cdecl; external {$IF CompilerVersion > 22}name _PU + 'CrcGenerateTable'{$IFEND};
function _CrcCalc( data : Pointer; size : NativeUInt ) : Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'CrcCalc'{$IFEND};
function _CrcUpdate( crc : Cardinal; data : Pointer; size : NativeUInt ) : Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'CrcUpdate'{$IFEND};
procedure _Delta_Init( state : PByte ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Delta_Init'{$IFEND};
procedure _Delta_Decode( state : PByte; delta : Cardinal; data : PByte; size : NativeUInt ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Delta_Decode'{$IFEND};
procedure _Delta_Encode( state : PByte; delta : Cardinal; data : PByte; size : NativeUInt ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Delta_Encode'{$IFEND};
{$ELSE}
procedure SzArEx_Init( var p : TCSzArEx ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_Init'{$IFEND};
procedure SzArEx_Free( var p : TCSzArEx; alloc : PISzAlloc ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_Free'{$IFEND};
function SzArEx_Open( var p : TCSzArEx; inStream : Pointer; allocMain, allocTemp : PISzAlloc ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_Open'{$IFEND};
function SzArEx_Extract( const db : TCSzArEx; inStream : Pointer; fileIndex : Cardinal; var blockIndex : Cardinal; var outBuffer : PByte; var outBufferSize : NativeUInt; var offset : NativeUInt; var outSizeProcessed : NativeUInt; allocMain, allocTemp : PISzAlloc ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_Extract'{$IFEND};
function SzArEx_GetFileNameUtf16( const p : TCSzArEx; fileIndex : NativeUInt; dest : PWideChar ) : NativeUInt; cdecl; external {$IF CompilerVersion > 22}name _PU + 'SzArEx_GetFileNameUtf16'{$IFEND};
procedure CrcGenerateTable; cdecl; external {$IF CompilerVersion > 22}name _PU + 'CrcGenerateTable'{$IFEND};
function CrcCalc( data : Pointer; size : NativeUInt ) : Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'CrcCalc'{$IFEND};
function CrcUpdate( crc : Cardinal; data : Pointer; size : NativeUInt ) : Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'CrcUpdate'{$IFEND};
procedure Delta_Init( state : PByte ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Delta_Init'{$IFEND};
procedure Delta_Decode( state : PByte; delta : Cardinal; data : PByte; size : NativeUInt ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Delta_Decode'{$IFEND};
procedure Delta_Encode( state : PByte; delta : Cardinal; data : PByte; size : NativeUInt ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Delta_Encode'{$IFEND};
{$ENDIF}

// Pascal implementation of 7zDec.c's SzAr_DecodeFolder, called from 7zArcIn.c
{$IFDEF UNDERSCORE}
function _SzAr_DecodeFolder( p : PCSzAr; folderIndex : Cardinal; stream : Pointer; startPos : Int64;
  outBuffer : PByte; outSize : NativeUInt; allocMain : PISzAlloc ) : Integer; cdecl;
{$ELSE}
function SzAr_DecodeFolder( p : PCSzAr; folderIndex : Cardinal; stream : Pointer; startPos : Int64;
  outBuffer : PByte; outSize : NativeUInt; allocMain : PISzAlloc ) : Integer; cdecl;
{$ENDIF}

// CRC32 as used by 7z (table/hardware code of the SDK)
function Crc7z( Data : Pointer; Size : NativeUInt ) : Cardinal;
function Crc7zUpdate( Crc : Cardinal; Data : Pointer; Size : NativeUInt ) : Cardinal; // Crc starts with $FFFFFFFF, result xor $FFFFFFFF

implementation

uses
  LzmaDec, Lzma2Dec, Bra, Bcj2, LZMAExe;

{$ifdef Win32}
  {$L Win32\7zArcIn.obj}
  {$L Win32\7zCrc.obj}
  {$L Win32\7zCrcOpt.obj}
  {$L Win32\7zBuf.obj}
  {$L Win32\Delta.obj}
{$else}
  {$L Win64\7zArcIn.o}
  {$L Win64\7zCrc.o}
  {$L Win64\7zCrcOpt.o}
  {$L Win64\7zBuf.o}
  {$L Win64\Delta.o}
{$endif}

threadvar
  // set by T7zReader around every call into 7zArcIn.c (SzAr_DecodeFolder has no user context)
  GPasswordPtr : PWideChar;
  GPasswordLen : Integer;
  GAesUsed     : Boolean;

function Crc7z( Data : Pointer; Size : NativeUInt ) : Cardinal;
begin
  result := {$IFDEF UNDERSCORE}_CrcCalc{$ELSE}CrcCalc{$ENDIF}( Data, Size );
end;

function Crc7zUpdate( Crc : Cardinal; Data : Pointer; Size : NativeUInt ) : Cardinal;
begin
  result := {$IFDEF UNDERSCORE}_CrcUpdate{$ELSE}CrcUpdate{$ENDIF}( Crc, Data, Size );
end;

function FileTimeToDateTime7z( const FT : TFileTime ) : TDateTime;
var
  L  : TFileTime;
  ST : TSystemTime;
begin
  result := 0;
  if FileTimeToLocalFileTime( FT, L ) and FileTimeToSystemTime( L, ST ) then
    result := SystemTimeToDateTime( ST );
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Folder decoding (replaces 7zDec.c)
// Port of SzGetNextFolderItem (7zArcIn.c) with higher limits
function ReadNumber7z( var sd : TCSzData; out V : Int64 ) : Integer;
var
  First, Mask : Byte;
  i : Integer;
begin
  result := SZ_ERROR_ARCHIVE;
  V := 0;
  if ( sd.Size = 0 ) then
    Exit;
  First := sd.Data^;
  Inc( sd.Data );
  Dec( sd.Size );
  Mask := $80;
  for i := 0 to 7 do
    begin
    if ( First and Mask = 0 ) then
      begin
      V := V or ( Int64( First and ( Mask-1 ) ) shl ( 8*i ) );
      result := SZ_OK;
      Exit;
      end;
    if ( sd.Size = 0 ) then
      Exit;
    V := V or ( Int64( sd.Data^ ) shl ( 8*i ) );
    Inc( sd.Data );
    Dec( sd.Size );
    Mask := Mask shr 1;
    end;
  result := SZ_OK;
end;

function ReadNum32( var sd : TCSzData; out V : Cardinal ) : Integer;
var
  X : Int64;
begin
  result := ReadNumber7z( sd, X );
  if ( result = SZ_OK ) and ( ( X < 0 ) or ( X > $7FFFFFFF ) ) then
    result := SZ_ERROR_UNSUPPORTED;
  V := Cardinal( X );
end;

function ParseFolder7z( var F : T7zFolder; var sd : TCSzData ) : Integer;
var
  Start : PByte;
  i, j, IdSize : Cardinal;
  MainByte : Byte;
  Id : Int64;
  NumIn, n : Cardinal;
  k : Integer;
  StreamUsed : array [ 0..k7zFolderMaxStreams-1 ] of Boolean;
  CoderUsed  : array [ 0..k7zFolderMaxCoders-1 ] of Boolean;
begin
  FillChar( F, SizeOf( F ), 0 );
  Start := sd.Data;
  result := ReadNum32( sd, F.NumCoders );
  if ( result <> SZ_OK ) then Exit;
  result := SZ_ERROR_UNSUPPORTED;
  if ( F.NumCoders = 0 ) or ( F.NumCoders > k7zFolderMaxCoders ) then Exit;
  NumIn := 0;
  for i := 0 to F.NumCoders-1 do
    begin
    result := SZ_ERROR_ARCHIVE;
    if ( sd.Size = 0 ) then Exit;
    MainByte := sd.Data^;
    Inc( sd.Data ); Dec( sd.Size );
    result := SZ_ERROR_UNSUPPORTED;
    if ( MainByte and $C0 <> 0 ) then Exit;
    IdSize := MainByte and $0F;
    if ( IdSize > 8 ) then Exit;
    result := SZ_ERROR_ARCHIVE;
    if ( IdSize > sd.Size ) then Exit;
    Id := 0;
    for j := 1 to IdSize do
      begin
      Id := ( Id shl 8 ) or sd.Data^;
      Inc( sd.Data ); Dec( sd.Size );
      end;
    result := SZ_ERROR_UNSUPPORTED;
    if ( Id < 0 ) or ( Id > $FFFFFFFF ) then Exit;
    F.Coders[ i ].MethodID := Cardinal( Id );
    F.Coders[ i ].NumStreams := 1;
    if ( MainByte and $10 <> 0 ) then
      begin
      result := ReadNum32( sd, F.Coders[ i ].NumStreams );
      if ( result <> SZ_OK ) then Exit;
      result := ReadNum32( sd, n );
      if ( result <> SZ_OK ) then Exit;
      result := SZ_ERROR_UNSUPPORTED;
      if ( n <> 1 ) or ( F.Coders[ i ].NumStreams > k7zFolderMaxStreams ) then Exit;
      end;
    Inc( NumIn, F.Coders[ i ].NumStreams );
    result := SZ_ERROR_UNSUPPORTED;
    if ( NumIn > k7zFolderMaxStreams ) then Exit;
    if ( MainByte and $20 <> 0 ) then
      begin
      result := ReadNum32( sd, n );
      if ( result <> SZ_OK ) then Exit;
      result := SZ_ERROR_ARCHIVE;
      if ( n > sd.Size ) then Exit;
      F.Coders[ i ].PropsOffset := NativeUInt( PAnsiChar( sd.Data )-PAnsiChar( Start ) );
      F.Coders[ i ].PropsSize := n;
      Inc( sd.Data, n ); Dec( sd.Size, n );
      end;
    end;

  F.NumBonds := F.NumCoders-1;
  result := SZ_ERROR_ARCHIVE;
  if ( NumIn < F.NumBonds ) then Exit;
  F.NumPackStreams := NumIn-F.NumBonds;
  FillChar( StreamUsed, SizeOf( StreamUsed ), 0 );
  FillChar( CoderUsed, SizeOf( CoderUsed ), 0 );
  for k := 0 to Integer( F.NumBonds )-1 do
    begin
    result := ReadNum32( sd, F.Bonds[ k ].InIndex );
    if ( result <> SZ_OK ) then Exit;
    result := SZ_ERROR_ARCHIVE;
    if ( F.Bonds[ k ].InIndex >= NumIn ) or StreamUsed[ F.Bonds[ k ].InIndex ] then Exit;
    StreamUsed[ F.Bonds[ k ].InIndex ] := True;
    result := ReadNum32( sd, F.Bonds[ k ].OutIndex );
    if ( result <> SZ_OK ) then Exit;
    result := SZ_ERROR_ARCHIVE;
    if ( F.Bonds[ k ].OutIndex >= F.NumCoders ) or CoderUsed[ F.Bonds[ k ].OutIndex ] then Exit;
    CoderUsed[ F.Bonds[ k ].OutIndex ] := True;
    end;
  F.UnpackStream := 0;
  while CoderUsed[ F.UnpackStream ] do
    begin
    Inc( F.UnpackStream );
    result := SZ_ERROR_ARCHIVE;
    if ( F.UnpackStream >= F.NumCoders ) then Exit;
    end;
  if ( F.NumPackStreams = 1 ) then
    begin
    i := 0;
    while StreamUsed[ i ] do
      begin
      Inc( i );
      result := SZ_ERROR_ARCHIVE;
      if ( i >= NumIn ) then Exit;
      end;
    F.PackStreams[ 0 ] := i;
    end
  else
    for i := 0 to F.NumPackStreams-1 do
      begin
      result := ReadNum32( sd, n );
      if ( result <> SZ_OK ) then Exit;
      result := SZ_ERROR_ARCHIVE;
      if ( n >= NumIn ) or StreamUsed[ n ] then Exit;
      StreamUsed[ n ] := True;
      F.PackStreams[ i ] := n;
      end;
  result := SZ_OK;
end;

type
  TFolderCtx = record
    F            : T7zFolder;
    Props        : PByte;              // coder props base (CodersData of the folder)
    UnpackSizes  : PInt64Array;        // per coder
    PackPos      : PInt64Array;        // pack positions of the folder (relative)
    Stream       : Pointer;            // ILookInStream
    StartPos     : Int64;
    InStart      : array [ 0..k7zFolderMaxCoders-1 ] of Cardinal; // first in-stream index per coder
  end;

function DecodeCoder( var Ctx : TFolderCtx; c : Cardinal; Dest : PByte; DestSize : NativeUInt ) : Integer; forward;

// Get the data of in-stream si (packed stream or output of a bonded coder)
function GetInStream( var Ctx : TFolderCtx; si : Cardinal; out P : PByte; out Size : NativeUInt ) : Integer;
var
  k   : Integer; // Integer: NumBonds can be 0 (Cardinal loop to 0-1 would run 4 billion times)
  Sz  : Int64;
begin
  P := nil;
  Size := 0;
  for k := 0 to Integer( Ctx.F.NumPackStreams )-1 do
    if ( Ctx.F.PackStreams[ k ] = si ) then
      begin
      Sz := Ctx.PackPos^[ k+1 ]-Ctx.PackPos^[ k ];
      if ( Sz < 0 ) or ( Sz > MaxInt ) then
        begin
        result := SZ_ERROR_MEM;
        Exit;
        end;
      Size := Sz;
      GetMem( P, Size+1 );
      result := {$IFDEF UNDERSCORE}_LookInStream_SeekTo{$ELSE}LookInStream_SeekTo{$ENDIF}( Ctx.Stream, Ctx.StartPos+Ctx.PackPos^[ k ] );
      if ( result = SZ_OK ) and ( Size > 0 ) then
        result := {$IFDEF UNDERSCORE}_LookInStream_Read{$ELSE}LookInStream_Read{$ENDIF}( Ctx.Stream, P, Size );
      if ( result <> SZ_OK ) then
        begin
        FreeMem( P );
        P := nil;
        end;
      Exit;
      end;

  for k := 0 to Integer( Ctx.F.NumBonds )-1 do
    if ( Ctx.F.Bonds[ k ].InIndex = si ) then
      begin
      Sz := Ctx.UnpackSizes^[ Ctx.F.Bonds[ k ].OutIndex ];
      if ( Sz < 0 ) or ( Sz > MaxInt ) then
        begin
        result := SZ_ERROR_MEM;
        Exit;
        end;
      Size := Sz;
      GetMem( P, Size+1 );
      result := DecodeCoder( Ctx, Ctx.F.Bonds[ k ].OutIndex, P, Size );
      if ( result <> SZ_OK ) then
        begin
        FreeMem( P );
        P := nil;
        end;
      Exit;
      end;

  result := SZ_ERROR_ARCHIVE;
end;

function BranchDecode( MethodID : Cardinal; Data : PByte; Size : NativeUInt; Pc : Cardinal ) : Boolean;
var
  State : Cardinal;
begin
  result := True;
  State := 0;
  case MethodID of
    k7zIdBCJ   : {$IFDEF UNDERSCORE}_z7_BranchConvSt_X86_Dec{$ELSE}z7_BranchConvSt_X86_Dec{$ENDIF}( Data, Size, Pc, State );
    k7zIdARM64 : {$IFDEF UNDERSCORE}_z7_BranchConv_ARM64_Dec{$ELSE}z7_BranchConv_ARM64_Dec{$ENDIF}( Data, Size, Pc );
    k7zIdARM   : {$IFDEF UNDERSCORE}_z7_BranchConv_ARM_Dec{$ELSE}z7_BranchConv_ARM_Dec{$ENDIF}( Data, Size, Pc );
    k7zIdARMT  : {$IFDEF UNDERSCORE}_z7_BranchConv_ARMT_Dec{$ELSE}z7_BranchConv_ARMT_Dec{$ENDIF}( Data, Size, Pc );
    k7zIdPPC   : {$IFDEF UNDERSCORE}_z7_BranchConv_PPC_Dec{$ELSE}z7_BranchConv_PPC_Dec{$ENDIF}( Data, Size, Pc );
    k7zIdSPARC : {$IFDEF UNDERSCORE}_z7_BranchConv_SPARC_Dec{$ELSE}z7_BranchConv_SPARC_Dec{$ENDIF}( Data, Size, Pc );
    k7zIdIA64  : {$IFDEF UNDERSCORE}_z7_BranchConv_IA64_Dec{$ELSE}z7_BranchConv_IA64_Dec{$ENDIF}( Data, Size, Pc );
    k7zIdRISCV : {$IFDEF UNDERSCORE}_z7_BranchConv_RISCV_Dec{$ELSE}z7_BranchConv_RISCV_Dec{$ENDIF}( Data, Size, Pc );
  else
    result := False;
  end;
end;

function DecodeCoder( var Ctx : TFolderCtx; c : Cardinal; Dest : PByte; DestSize : NativeUInt ) : Integer;
var
  Coder  : T7zCoderInfo;
  Props  : PByte;
  Src    : PByte;
  SrcLen : NativeUInt;
  DLen, SLen : NativeInt;
  Status : ELzmaStatus;
  S      : TBcj2Streams;
  i      : Integer;
  P      : array [ 0..3 ] of PByte;
  L      : array [ 0..3 ] of NativeUInt;
  DeltaState : array [ 0..255 ] of Byte;
  Pc     : Cardinal;
begin
  Coder := Ctx.F.Coders[ c ];
  Props := PByte( PAnsiChar( Ctx.Props )+Coder.PropsOffset );

  if ( Coder.MethodID = k7zIdBCJ2 ) then
    begin
    if ( Coder.NumStreams <> 4 ) then
      begin
      result := SZ_ERROR_UNSUPPORTED;
      Exit;
      end;
    for i := 0 to 3 do
      P[ i ] := nil;
    result := SZ_OK;
    for i := 0 to 3 do
      begin
      result := GetInStream( Ctx, Ctx.InStart[ c ]+Cardinal( i ), P[ i ], L[ i ] );
      if ( result <> SZ_OK ) then
        Break;
      end;
    if ( result = SZ_OK ) then
      begin
      for i := 0 to 3 do
        begin
        SetLength( S[ i ], L[ i ] );
        if ( L[ i ] > 0 ) then
          Move( P[ i ]^, S[ i ][ 0 ], L[ i ] );
        end;
      if not Bcj2Decode( S, Dest, DestSize ) then
        result := SZ_ERROR_DATA;
      end;
    for i := 0 to 3 do
      if ( P[ i ] <> nil ) then
        FreeMem( P[ i ] );
    Exit;
    end;

  if ( Coder.NumStreams <> 1 ) then
    begin
    result := SZ_ERROR_UNSUPPORTED;
    Exit;
    end;

  result := GetInStream( Ctx, Ctx.InStart[ c ], Src, SrcLen );
  if ( result <> SZ_OK ) then
    Exit;
  try
    case Coder.MethodID of
      k7zIdCopy :
        if ( SrcLen <> DestSize ) then
          result := SZ_ERROR_DATA
        else if ( DestSize > 0 ) then
          Move( Src^, Dest^, DestSize );

      k7zIdLZMA :
        begin
        DLen := DestSize;
        SLen := SrcLen;
        result := {$IFDEF UNDERSCORE}_LzmaDecode{$ELSE}LzmaDecode{$ENDIF}( Dest, DLen, Src, SLen, Props, Coder.PropsSize, LZMA_FINISH_END, Status, TISzAllocDefault );
        if ( result = SZ_OK ) and ( NativeUInt( DLen ) <> DestSize ) then
          result := SZ_ERROR_DATA;
        if ( result = SZ_ERROR_INPUT_EOF ) then
          result := SZ_ERROR_DATA;
        end;

      k7zIdLZMA2 :
        begin
        if ( Coder.PropsSize <> 1 ) then
          result := SZ_ERROR_UNSUPPORTED
        else
          begin
          DLen := DestSize;
          SLen := SrcLen;
          result := {$IFDEF UNDERSCORE}_Lzma2Decode{$ELSE}Lzma2Decode{$ENDIF}( Dest^, DLen, Src^, SLen, Props^, LZMA_FINISH_END, Status, TISzAllocDefault );
          if ( result = SZ_OK ) and ( NativeUInt( DLen ) <> DestSize ) then
            result := SZ_ERROR_DATA;
          if ( result = SZ_ERROR_INPUT_EOF ) then
            result := SZ_ERROR_DATA;
          end;
        end;

      k7zIdDelta :
        if ( Coder.PropsSize <> 1 ) or ( SrcLen <> DestSize ) then
          result := SZ_ERROR_UNSUPPORTED
        else
          begin
          Move( Src^, Dest^, DestSize );
          {$IFDEF UNDERSCORE}_Delta_Init{$ELSE}Delta_Init{$ENDIF}( @DeltaState[ 0 ] );
          {$IFDEF UNDERSCORE}_Delta_Decode{$ELSE}Delta_Decode{$ENDIF}( @DeltaState[ 0 ], Cardinal( Props^ )+1, Dest, DestSize );
          end;

      k7zIdAES :
        begin
        GAesUsed := True;
        if not Assigned( Sz7zAesDecode ) then
          result := SZ_ERROR_UNSUPPORTED
        else if ( GPasswordLen = 0 ) then
          result := SZ_ERROR_DATA
        else if ( SrcLen mod 16 <> 0 ) or ( SrcLen < DestSize ) then
          result := SZ_ERROR_DATA
        else
          begin
          result := Sz7zAesDecode( Props, Coder.PropsSize, Src, SrcLen, GPasswordPtr, GPasswordLen );
          if ( result = SZ_OK ) and ( DestSize > 0 ) then
            Move( Src^, Dest^, DestSize );
          end;
        end;
    else
      if ( Coder.MethodID = k7zIdBCJ ) or ( Coder.MethodID = k7zIdARM64 ) or ( Coder.MethodID = k7zIdARM ) or
         ( Coder.MethodID = k7zIdARMT ) or ( Coder.MethodID = k7zIdPPC ) or ( Coder.MethodID = k7zIdSPARC ) or
         ( Coder.MethodID = k7zIdIA64 ) or ( Coder.MethodID = k7zIdRISCV ) then
        begin
        Pc := 0;
        if ( Coder.PropsSize = 4 ) then
          Pc := PCardinal( Props )^ // optional start address
        else if ( Coder.PropsSize <> 0 ) then
          begin
          result := SZ_ERROR_UNSUPPORTED;
          Exit;
          end;
        if ( SrcLen <> DestSize ) then
          result := SZ_ERROR_DATA
        else
          begin
          Move( Src^, Dest^, DestSize );
          BranchDecode( Coder.MethodID, Dest, DestSize, Pc );
          end;
        end
      else
        result := SZ_ERROR_UNSUPPORTED; // PPMd, Deflate, BZip2, ...
    end;
  finally
    FreeMem( Src );
  end;
end;

// Called by 7zArcIn.c (SzArEx_Open for packed headers, SzArEx_Extract)
function SzAr_DecodeFolder_( p : PCSzAr; folderIndex : Cardinal; stream : Pointer; startPos : Int64;
  outBuffer : PByte; outSize : NativeUInt; allocMain : PISzAlloc ) : Integer;
var
  Ctx : TFolderCtx;
  sd  : TCSzData;
  i   : Cardinal;
  n   : Cardinal;
begin
  try
    FillChar( Ctx, SizeOf( Ctx ), 0 );
    sd.Data := PByte( PAnsiChar( p^.CodersData )+p^.FoCodersOffsets^[ folderIndex ] );
    sd.Size := p^.FoCodersOffsets^[ folderIndex+1 ]-p^.FoCodersOffsets^[ folderIndex ];
    result := ParseFolder7z( Ctx.F, sd );
    if ( result <> SZ_OK ) then
      Exit;
    if ( sd.Size <> 0 ) or ( Ctx.F.NumCoders = 0 ) or ( Ctx.F.NumCoders > k7zFolderMaxCoders ) or ( Ctx.F.UnpackStream >= Ctx.F.NumCoders ) then
      begin
      result := SZ_ERROR_UNSUPPORTED;
      Exit;
      end;
    Ctx.Props       := PByte( PAnsiChar( p^.CodersData )+p^.FoCodersOffsets^[ folderIndex ] );
    Ctx.UnpackSizes := PInt64Array( @p^.CoderUnpackSizes^[ p^.FoToCoderUnpackSizes^[ folderIndex ] ] );
    Ctx.PackPos     := PInt64Array( @p^.PackPositions^[ p^.FoStartPackStreamIndex^[ folderIndex ] ] );
    Ctx.Stream      := stream;
    Ctx.StartPos    := startPos;
    n := 0;
    for i := 0 to Ctx.F.NumCoders-1 do
      begin
      Ctx.InStart[ i ] := n;
      Inc( n, Ctx.F.Coders[ i ].NumStreams );
      end;
    if ( Ctx.UnpackSizes^[ Ctx.F.UnpackStream ] <> Int64( outSize ) ) then
      begin
      result := SZ_ERROR_FAIL;
      Exit;
      end;

    result := DecodeCoder( Ctx, Ctx.F.UnpackStream, outBuffer, outSize );

    if ( result = SZ_OK ) and ( p^.FolderCRCs.Defs <> nil ) and
       ( ( PByteArray7z( p^.FolderCRCs.Defs )^[ folderIndex shr 3 ] and ( $80 shr ( folderIndex and 7 ) ) ) <> 0 ) then
      if ( Crc7z( outBuffer, outSize ) <> PCardinalArray( p^.FolderCRCs.Vals )^[ folderIndex ] ) then
        result := SZ_ERROR_CRC;
  except
    result := SZ_ERROR_FAIL; // never let a Delphi exception cross the C frames
  end;
end;

{$IFDEF UNDERSCORE}
function _SzAr_DecodeFolder( p : PCSzAr; folderIndex : Cardinal; stream : Pointer; startPos : Int64;
  outBuffer : PByte; outSize : NativeUInt; allocMain : PISzAlloc ) : Integer; cdecl;
begin
  result := SzAr_DecodeFolder_( p, folderIndex, stream, startPos, outBuffer, outSize, allocMain );
end;
{$ELSE}
function SzAr_DecodeFolder( p : PCSzAr; folderIndex : Cardinal; stream : Pointer; startPos : Int64;
  outBuffer : PByte; outSize : NativeUInt; allocMain : PISzAlloc ) : Integer; cdecl;
begin
  result := SzAr_DecodeFolder_( p, folderIndex, stream, startPos, outBuffer, outSize, allocMain );
end;
{$ENDIF}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// ISeekInStream over TStream
function SeekInRead( p : PISeekInStream; buf : Pointer; var size : NativeUInt ) : Integer; cdecl;
begin
  try
    if ( size > 0 ) then
      size := TSeekInStreamTStream( Pointer( p )^ ).Stream.Read( buf^, size );
    result := SZ_OK;
  except
    size := 0;
    result := SZ_ERROR_READ;
  end;
end;

function SeekInSeek( p : PISeekInStream; var pos : Int64; origin : Integer ) : Integer; cdecl;
begin
  try
    pos := TSeekInStreamTStream( Pointer( p )^ ).Stream.Seek( pos, TSeekOrigin( origin ) );
    result := SZ_OK;
  except
    result := SZ_ERROR_READ;
  end;
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// T7zReader
type
  THandleStreamOwned7z = class( THandleStream )
  public
    destructor Destroy; override;
  end;

destructor THandleStreamOwned7z.Destroy;
begin
  CloseHandle( Handle );
  inherited;
end;

type
  TMemStream7z = class( TCustomMemoryStream ) // read-only view on caller memory
  public
    constructor Create( Data : Pointer; Len : NativeUInt );
    function Write( const Buffer; Count : Longint ) : Longint; override;
  end;

constructor TMemStream7z.Create( Data : Pointer; Len : NativeUInt );
begin
  inherited Create;
  SetPointer( Data, Len );
end;

function TMemStream7z.Write( const Buffer; Count : Longint ) : Longint;
begin
  result := 0;
end;

destructor T7zReader.Destroy;
begin
  Close;
  inherited;
end;

procedure T7zReader.Close;
begin
  if FOpen then
    {$IFDEF UNDERSCORE}_SzArEx_Free{$ELSE}SzArEx_Free{$ENDIF}( FDb, @TISzAllocDefault );
  FOpen := False;
  if ( FOutBuffer <> nil ) then
    TISzAllocDefault.SzFree( @TISzAllocDefault, FOutBuffer );
  FOutBuffer := nil;
  FOutSize := 0;
  FBlockIndex := $FFFFFFFF;
  if FOwnsStream then
    FStream.Free;
  FStream := nil;
  FOwnsStream := False;
  FAesUsed := False;
end;

function T7zReader.MapError( Res : Integer ) : Integer;
begin
  if ( Res = SZ_OK ) then
    result := 0
  else if FAesUsed and ( ( Res = SZ_ERROR_DATA ) or ( Res = SZ_ERROR_CRC ) or ( Res = SZ_ERROR_ARCHIVE ) or
                          ( Res = SZ_ERROR_UNSUPPORTED ) or ( Res = SZ_ERROR_FAIL ) or ( Res = SZ_ERROR_MEM ) ) then
    result := E7Z_PASSWORD
  else
    result := -Abs( Res );
end;

function T7zReader.Open( Stream : TStream; const Password : T7zString = ''; OwnsStream : Boolean = False ) : Integer;
var
  Res : Integer;
begin
  Close;
  result := -SZ_ERROR_PARAM;
  if ( Stream = nil ) then
    Exit;
  FStream := Stream;
  FOwnsStream := OwnsStream;
  FPassword := Password;

  FSeek.vt.Read := SeekInRead;
  FSeek.vt.Seek := SeekInSeek;
  FSeek.Stream := Stream;
  SetLength( FLookBuf, 1 shl 16 );
  FillChar( FLook, SizeOf( FLook ), 0 );
  {$IFDEF UNDERSCORE}_LookToRead2_CreateVTable{$ELSE}LookToRead2_CreateVTable{$ENDIF}( FLook, 0 );
  FLook.realStream := @FSeek.vt;
  FLook.buf := @FLookBuf[ 0 ];
  FLook.bufSize := Length( FLookBuf );
  FLook.pos := 0;
  FLook.size := 0;
  // the archive starts at the current position (7zArcIn.c takes it as start of the archive),
  // e.g. an archive behind a prefix in a resource or in a bigger file

  {$IFDEF UNDERSCORE}_SzArEx_Init{$ELSE}SzArEx_Init{$ENDIF}( FDb );
  GPasswordPtr := PWideChar( FPassword );
  GPasswordLen := Length( FPassword );
  GAesUsed := False;
  Res := {$IFDEF UNDERSCORE}_SzArEx_Open{$ELSE}SzArEx_Open{$ENDIF}( FDb, @FLook.vt, @TISzAllocDefault, @TISzAllocDefault );
  FAesUsed := GAesUsed;
  GPasswordPtr := nil;
  GPasswordLen := 0;
  if ( Res <> SZ_OK ) then
    begin
    {$IFDEF UNDERSCORE}_SzArEx_Free{$ELSE}SzArEx_Free{$ENDIF}( FDb, @TISzAllocDefault );
    result := MapError( Res );
    if FOwnsStream then
      FStream.Free;
    FStream := nil;
    FOwnsStream := False;
    Exit;
    end;
  FOpen := True;
  FBlockIndex := $FFFFFFFF;
  result := 0;
end;

function T7zReader.OpenFile( const FileName : T7zString; const Password : T7zString = '' ) : Integer;
var
  H : THandle;
begin
  H := CreateFileW( PWideChar( FileName ), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0 );
  if ( H = INVALID_HANDLE_VALUE ) then
    begin
    result := E7Z_IO;
    Exit;
    end;
  result := Open( THandleStreamOwned7z.Create( H ), Password, True );
end;

function T7zReader.OpenMemory( Data : Pointer; Len : NativeUInt; const Password : T7zString = '' ) : Integer;
begin
  result := Open( TMemStream7z.Create( Data, Len ), Password, True );
end;

function T7zReader.GetCount : Integer;
begin
  if FOpen then
    result := FDb.NumFiles
  else
    result := 0;
end;

function BitDefined( Defs : PByte; i : Cardinal ) : Boolean;
begin
  result := ( Defs <> nil ) and ( ( PByteArray7z( Defs )^[ i shr 3 ] and ( $80 shr ( i and 7 ) ) ) <> 0 );
end;

function T7zReader.Item( Index : Integer ) : T7zItem;
var
  n : NativeUInt;
  W : T7zString;
  i : Integer;
begin
  result.Name := '';
  FillChar( result.MTime, SizeOf( result.MTime ), 0 );
  FillChar( result.CTime, SizeOf( result.CTime ), 0 );
  result.Size := 0; result.IsDir := False; result.HasCRC := False; result.CRC := 0;
  result.HasAttrib := False; result.Attrib := 0; result.HasMTime := False; result.HasCTime := False;
  result.Folder := -1;
  if not FOpen or ( Index < 0 ) or ( Cardinal( Index ) >= FDb.NumFiles ) then
    Exit;
  n := {$IFDEF UNDERSCORE}_SzArEx_GetFileNameUtf16{$ELSE}SzArEx_GetFileNameUtf16{$ENDIF}( FDb, Index, nil );
  if ( n > 1 ) then
    begin
    SetLength( W, n-1 );
    {$IFDEF UNDERSCORE}_SzArEx_GetFileNameUtf16{$ELSE}SzArEx_GetFileNameUtf16{$ENDIF}( FDb, Index, PWideChar( W ) ); // writes n chars incl. #0
    for i := 1 to Length( W ) do // 7z stores '/' as separator; Windows style for the caller
      if ( W[ i ] = '/' ) then
        W[ i ] := '\';
    result.Name := W;
    end;
  result.Size  := FDb.UnpackPositions^[ Index+1 ]-FDb.UnpackPositions^[ Index ];
  result.IsDir := BitDefined( PByte( FDb.IsDirs ), Index );
  result.HasCRC := BitDefined( FDb.CRCs.Defs, Index );
  if result.HasCRC then
    result.CRC := PCardinalArray( FDb.CRCs.Vals )^[ Index ];
  result.HasAttrib := BitDefined( FDb.Attribs.Defs, Index );
  if result.HasAttrib then
    result.Attrib := PCardinalArray( FDb.Attribs.Vals )^[ Index ];
  result.HasMTime := BitDefined( FDb.MTime.Defs, Index );
  if result.HasMTime then
    begin
    result.MTime.dwLowDateTime  := PCNtfsFileTimeArray( FDb.MTime.Vals )^[ Index ].Low;
    result.MTime.dwHighDateTime := PCNtfsFileTimeArray( FDb.MTime.Vals )^[ Index ].High;
    end;
  result.HasCTime := BitDefined( FDb.CTime.Defs, Index );
  if result.HasCTime then
    begin
    result.CTime.dwLowDateTime  := PCNtfsFileTimeArray( FDb.CTime.Vals )^[ Index ].Low;
    result.CTime.dwHighDateTime := PCNtfsFileTimeArray( FDb.CTime.Vals )^[ Index ].High;
    end;
  if ( FDb.FileToFolder^[ Index ] <> $FFFFFFFF ) then
    result.Folder := FDb.FileToFolder^[ Index ];
end;

function SameName7z( const A, B : T7zString ) : Boolean;
var
  X, Y : T7zString;
  i    : Integer;
begin
  X := A; Y := B;
  for i := 1 to Length( X ) do if ( X[ i ] = '/' ) then X[ i ] := '\';
  for i := 1 to Length( Y ) do if ( Y[ i ] = '/' ) then Y[ i ] := '\';
  result := ( Length( X ) = Length( Y ) ) and
    ( CompareStringW( $007F {LOCALE_INVARIANT}, NORM_IGNORECASE, PWideChar( X ), Length( X ), PWideChar( Y ), Length( Y ) ) = CSTR_EQUAL );
end;

function T7zReader.IndexOf( const Name : T7zString ) : Integer;
var
  i : Integer;
begin
  result := -1;
  for i := 0 to Count-1 do
    if SameName7z( Item( i ).Name, Name ) then
      begin
      result := i;
      Exit;
      end;
end;

function T7zReader.ExtractToMemory( Index : Integer; out Data : PByte; out Len : NativeUInt ) : Integer;
var
  Offset, Processed : NativeUInt;
  Res : Integer;
begin
  Data := nil;
  Len := 0;
  if not FOpen then
    begin
    result := E7Z_NOTOPEN;
    Exit;
    end;
  if ( Index < 0 ) or ( Cardinal( Index ) >= FDb.NumFiles ) then
    begin
    result := E7Z_INDEX;
    Exit;
    end;
  Offset := 0;
  Processed := 0;
  GPasswordPtr := PWideChar( FPassword );
  GPasswordLen := Length( FPassword );
  GAesUsed := False;
  Res := {$IFDEF UNDERSCORE}_SzArEx_Extract{$ELSE}SzArEx_Extract{$ENDIF}( FDb, @FLook.vt, Index, FBlockIndex, FOutBuffer, FOutSize,
    Offset, Processed, @TISzAllocDefault, @TISzAllocDefault );
  FAesUsed := FAesUsed or GAesUsed;
  GPasswordPtr := nil;
  GPasswordLen := 0;
  if ( Res <> SZ_OK ) then
    begin
    if ( FOutBuffer <> nil ) then // drop a possibly broken cache
      TISzAllocDefault.SzFree( @TISzAllocDefault, FOutBuffer );
    FOutBuffer := nil;
    FOutSize := 0;
    FBlockIndex := $FFFFFFFF;
    result := MapError( Res );
    Exit;
    end;
  if ( Processed > 0 ) then
    Data := PByte( PAnsiChar( FOutBuffer )+Offset );
  Len := Processed;
  result := 0;
end;

function T7zReader.Extract( Index : Integer; Dest : TStream ) : Integer;
var
  P : PByte;
  L : NativeUInt;
begin
  result := ExtractToMemory( Index, P, L );
  if ( result <> 0 ) then
    Exit;
  try
    if ( L > 0 ) then
      Dest.WriteBuffer( P^, L );
  except
    result := E7Z_IO;
  end;
end;

function ForceDirW( const Dir : T7zString ) : Boolean;
var
  i : Integer;
begin
  result := True;
  if ( Dir = '' ) then
    Exit;
  i := Integer( GetFileAttributesW( PWideChar( Dir ) ) );
  if ( i <> -1 ) and ( i and FILE_ATTRIBUTE_DIRECTORY <> 0 ) then
    Exit;
  i := Length( Dir );
  while ( i > 0 ) and ( Dir[ i ] <> '\' ) do
    Dec( i );
  if ( i > 1 ) and ( Dir[ i-1 ] <> ':' ) then
    ForceDirW( Copy( Dir, 1, i-1 ) );
  result := CreateDirectoryW( PWideChar( Dir ), nil ) or ( GetLastError = ERROR_ALREADY_EXISTS );
end;

function SafeRelPath( const Name : T7zString ) : T7zString;
var
  i : Integer;
begin
  // no absolute paths, no drive letters, no '..' components (zip slip)
  result := Name;
  for i := 1 to Length( result ) do
    if ( result[ i ] = '/' ) then
      result[ i ] := '\';
  while ( Length( result ) > 0 ) and ( result[ 1 ] = '\' ) do
    Delete( result, 1, 1 );
  i := Pos( ':', result );
  if ( i > 0 ) then
    Delete( result, 1, i );
  if ( result = '..' ) or ( Pos( '..\', result ) = 1 ) or ( Pos( '\..\', result ) > 0 ) or
     ( Copy( result, Length( result )-2, 3 ) = '\..' ) then
    result := '';
end;

function T7zReader.ExtractToDir( Index : Integer; const Dir : T7zString ) : Integer;
var
  It   : T7zItem;
  Path : T7zString;
  Base : T7zString;
  H    : THandle;
  P    : PByte;
  L    : NativeUInt;
  W    : Cardinal;
  Rel  : T7zString;
  i    : Integer;
begin
  if not FOpen then
    begin
    result := E7Z_NOTOPEN;
    Exit;
    end;
  It := Item( Index );
  if ( Index < 0 ) or ( Index >= Count ) then
    begin
    result := E7Z_INDEX;
    Exit;
    end;
  Rel := SafeRelPath( It.Name );
  if ( Rel = '' ) then
    begin
    result := E7Z_IO;
    Exit;
    end;
  Base := Dir;
  if ( Base <> '' ) and ( Base[ Length( Base ) ] <> '\' ) then
    Base := Base+'\';
  Path := Base+Rel;

  if It.IsDir then
    begin
    if not ForceDirW( Path ) then
      result := E7Z_IO
    else
      result := 0;
    if ( result = 0 ) and It.HasAttrib and ( It.Attrib and $FFFF <> 0 ) then
      SetFileAttributesW( PWideChar( Path ), It.Attrib and $7FFF );
    Exit;
    end;

  i := Length( Path );
  while ( i > 0 ) and ( Path[ i ] <> '\' ) do
    Dec( i );
  if ( i > 0 ) then
    ForceDirW( Copy( Path, 1, i-1 ) );

  result := ExtractToMemory( Index, P, L );
  if ( result <> 0 ) then
    Exit;

  SetFileAttributesW( PWideChar( Path ), FILE_ATTRIBUTE_NORMAL ); // overwrite read-only files
  H := CreateFileW( PWideChar( Path ), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0 );
  if ( H = INVALID_HANDLE_VALUE ) then
    begin
    result := E7Z_IO;
    Exit;
    end;
  try
    while ( L > 0 ) do
      begin
      if ( L > $40000000 ) then W := $40000000 else W := L;
      if not WriteFile( H, P^, W, W, nil ) or ( W = 0 ) then
        begin
        result := E7Z_IO;
        Break;
        end;
      Inc( P, W );
      Dec( L, W );
      end;
    if It.HasMTime then
      if It.HasCTime then
        SetFileTime( H, @It.CTime, nil, @It.MTime )
      else
        SetFileTime( H, nil, nil, @It.MTime );
  finally
    CloseHandle( H );
  end;
  if ( result = 0 ) and It.HasAttrib and ( It.Attrib and $7FFF <> 0 ) then
    SetFileAttributesW( PWideChar( Path ), It.Attrib and $7FFF );
end;

function T7zReader.ExtractToDir( const Dir : T7zString ) : Integer;
var
  i : Integer;
begin
  result := 0;
  for i := 0 to Count-1 do
    begin
    result := ExtractToDir( i, Dir );
    if ( result <> 0 ) then
      Exit;
    end;
end;

initialization
  {$IFDEF UNDERSCORE}_CrcGenerateTable{$ELSE}CrcGenerateTable{$ENDIF};

end.
