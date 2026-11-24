unit LZMA2;

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_CAST OFF}

{$I LZMA.inc}

uses
  types;

function CompressLZMA2( Source : PByte; Len : Cardinal; var Compressed : TByteDynArray; Header : boolean = False; Level : Integer = 9 ) : Int64; overload;
function CompressLZMA2( Source : PByte; Len : Cardinal; var Compressed : Pointer; Header : boolean = False; Level : Integer = 9 ) : Int64; overload;
function ExtractLZMA2( Source : PByte; Len : Cardinal; var Decompressed : TByteDynArray ) : Int64; overload;
function ExtractLZMA2( Source : PByte; Len : Cardinal; var Decompressed : Pointer ) : Int64; overload;

{$IFDEF TESTCASE}
function TestLZMA2( FileName : string; Header : boolean = False; SaveDebugFiles : Boolean = False ) : Int64;
{$ENDIF TESTCASE}

implementation

uses
{$IFDEF TESTCASE}
  Classes, SysUtils, Dialogs,
{$ENDIF TESTCASE}
  LzmaTypes, Lzma2Dec, LzmaDec, Lzma2Enc;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
type
  TLZMA2ReadProcRec = record
    Data : PByte;
    Size : NativeInt;
  end;
  pLZMA2ReadProcRec = ^TLZMA2ReadProcRec;

  TLZMA2WriteProcRec = record
    Data   : PByte;
    Size   : NativeInt;
    Used   : NativeInt;
  end;
  pLZMA2WriteProcRec = ^TLZMA2WriteProcRec;

const
  HEADER_ = AnsiString( 'lzm2' );
  HEADER_LEN_ = Length( HEADER_ );
type
  tHeader = Array [ 0..HEADER_LEN_-1 ] of AnsiChar;
  pHeader = ^tHeader;

function Lzma2ReadProc( p: PISeqInStream; buf: PByte; var size: NativeInt ): Integer; cdecl;
var
  R : PLZMA2ReadProcRec;
begin
  R := PLZMA2ReadProcRec( P.Stream );
  try
    if ( Size > R^.Size ) then
      Size := R^.Size;
    if ( Size > 0 ) then
      begin
      Move( R^.Data^, buf^, size );
      Inc( R^.Data, size );
      R^.Size := R^.Size-size;
      end;
    Result := SZ_OK;
  except
    Result := SZ_ERROR_DATA;
  end;
end;

function Lzma2WriteProc( p: PISeqOutStream; const buf: Pointer; size: NativeInt ): NativeInt; cdecl;
var
  R : PLZMA2WriteProcRec;
begin
  R := PLZMA2WriteProcRec( P.Stream );
  try
    if ( size > R^.Size ) then
      size := R^.Size;
    if ( Size > 0 ) then
      begin
      Move( buf^, R^.Data^, size );
      Inc( R^.Data, size );
      R^.Size := R^.Size-size;
      R^.Used := R^.Used+size;
      end;
    Result := size;
  except
    Result := SZ_ERROR_DATA;
  end;
end;

function CompressLZMA2( Source : PByte; Len : Cardinal; var Compressed : TByteDynArray; Header : boolean = False; Level : Integer = 9 ) : Int64;
var
  Encoder : TCLzma2EncHandle;
  Props: TCLzma2EncProps;
  bProp : Byte;
  OutSize : Int64;
  OutLen  : NativeInt;
  Offset : NativeInt;

  R: TISeqInStream;
  RS : TLZMA2ReadProcRec;
  W: TISeqOutStream;
  WS : TLZMA2WriteProcRec;
begin
  result := -100;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  SetLength( Compressed, 0 );
//  if NOT Assigned( OutStream ) then
//    Exit;
  Encoder := {$IFDEF UNDERSCORE}_Lzma2Enc_Create{$ELSE}Lzma2Enc_Create{$ENDIF}( TISzAllocDefault, TISzAllocDefault );
  if NOT Assigned( Encoder ) then
    Exit;

  {$IFDEF UNDERSCORE}_Lzma2EncProps_Init{$ELSE}Lzma2EncProps_Init{$ENDIF}( Props );
  Props.lzmaProps.level := Level;
  Props.lzmaProps.writeEndMark := 1;  
  PInt64( @Props.lzmaProps.reduceSize )^ := Len; // dictionary not larger than the data (level 9 = 64 MB dictionary, ~700 MB RAM otherwise)

  result := {$IFDEF UNDERSCORE}_Lzma2Enc_SetProps{$ELSE}Lzma2Enc_SetProps{$ENDIF}( Encoder, Props );
  if ( result <> SZ_OK ) then
    begin
    {$IFDEF UNDERSCORE}_Lzma2Enc_Destroy{$ELSE}Lzma2Enc_Destroy{$ENDIF}( Encoder );
    result := -Abs( result );
    Exit;
    end;

  bProp := {$IFDEF UNDERSCORE}_Lzma2Enc_WriteProperties{$ELSE}Lzma2Enc_WriteProperties{$ENDIF}( Encoder );

  OutSize := Int64( Len )+Len div 128+64; // room for incompressible data (stored chunks: 3 bytes per 64 KB)
  Offset := SizeOf( bProp );
  if Header then
    Offset := Offset+4;
  OutLen := OutSize-Offset;
  SetLength( Compressed, OutSize );

  if Header then
    begin
    Move( HEADER_[ 1 ], Compressed[ 0 ], HEADER_LEN_ );
    Move( bProp, Compressed[ Offset-1 ], SizeOf( bProp ) );
    end
  else
    Move( bProp, Compressed[ Offset-1 ], SizeOf( bProp ) );

  R.Proc := Lzma2ReadProc;
  RS.Data := Source;
  RS.Size := Len;
  R.Stream := @RS;

  W.Proc := Lzma2WriteProc;
  WS.Data := @Compressed[ Offset ];
  WS.Size := OutLen;
  WS.Used := 0;
  W.Stream := @WS;

//  result := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode{$ELSE}Lzma2Enc_Encode{$ENDIF}( Encoder, @W, @R, nil{progress} );
  result := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode2{$ELSE}Lzma2Enc_Encode2{$ENDIF}( Encoder, @W, nil{outbuf}, nil{size}, @R, nil{inbuf}, nil{size}, nil{progress} );
  if ( result = SZ_OK ) then
    begin
    Result := WS.Used+Offset; // OutLen+Offset;
    if ( Result <> OutSize ) then
      SetLength( Compressed, Result );
    end
  else
    begin
    SetLength( Compressed, 0 );
    result := -Abs( result ); // SZ_ERROR_* as negative value
    end;

  {$IFDEF UNDERSCORE}_Lzma2Enc_Destroy{$ELSE}Lzma2Enc_Destroy{$ENDIF}( Encoder );
end;

function CompressLZMA2( Source : PByte; Len : Cardinal; var Compressed : Pointer; Header : boolean = False; Level : Integer = 9 ) : Int64;
var
  bCompressed : PByte;
  Encoder : TCLzma2EncHandle;
  Props: TCLzma2EncProps;
  bProp : Byte;
  OutSize : Int64;
  OutLen : NativeInt;
  Offset : NativeInt;

  R: TISeqInStream;
  RS : TLZMA2ReadProcRec;
  W: TISeqOutStream;
  WS : TLZMA2WriteProcRec;
begin
  result := -100;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  if Assigned( Compressed ) then
    ReallocMem( Compressed, 0 );
//  if NOT Assigned( OutStream ) then
//    Exit;
  Encoder := {$IFDEF UNDERSCORE}_Lzma2Enc_Create{$ELSE}Lzma2Enc_Create{$ENDIF}( TISzAllocDefault, TISzAllocDefault );
  if NOT Assigned( Encoder ) then
    Exit;

  {$IFDEF UNDERSCORE}_Lzma2EncProps_Init{$ELSE}Lzma2EncProps_Init{$ENDIF}( Props );
  Props.lzmaProps.level := Level;
  Props.lzmaProps.writeEndMark := 1;  
  PInt64( @Props.lzmaProps.reduceSize )^ := Len; // dictionary not larger than the data (level 9 = 64 MB dictionary, ~700 MB RAM otherwise)

  result := {$IFDEF UNDERSCORE}_Lzma2Enc_SetProps{$ELSE}Lzma2Enc_SetProps{$ENDIF}( Encoder, Props );
  if ( result <> SZ_OK ) then
    begin
    {$IFDEF UNDERSCORE}_Lzma2Enc_Destroy{$ELSE}Lzma2Enc_Destroy{$ENDIF}( Encoder );
    result := -Abs( result );
    Exit;
    end;

  bProp := {$IFDEF UNDERSCORE}_Lzma2Enc_WriteProperties{$ELSE}Lzma2Enc_WriteProperties{$ENDIF}( Encoder );

  OutSize := Int64( Len )+Len div 128+64; // room for incompressible data (stored chunks: 3 bytes per 64 KB)
  Offset := SizeOf( bProp );
  if Header then
    Offset := Offset+4;
  OutLen := OutSize-Offset;
  ReallocMem( Compressed, OutSize ); // header + payload; OutLen alone was Offset bytes short

  bCompressed := Compressed;

  if Header then
    begin
    Move( HEADER_[ 1 ], bCompressed^, HEADER_LEN_ );
    Inc( bCompressed, HEADER_LEN_ );
    end;

  Move( bProp, bCompressed^, SizeOf( bProp ) );
  Inc( bCompressed, SizeOf( bProp ) );

  R.Proc := Lzma2ReadProc;
  RS.Data := Source;
  RS.Size := Len;
  R.Stream := @RS;

  W.Proc := Lzma2WriteProc;
  WS.Data := bCompressed;
  WS.Size := OutLen;
  WS.Used := 0;
  W.Stream := @WS;

//  result := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode{$ELSE}Lzma2Enc_Encode{$ENDIF}( Encoder, @W, @R, nil{progress} );
  result := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode2{$ELSE}Lzma2Enc_Encode2{$ENDIF}( Encoder, @W, nil{outbuf}, nil{size}, @R, nil{inbuf}, nil{size}, nil{progress} );
  if ( result = SZ_OK ) then
    begin
    Result := WS.Used+Offset; // OutLen+Offset;
    if ( OutLen <> Result ) then
      ReallocMem( Compressed, Result );
    end
  else
    begin
    ReallocMem( Compressed, 0 );
    result := -Abs( result ); // SZ_ERROR_* as negative value
    end;

  {$IFDEF UNDERSCORE}_Lzma2Enc_Destroy{$ELSE}Lzma2Enc_Destroy{$ENDIF}( Encoder );
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function ExtractLZMA2( Source : PByte; Len : Cardinal; var Decompressed : TByteDynArray ) : Int64;
var
  Lzma2State     : TCLzma2Dec;
  Status         : ELzmaStatus;

  DataSize       : Cardinal;
  OutSize        : Cardinal;
  OutLen, InLen  : NativeInt;
  DecompressSize : Cardinal;
begin
  result := -100;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  SetLength( Decompressed, 0 );

  if ( pHeader( Source )^ = HEADER_ ) then
    begin
    Inc( Source, HEADER_LEN_ );
    Dec( Len, HEADER_LEN_ );
    end;

  FillChar( Lzma2State, SizeOf( Lzma2State ), 0 );
  result := {$IFDEF UNDERSCORE}_Lzma2Dec_Allocate{$ELSE}Lzma2Dec_Allocate{$ENDIF}( Lzma2State, Source^{Props}, TISzAllocDefault );
  if ( result <> SZ_OK ) then
    begin
    result := -Abs( result );
    Exit;
    end;
  Inc( Source, 1{LZMA_PROPS_SIZE} );
  Dec( Len, 1{LZMA_PROPS_SIZE} );
  {$IFDEF UNDERSCORE}_Lzma2Dec_Init{$ELSE}Lzma2Dec_Init{$ENDIF}( Lzma2State );

  OutSize := Len*4;
  if ( OutSize < 4096 ) then
    OutSize := 4096;
  SetLength( Decompressed, OutSize );

  // 2026-11-24: keep decoding while the decoder reports LZMA_STATUS_NOT_FINISHED (output buffer full) and grow
  // the buffer by doubling. Before, the loop only continued on NEEDS_MORE_INPUT and returned the data silently
  // truncated to 4 x compressed size (e.g. 6.1 of 14.7 MB at ratio 9.7:1). A stream without end mark is SZ_ERROR_DATA.
  DataSize := Len;
  DecompressSize := 0;
  Status := LZMA_STATUS_NOT_SPECIFIED;
  repeat
    if ( DecompressSize = OutSize ) then
      begin
      OutSize := OutSize*2;
      SetLength( Decompressed, OutSize );
      end;
    InLen  := DataSize;
    OutLen := OutSize-DecompressSize;
    result := {$IFDEF UNDERSCORE}_Lzma2Dec_DecodeToBuf{$ELSE}Lzma2Dec_DecodeToBuf{$ENDIF}( Lzma2State, Decompressed[ DecompressSize ], OutLen, Source^, InLen, LZMA_FINISH_ANY, Status );
    if ( result <> SZ_OK ) then
      Break;
    Dec( DataSize, InLen );
    Inc( Source, InLen );
    Inc( DecompressSize, OutLen );
    if ( InLen = 0 ) AND ( OutLen = 0 ) then
      Break; // no progress
  until ( Status = LZMA_STATUS_FINISHED_WITH_MARK ) OR ( ( Status = LZMA_STATUS_NEEDS_MORE_INPUT ) AND ( DataSize = 0 ) );
  if ( result = SZ_OK ) AND ( Status <> LZMA_STATUS_FINISHED_WITH_MARK ) then
    result := SZ_ERROR_DATA; // stream ended without end mark: incomplete
  if ( result = SZ_OK ) then
    begin
    result := DecompressSize;
    if ( OutSize <> DecompressSize ) then
      SetLength( Decompressed, DecompressSize );
    end
  else
    begin
    SetLength( Decompressed, 0 );
    result := -Abs( result ); // SZ_ERROR_* as negative value
    end;

  {$IFDEF UNDERSCORE}_LzmaDec_Free{$ELSE}LzmaDec_Free{$ENDIF}( Lzma2State.Decoder, TISzAllocDefault );
end;

function ExtractLZMA2( Source : PByte; Len : Cardinal; var Decompressed : Pointer ) : Int64;
var
  Lzma2State     : TCLzma2Dec;
  Status         : ELzmaStatus;

  DataSize       : Cardinal;
  OutSize        : Cardinal;
  OutLen, InLen  : NativeInt;
  DecompressSize : Cardinal;
begin
  result := -100;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  if Assigned( Decompressed ) then
    ReallocMem( Decompressed, 0 );

  if ( pHeader( Source )^ = HEADER_ ) then
    begin
    Inc( Source, HEADER_LEN_ );
    Dec( Len, HEADER_LEN_ );
    end;

  FillChar( Lzma2State, SizeOf( Lzma2State ), 0 );
  result := {$IFDEF UNDERSCORE}_Lzma2Dec_Allocate{$ELSE}Lzma2Dec_Allocate{$ENDIF}( Lzma2State, Source^{Props}, TISzAllocDefault );
  if ( result <> SZ_OK ) then
    begin
    result := -Abs( result );
    Exit;
    end;
  Inc( Source, 1{LZMA_PROPS_SIZE} );
  Dec( Len, 1{LZMA_PROPS_SIZE} );
  {$IFDEF UNDERSCORE}_Lzma2Dec_Init{$ELSE}Lzma2Dec_Init{$ENDIF}( Lzma2State );

  OutSize := Len*4;
  if ( OutSize < 4096 ) then
    OutSize := 4096;
  GetMem( Decompressed, OutSize );

  // 2026-11-24: keep decoding while the decoder reports LZMA_STATUS_NOT_FINISHED (output buffer full) and grow
  // the buffer by doubling. Before, the loop only continued on NEEDS_MORE_INPUT and returned the data silently
  // truncated to 4 x compressed size (e.g. 6.1 of 14.7 MB at ratio 9.7:1). A stream without end mark is SZ_ERROR_DATA.
  DataSize := Len;
  DecompressSize := 0;
  Status := LZMA_STATUS_NOT_SPECIFIED;
  repeat
    if ( DecompressSize = OutSize ) then
      begin
      OutSize := OutSize*2;
      ReallocMem( Decompressed, OutSize );
      end;
    InLen  := DataSize;
    OutLen := OutSize-DecompressSize;
    {$R-}
    result := {$IFDEF UNDERSCORE}_Lzma2Dec_DecodeToBuf{$ELSE}Lzma2Dec_DecodeToBuf{$ENDIF}( Lzma2State, PByte( NativeUInt( Decompressed )+DecompressSize )^, OutLen, Source^, InLen, LZMA_FINISH_ANY, Status );
    {$R+}
    if ( result <> SZ_OK ) then
      Break;
    Dec( DataSize, InLen );
    Inc( Source, InLen );
    Inc( DecompressSize, OutLen );
    if ( InLen = 0 ) AND ( OutLen = 0 ) then
      Break; // no progress
  until ( Status = LZMA_STATUS_FINISHED_WITH_MARK ) OR ( ( Status = LZMA_STATUS_NEEDS_MORE_INPUT ) AND ( DataSize = 0 ) );
  if ( result = SZ_OK ) AND ( Status <> LZMA_STATUS_FINISHED_WITH_MARK ) then
    result := SZ_ERROR_DATA; // stream ended without end mark: incomplete
  if ( result = SZ_OK ) then
    begin
    result := DecompressSize;
    if ( OutSize <> DecompressSize ) then
      ReallocMem( Decompressed, DecompressSize );
    end
  else
    begin
    ReallocMem( Decompressed, 0 );
    result := -Abs( result ); // SZ_ERROR_* as negative value
    end;

  {$IFDEF UNDERSCORE}_LzmaDec_Free{$ELSE}LzmaDec_Free{$ENDIF}( Lzma2State.Decoder, TISzAllocDefault );
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
{$IFDEF TESTCASE}
function TestLZMA2( FileName : string; Header : boolean = False; SaveDebugFiles : Boolean = False ) : Int64;
var
  sIn : TMemoryStream;

  function PointerToArray : Int64;
  var
    sCompress, sOut : TMemoryStream;
    aDecompressed : TByteDynArray;
  begin
    SetLength( aDecompressed, 0 );

    sCompress := TMemoryStream.Create;
    result := CompressLZMA2( sIn.Memory, sIn.Size, aDecompressed, Header );
    if ( result <= 0 ) then
      begin
      sCompress.free;
      result := -3;
      Exit;
      end;

    sCompress.Write( aDecompressed[ 0 ], Length( aDecompressed ) );
    sCompress.Position := 0;
    SetLength( aDecompressed, 0 );
    if SaveDebugFiles then
      sCompress.SaveToFile( ChangeFileExt( FileName, '.lzma2' ) );

    sOut := TMemoryStream.Create;
    SetLength( aDecompressed, 0 );
    result := ExtractLZMA2( sCompress.Memory, sCompress.Size, aDecompressed );
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
    result := CompressLZMA2( sIn.Memory, sIn.Size, pDecompressed, Header );
    if ( result <= 0 ) then
      begin
      sCompress.free;
      result := -3;
      Exit;
      end;

    sCompress.Write( pDecompressed^, result );
    ReallocMem( pDecompressed, 0 );
    sCompress.Position := 0;    
    if SaveDebugFiles then
      sCompress.SaveToFile( ChangeFileExt( FileName, '.lzma2' ) );

    sOut := TMemoryStream.Create;
    pDecompressed := nil;
    result := ExtractLZMA2( sCompress.Memory, sCompress.Size, pDecompressed );
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
