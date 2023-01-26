unit LZMA;

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_CAST OFF}

{$I LZMA.inc}

uses
  types;

function CompressLZMA( Source : PByte; Len : Cardinal; var Compressed : TByteDynArray; Header : boolean = False ) : Int64; overload;
function CompressLZMA( Source : PByte; Len : Cardinal; var Compressed : Pointer; Header : boolean = False ) : Int64; overload;
function ExtractLZMA( Source : PByte; Len : Cardinal; var Decompressed : TByteDynArray ) : Int64; overload;
function ExtractLZMA( Source : PByte; Len : Cardinal; var Decompressed : Pointer ) : Int64; overload;

{$IFDEF TESTCASE}
function TestLZMA( FileName : string; Header : boolean = False; SaveDebugFiles : Boolean = False ) : Int64;
{$ENDIF TESTCASE}

implementation

uses
{$IFDEF TESTCASE}
  Classes, SysUtils, Dialogs,
{$ENDIF TESTCASE}
  LzmaTypes, LzmaDec, LzmaEnc;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
const
  HEADER_ = AnsiString( 'lzma' );
  HEADER_LEN_ = Length( HEADER_ );
type
  tHeader = Array [ 0..HEADER_LEN_-1 ] of AnsiChar;
  pHeader = ^tHeader;

function CompressLZMA( Source : PByte; Len : Cardinal; var Compressed : TByteDynArray; Header : boolean = False ) : Int64;
var
  Encoder : TCLzmaEncHandle;
  Props: TCLzmaEncProps;
  PropData: Array [ 0..LZMA_PROPS_SIZE-1 ] of Byte;
  PropDataLen: NativeInt;
  OutSize : Int64;
  InLen, OutLen  : NativeInt;
  Offset : NativeInt;
begin
  result := -100;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  SetLength( Compressed, 0 );
//  if NOT Assigned( OutStream ) then
//    Exit;
  Encoder := {$IFDEF UNDERSCORE}_LzmaEnc_Create{$ELSE}LzmaEnc_Create{$ENDIF}( TISzAllocDefault );
  if NOT Assigned( Encoder ) then
    Exit;

  {$IFDEF UNDERSCORE}_LzmaEncProps_Init{$ELSE}LzmaEncProps_Init{$ENDIF}( Props );
  Props.level := 9;
  Props.writeEndMark := 1;

  result := {$IFDEF UNDERSCORE}_LzmaEnc_SetProps{$ELSE}LzmaEnc_SetProps{$ENDIF}( Encoder, Props );
  if ( result <> SZ_OK ) then
    Exit;

  PropDataLen := LZMA_PROPS_SIZE;
  result := {$IFDEF UNDERSCORE}_LzmaEnc_WriteProperties{$ELSE}LzmaEnc_WriteProperties{$ENDIF}( Encoder, @PropData[ 0 ], PropDataLen );
  if ( result <> SZ_OK ) then
    Exit;

  OutSize := Len;
  Offset := 2+LZMA_PROPS_SIZE;
  if Header then
    Offset := Offset+4;
  OutLen := OutSize-Offset;
  SetLength( Compressed, OutSize );
  InLen := Len;

  if Header then
    begin
    Move( HEADER_[ 1 ], Compressed[ 0 ], HEADER_LEN_ );
    Move( PropDataLen, Compressed[ 4 ], SizeOf( Word ) );
    Move( PropData[ 0 ], Compressed[ 6 ], LZMA_PROPS_SIZE );
    end
  else
    begin
    Move( PropDataLen, Compressed[ 0 ], SizeOf( Word ) );
    Move( PropData[ 0 ], Compressed[ 2 ], LZMA_PROPS_SIZE );
    end;

  result := {$IFDEF UNDERSCORE}_LzmaEnc_MemEncode{$ELSE}LzmaEnc_MemEncode{$ENDIF}( Encoder, @Compressed[ Offset ], OutLen, Source, InLen, 1{writeEndMark}, nil, TISzAllocDefault, TISzAllocDefault );
  if ( result = SZ_OK ) then
    begin
    Result := OutLen+Offset;
    if ( Result <> OutSize ) then
      SetLength( Compressed, Result );
    end
  else
    SetLength( Compressed, 0 );

  {$IFDEF UNDERSCORE}_LzmaEnc_Destroy{$ELSE}LzmaEnc_Destroy{$ENDIF}( Encoder, TISzAllocDefault, TISzAllocDefault );
end;

function CompressLZMA( Source : PByte; Len : Cardinal; var Compressed : Pointer; Header : boolean = False ) : Int64;
var
  bCompressed : PByte;
  Encoder : TCLzmaEncHandle;
  Props: TCLzmaEncProps;
  PropData: Array [ 0..LZMA_PROPS_SIZE-1 ] of Byte;
  PropDataLen: NativeInt;
  OutSize : Int64;
  InLen, OutLen : NativeInt;
  Offset : NativeInt;
begin
  result := -100;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  if Assigned( Compressed ) then
    ReallocMem( Compressed, 0 );
//  if NOT Assigned( OutStream ) then
//    Exit;
  Encoder := {$IFDEF UNDERSCORE}_LzmaEnc_Create{$ELSE}LzmaEnc_Create{$ENDIF}( TISzAllocDefault );
  if NOT Assigned( Encoder ) then
    Exit;

  {$IFDEF UNDERSCORE}_LzmaEncProps_Init{$ELSE}LzmaEncProps_Init{$ENDIF}( Props );
  Props.level := 9;
  Props.writeEndMark := 1;  

  result := {$IFDEF UNDERSCORE}_LzmaEnc_SetProps{$ELSE}LzmaEnc_SetProps{$ENDIF}( Encoder, Props );
  if ( result <> SZ_OK ) then
    Exit;

  PropDataLen := LZMA_PROPS_SIZE;
  result := {$IFDEF UNDERSCORE}_LzmaEnc_WriteProperties{$ELSE}LzmaEnc_WriteProperties{$ENDIF}( Encoder, @PropData[ 0 ], PropDataLen );
  if ( result <> SZ_OK ) then
    Exit;

  OutSize := Len;
  Offset := 2+LZMA_PROPS_SIZE;
  if Header then
    Offset := Offset+4;
  OutLen := OutSize-Offset;
  ReallocMem( Compressed, OutSize );
  InLen := Len;

  bCompressed := Compressed;

  if Header then
    begin
    Move( HEADER_[ 1 ], bCompressed^, HEADER_LEN_ );
    Inc( bCompressed, HEADER_LEN_ );
    end;

  Move( PropDataLen, bCompressed^, SizeOf( Word ) );
  Inc( bCompressed, SizeOf( Word ) );
  Move( PropData[ 0 ], bCompressed^, LZMA_PROPS_SIZE );
  Inc( bCompressed, LZMA_PROPS_SIZE );

  result := {$IFDEF UNDERSCORE}_LzmaEnc_MemEncode{$ELSE}LzmaEnc_MemEncode{$ENDIF}( Encoder, bCompressed, OutLen, Source, InLen, 1{writeEndMark}, nil, TISzAllocDefault, TISzAllocDefault );
  if ( result = SZ_OK ) then
    begin
    Result := OutLen+Offset;
    if ( OutLen <> Result ) then
      ReallocMem( Compressed, Result );
    end
  else
    ReallocMem( Compressed, 0 );

  {$IFDEF UNDERSCORE}_LzmaEnc_Destroy{$ELSE}LzmaEnc_Destroy{$ENDIF}( Encoder, TISzAllocDefault, TISzAllocDefault );
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function ExtractLZMA( Source : PByte; Len : Cardinal; var Decompressed : TByteDynArray ) : Int64;
var
  LzmaState      : TCLzmaDec;
  Status         : ELzmaStatus;

  DataSize       : Cardinal;
  OutSize        : Cardinal;
  OutLen, InLen  : NativeInt;
  DecompressSize : Cardinal;
begin
  result := -200;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  SetLength( Decompressed, 0 );

  if ( pHeader( Source )^ = HEADER_ ) then
    begin
    Inc( Source, HEADER_LEN_ );
    Dec( Len, HEADER_LEN_ );
    end;

  result := -100;
  if ( PWord( Source )^ <> LZMA_PROPS_SIZE ) then // Properties size
    Exit;
  Inc( Source, SizeOf( Word ) );
  Dec( Len, SizeOf( Word ) );

  FillChar( LzmaState, SizeOf( LzmaState ), 0 );
  result := {$IFDEF UNDERSCORE}_LzmaDec_Allocate{$ELSE}LzmaDec_Allocate{$ENDIF}( LzmaState, Source^{Props}, LZMA_PROPS_SIZE, TISzAllocDefault );
  if ( result <> SZ_OK ) then
    Exit;
  Inc( Source, LZMA_PROPS_SIZE );
  Dec( Len, LZMA_PROPS_SIZE );
  {$IFDEF UNDERSCORE}_LzmaDec_Init{$ELSE}LzmaDec_Init{$ENDIF}( LzmaState );

  OutSize := Len*4;
  SetLength( Decompressed, OutSize );

  // Read
  DataSize := Len;
  OutLen   := OutSize;
  DecompressSize := 0;
  Status := LZMA_STATUS_NEEDS_MORE_INPUT;
  while ( DataSize > 0 ) AND ( Status = LZMA_STATUS_NEEDS_MORE_INPUT ) do
    begin
    if ( DecompressSize > 0 ) then
      begin
      OutSize := OutSize+Len;
      SetLength( Decompressed, OutSize );
      OutLen := OutSize-DecompressSize;
      end;

    InLen := DataSize;

    result := {$IFDEF UNDERSCORE}_LzmaDec_DecodeToBuf{$ELSE}LzmaDec_DecodeToBuf{$ENDIF}( LzmaState, Decompressed[ DecompressSize ], OutLen, Source^, InLen, LZMA_FINISH_ANY, Status );
    if ( result <> SZ_OK ) then
      Break;
    Dec( DataSize, InLen );
    Inc( Source, InLen );

    Inc( DecompressSize, OutLen );
    end;
  if ( result = SZ_OK ) then
    begin
    result := DecompressSize;
    if ( OutSize <> DecompressSize ) then
      SetLength( Decompressed, DecompressSize );
    end
  else
    SetLength( Decompressed, 0 );

  {$IFDEF UNDERSCORE}_LzmaDec_Free{$ELSE}LzmaDec_Free{$ENDIF}( LzmaState, TISzAllocDefault );
end;

function ExtractLZMA( Source : PByte; Len : Cardinal; var Decompressed : Pointer ) : Int64;
var
  LzmaState      : TCLzmaDec;
  Status         : ELzmaStatus;

  DataSize       : Cardinal;
  OutSize        : Cardinal;
  OutLen, InLen  : NativeInt;
  DecompressSize : Cardinal;
begin
  result := -200;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  if Assigned( Decompressed ) then
    ReallocMem( Decompressed, 0 );

  if ( pHeader( Source )^ = HEADER_ ) then
    begin
    Inc( Source, HEADER_LEN_ );
    Dec( Len, HEADER_LEN_ );
    end;

  result := -100;
  if ( PWord( Source )^ <> LZMA_PROPS_SIZE ) then // Properties size
    Exit;
  Inc( Source, SizeOf( Word ) );
  Dec( Len, SizeOf( Word ) );

  FillChar( LzmaState, SizeOf( LzmaState ), 0 );
  result := {$IFDEF UNDERSCORE}_LzmaDec_Allocate{$ELSE}LzmaDec_Allocate{$ENDIF}( LzmaState, Source^{Props}, LZMA_PROPS_SIZE, TISzAllocDefault );
  if ( result <> SZ_OK ) then
    Exit;
  Inc( Source, LZMA_PROPS_SIZE );
  Dec( Len, LZMA_PROPS_SIZE );
  {$IFDEF UNDERSCORE}_LzmaDec_Init{$ELSE}LzmaDec_Init{$ENDIF}( LzmaState );

  OutSize := Len*4;
  GetMem( Decompressed, OutSize );

  // Read
  DataSize := Len;
  OutLen   := OutSize;
  DecompressSize := 0;
  Status := LZMA_STATUS_NEEDS_MORE_INPUT;
  while ( DataSize > 0 ) AND ( Status = LZMA_STATUS_NEEDS_MORE_INPUT ) do
    begin
    if ( DecompressSize > 0 ) then
      begin
      OutSize := OutSize+Len;
      ReallocMem( Decompressed, OutSize );
      OutLen := OutSize-DecompressSize;
      end;

    InLen := DataSize;
    {$R-}
    result := {$IFDEF UNDERSCORE}_LzmaDec_DecodeToBuf{$ELSE}LzmaDec_DecodeToBuf{$ENDIF}( LzmaState, PByte( NativeUInt( Decompressed )+DecompressSize )^{bDecompressed^[ DecompressSize ]}, OutLen, Source^, InLen, LZMA_FINISH_ANY, Status );
    {$R+}
    if ( result <> SZ_OK ) then
      Break;
    Dec( DataSize, InLen );
    Inc( Source, InLen );

    Inc( DecompressSize, OutLen );
    end;
  if ( result = SZ_OK ) then
    begin
    result := DecompressSize;
    if ( OutSize <> DecompressSize ) then
      ReallocMem( Decompressed, DecompressSize );
    end
  else
    ReallocMem( Decompressed, 0 );

  {$IFDEF UNDERSCORE}_LzmaDec_Free{$ELSE}LzmaDec_Free{$ENDIF}( LzmaState, TISzAllocDefault );
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
{$IFDEF TESTCASE}
function TestLZMA( FileName : string; Header : boolean = False; SaveDebugFiles : Boolean = False ) : Int64;
var
  sIn : TMemoryStream;

  function PointerToArray : Int64;
  var
    sCompress, sOut : TMemoryStream;
    aDecompressed : TByteDynArray;
  begin
    SetLength( aDecompressed, 0 );

    sCompress := TMemoryStream.Create;
    result := CompressLZMA( sIn.Memory, sIn.Size, aDecompressed, Header );
    if ( result <= 0 ) then
      begin
      sCompress.free;
      result := -3;
      Exit;
      end;

    sCompress.Write( aDecompressed[ 0 ], Length( aDecompressed ) );
    SetLength( aDecompressed, 0 );
    if SaveDebugFiles then
      sCompress.SaveToFile( ChangeFileExt( FileName, '.lzma' ) );

    sOut := TMemoryStream.Create;
    sCompress.Position := 0;
    SetLength( aDecompressed, 0 );
    result := ExtractLZMA( sCompress.Memory, sCompress.Size, aDecompressed );
    if ( result <= 0 ) then
      begin
      sOut.free;
      sCompress.free;
      result := -2;
      Exit;
      end;
    sOut.Write( aDecompressed[ 0 ], Length( aDecompressed ) );
    SetLength( aDecompressed, 0 );

    if ( sIn.Size <> sOut.Size ) OR NOT CompareMem( sIn.Memory, sOut.Memory, sIn.Size ) then
      result := -1;
    if SaveDebugFiles then
      sOut.SaveToFile( ChangeFileExt( FileName, '.extract' ) );

    sOut.free;
    sCompress.free;
  end;

  function PointerToPointer : Int64;
  var
    sCompress, sOut : TMemoryStream;
    pDecompressed : Pointer;
  begin
    pDecompressed := nil;

    sCompress := TMemoryStream.Create;
    result := CompressLZMA( sIn.Memory, sIn.Size, pDecompressed, Header );
    if ( result <= 0 ) then
      begin
      sCompress.free;
      result := -3;
      Exit;
      end;

    sCompress.Write( pDecompressed^, result );
    ReallocMem( pDecompressed, 0 );
    if SaveDebugFiles then
      sCompress.SaveToFile( ChangeFileExt( FileName, '.lzma' ) );

    sOut := TMemoryStream.Create;
    sCompress.Position := 0;
    pDecompressed := nil;
    result := ExtractLZMA( sCompress.Memory, sCompress.Size, pDecompressed );
    if ( result <= 0 ) then
      begin
      sOut.free;
      sCompress.free;
      result := -2;
      Exit;
      end;
    sOut.Write( PByte( pDecompressed )^, result );
    ReallocMem( pDecompressed, 0 );

    if ( sIn.Size <> sOut.Size ) OR NOT CompareMem( sIn.Memory, sOut.Memory, sIn.Size ) then
      result := -1;
    if SaveDebugFiles then
      sOut.SaveToFile( ChangeFileExt( FileName, '.extract' ) );

    sOut.free;
    sCompress.free;
  end;
begin
  result := -999;
  if NOT FileExists( FileName ) then
    Exit;

  sIn := TMemoryStream.Create;
  sIn.LoadFromFile( FileName );
  sIn.Position := 0;

  result := PointerToArray;
  case result of
  -999 : ShowMessage( 'PointerToArray: Invalid File' );
    -3 : ShowMessage( 'PointerToArray: Failed compress' );
    -2 : ShowMessage( 'PointerToArray: Failed decompress' );
    -1 : ShowMessage( 'PointerToArray: Size invalid or CompareMem failed' );
     0 : ShowMessage( 'PointerToArray: Failed to Extract' );
//    else
//       ShowMessage( 'PointerToArray: OK' );
  end;
  if ( result < 0 ) then
    begin
    sIn.Free;
    Exit;
    end;

  result := PointerToPointer;
  case result of
  -999 : ShowMessage( 'PointerToPointer: Invalid File' );
    -3 : ShowMessage( 'PointerToPointer: Failed compress' );
    -2 : ShowMessage( 'PointerToPointer: Failed decompress' );
    -1 : ShowMessage( 'PointerToPointer: Size invalid or CompareMem failed' );
     0 : ShowMessage( 'PointerToPointer: Failed to Extract' );
//    else
//       ShowMessage( 'PointerToPointer: OK' );
  end;
  if ( result < 0 ) then
    begin
    sIn.Free;
    Exit;
    end;
  sIn.free;
end;
{$ENDIF TESTCASE}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

end.
