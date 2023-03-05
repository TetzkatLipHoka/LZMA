unit LZMA2Stream;

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_CAST OFF}

{$I LZMA.inc}

uses
  Classes, types,
  LzmaTypes, Lzma2Dec, LzmaDec, Lzma2Enc;

type
  {$IF NOT Declared( TBytes )}
  TBytes = TByteDynArray;
  {$IFEND}

  TLZMA2EncoderStream = class( TStream )
  private
    FStream  : TStream;
    FEncoder : TCLzma2EncHandle;
    fHeader  : Boolean;
    fError   : Integer;
  public
    constructor Create( const Stream: TStream; Header : boolean = False ); reintroduce;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    function Read( var Buffer; Count: Longint ): Longint; override;
    function Write( const Buffer; Count: Longint ): Longint; override;
    function Compress( InStream: TStream ) : LongInt;
    property Error : Integer read fError;
  end;

  TLZMA2DecoderStream = class( TStream )
  private
    fError          : Integer;
    FCurrentDataLen : Cardinal;
    FData           : Array of Byte;
    FLzma2State     : TCLzma2Dec;
    FStream         : TStream;
    FDecompressSize : Int64;
  public
    constructor Create( const Stream: TStream ); reintroduce;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    function Read( Buffer: TBytes; Count: Longint ): Longint; reintroduce;
//    function Read( var Buffer; Count: Longint ): Longint; override;
    function Write( const Buffer; Count: Longint ): Longint; override;
    function Decompress( OutStream: TStream ) : Longint;
    property Error : Integer read fError;
  end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function CompressStreamLZMA2( InStream : TStream; OutStream: TStream; Header : boolean = False ) : Int64; overload;
function CompressStreamLZMA2( Source : PByte ; Len : Cardinal; OutStream: TStream; Header : boolean = False ) : Int64; overload;
function ExtractStreamLZMA2( InStream : TStream; OutStream: TStream ) : Int64;

{$IFDEF TESTCASE}
function TestLZMA2Stream( FileName : string; Header : boolean = False; SaveDebugFiles : Boolean = False ) : Int64;
{$ENDIF TESTCASE}

implementation

{$IFDEF TESTCASE}
uses
  SysUtils, Dialogs;
{$ENDIF TESTCASE}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
type
  TLZMA2ReadProcRec = record
    Data : PByte;
    Size : NativeInt;
  end;
  pLZMA2ReadProcRec = ^TLZMA2ReadProcRec;

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
      Inc( R^.Data^, size );
      R^.Size := R^.Size-size;
      end;
    Result := SZ_OK;
  except
    Result := SZ_ERROR_DATA;
  end;
end;

function Lzma2ReadProcStream( p: PISeqInStream; buf: PByte; var size: NativeInt ): Integer; cdecl;
begin
  try
    size := TStream( P.Stream ).Read( buf^, size );
    Result := SZ_OK;
  except
    Result := SZ_ERROR_DATA;
  end;
end;

function Lzma2WriteProc( p: PISeqOutStream; const buf: Pointer; size: NativeInt ): NativeInt; cdecl;
begin
  Result := TStream( P.Stream ).Write( buf^, size );
end;

//function Lzma2ProgressProc( p: PICompressProgress; inSize: UInt64; outSize: UInt64 ): Integer; cdecl;
//begin
//  if Assigned( p.Progress ) then
//    p.Progress( nil, TEncoding.Default.GetString( p.ZipHeader.FileName ), p.ZipHeader, inSize );
//  Result := SZ_OK;
//end;

constructor TLZMA2EncoderStream.Create( const Stream: TStream; Header : boolean = False );
begin
  inherited Create;
  FStream := Stream;
  FEncoder := nil;
  fError := 0;
  fHeader := Header;
end;

procedure TLZMA2EncoderStream.AfterConstruction;
var
  Props: TCLzma2EncProps;
  bProp : Byte;
begin
  inherited;
  FEncoder := {$IFDEF UNDERSCORE}_Lzma2Enc_Create{$ELSE}Lzma2Enc_Create{$ENDIF}( TISzAllocDefault, TISzAllocDefault );
  if NOT Assigned( FEncoder ) then
    begin
    fError := -100;
    Exit;
    end;

  {$IFDEF UNDERSCORE}_Lzma2EncProps_Init{$ELSE}Lzma2EncProps_Init{$ENDIF}( Props );
  Props.lzmaProps.level := 9;
  Props.lzmaProps.writeEndMark := 1;

  fError := {$IFDEF UNDERSCORE}_Lzma2Enc_SetProps{$ELSE}Lzma2Enc_SetProps{$ENDIF}( FEncoder, Props );
  if ( fError <> SZ_OK ) then
    Exit;

  bProp := {$IFDEF UNDERSCORE}_Lzma2Enc_WriteProperties{$ELSE}Lzma2Enc_WriteProperties{$ENDIF}( FEncoder );

  if fHeader then
    FStream.Write( HEADER_[ 1 ], HEADER_LEN_ );
  FStream.Write( bProp, SizeOf( bProp ) );
end;

procedure TLZMA2EncoderStream.BeforeDestruction;
begin
  inherited;
  if Assigned( FEncoder ) then
    {$IFDEF UNDERSCORE}_Lzma2Enc_Destroy{$ELSE}Lzma2Enc_Destroy{$ENDIF}( FEncoder );
end;

function TLZMA2EncoderStream.Read( var Buffer; Count: Longint ): Longint;
begin
  result := FStream.Read( Buffer, Count );
end;

function TLZMA2EncoderStream.Write( const Buffer; Count: Longint ): Longint;
var
  R: TISeqInStream;
  W: TISeqOutStream;
begin
  R.Proc := Lzma2ReadProcStream;
  R.Stream := TStream( Buffer );

  W.Proc := Lzma2WriteProc;
  W.Stream := FStream;

//  fError := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode{$ELSE}Lzma2Enc_Encode{$ENDIF}( FEncoder, @W, @R, nil );
  fError := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode2{$ELSE}Lzma2Enc_Encode2{$ENDIF}( FEncoder, @W, nil{outbuf}, nil{size}, @R, nil{inbuf}, nil{size}, nil{progress} );
  if ( fError <> SZ_OK ) then
    begin
    result := fError;
    Exit;
    end
  else
    Result := FStream.Size;
end;

function TLZMA2EncoderStream.Compress( InStream: TStream ) : LongInt;
begin
  if ( InStream.Position = InStream.Size ) then
    InStream.Position := 0;
  result := Write( InStream, InStream.Size-InStream.Position );
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Decoder
const
  BufferSizeOut_ = $FFFF;
  BufferSizeIn_ = $3FFF;

constructor TLZMA2DecoderStream.Create( const Stream: TStream );
begin
  inherited Create;
  FStream := Stream;
  fError := 0;
  FDecompressSize := 0;
  SetLength( FData, 0 );
end;

procedure TLZMA2DecoderStream.AfterConstruction;
var
  Head : tHeader;
  bProp : Byte;
begin
  inherited;

  if ( FStream.Read( Head[ 0 ], HEADER_LEN_ ) <> HEADER_LEN_ ) then
    begin
    fError := -200;
    Exit;
    end;
  if ( Head <> HEADER_ ) then
    FStream.Position := FStream.Position-HEADER_LEN_;

  FStream.Read( bProp, SizeOf( bProp ) );
  FillChar( FLzma2State, SizeOf( FLzma2State ), 0 );
  fError := {$IFDEF UNDERSCORE}_Lzma2Dec_Allocate{$ELSE}Lzma2Dec_Allocate{$ENDIF}( FLzma2State, bProp, TISzAllocDefault );
  if ( fError <> SZ_OK ) then
    Exit;
  {$IFDEF UNDERSCORE}_Lzma2Dec_Init{$ELSE}Lzma2Dec_Init{$ENDIF}( FLzma2State );

  SetLength( FData, BufferSizeIn_ );
end;

procedure TLZMA2DecoderStream.BeforeDestruction;
begin
  {$IFDEF UNDERSCORE}_LzmaDec_Free{$ELSE}LzmaDec_Free{$ENDIF}( FLzma2State.Decoder, TISzAllocDefault );
  FillChar( FLzma2State, SizeOf( FLzma2State ), 0 );
  SetLength( FData, 0 );
  inherited;
end;

function TLZMA2DecoderStream.Read( Buffer: TBytes; Count: Longint ): Longint;
//function TLZMA2DecoderStream.Read( var Buffer; Count: Longint ): Longint;
var
  Status: ELzmaStatus;
  OutLen, InLen: NativeInt;
  BufferPos: LongInt;
begin
  BufferPos := 0;
  FCurrentDataLen := 0;
  Status := LZMA_STATUS_NOT_FINISHED;
  while ( Status <> LZMA_STATUS_FINISHED_WITH_MARK ) do
    begin
    if ( FCurrentDataLen > 0 ) then
      FStream.Position := FStream.Position-FCurrentDataLen;
    if ( BufferPos = Count ) then
      Break;      
    if ( FStream.Position = FStream.Size ) then
      break;
    FCurrentDataLen := FStream.Read( FData[ 0 ], BufferSizeIn_ );
    OutLen := Count - BufferPos;
    InLen := FCurrentDataLen;

    fError := {$IFDEF UNDERSCORE}_Lzma2Dec_DecodeToBuf{$ELSE}Lzma2Dec_DecodeToBuf{$ENDIF}( FLzma2State, Buffer[ BufferPos ], OutLen, FData[ 0 ], InLen, LZMA_FINISH_ANY, Status );
    if ( fError <> SZ_OK ) then
      begin
      result := fError;
      Exit;
      end;
    Dec( FCurrentDataLen, InLen );

    Inc( BufferPos, OutLen );
    Inc( FDecompressSize, OutLen );
    end;

//  if Assigned( FProgress ) then
//    FProgress( Self, TEncoding.Default.GetString( FZipHeader.FileName ), FZipHeader, FDecompressSize );

  Result := BufferPos;
end;

function TLZMA2DecoderStream.Write( const Buffer; Count: Longint ): Longint;
begin
  result := -1;
end;

function TLZMA2DecoderStream.Decompress( OutStream: TStream ) : Longint;
var
  Buffer: TBytes;
  BytesRead: Integer;
  res : Integer;
  Head : tHeader;
begin
  result := 0;
  res := -300;
  SetLength( Buffer, BufferSizeOut_ );

  if ( FStream.Read( Head[ 0 ], HEADER_LEN_ ) <> HEADER_LEN_ ) then
    Exit;
  if ( Head <> HEADER_ ) then
    FStream.Position := FStream.Position-HEADER_LEN_;

  repeat
    BytesRead := Read( Buffer, BufferSizeOut_ );
    if ( BytesRead <= 0 ) then
      begin
      if ( BytesRead < 0 ) then
        begin
        fError := BytesRead;
        result := BytesRead;
        end;
      break;
      end;
    res := OutStream.Write( Buffer[ 0 ], BytesRead );
    if ( res <= 0 ) then
      begin
      fError := res;
      result := res;
      Break;
      end
    else
      Inc( result, res );
  until ( BytesRead = 0 );

  SetLength( Buffer, 0 );
  if ( res > 0 ) then
    fError := SZ_OK;
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function CompressStreamLZMA2( InStream : TStream; OutStream: TStream; Header : boolean = False ) : Int64;
var
  Encoder : TCLzma2EncHandle;
  Props: TCLzma2EncProps;
  bProp : Byte;
  R: TISeqInStream;
  W: TISeqOutStream;
  ToSource : Boolean;
begin
  result := -100;
  if NOT Assigned( InStream ) then
    Exit;
  if ( InStream = OutStream ) OR NOT Assigned( OutStream ) then
    begin
    ToSource := True;
    OutStream := TMemoryStream.Create;
    end
  else
    ToSource := False;

  Encoder := {$IFDEF UNDERSCORE}_Lzma2Enc_Create{$ELSE}Lzma2Enc_Create{$ENDIF}( TISzAllocDefault, TISzAllocDefault );
  if NOT Assigned( Encoder ) then
    begin
    if ToSource then
      OutStream.free;
    Exit;
    end;

  {$IFDEF UNDERSCORE}_Lzma2EncProps_Init{$ELSE}Lzma2EncProps_Init{$ENDIF}( Props );
  Props.lzmaProps.level := 9;
  Props.lzmaProps.writeEndMark := 1;  

  result := {$IFDEF UNDERSCORE}_Lzma2Enc_SetProps{$ELSE}Lzma2Enc_SetProps{$ENDIF}( Encoder, Props );
  if ( result <> SZ_OK ) then
    begin
    if ToSource then
      OutStream.free;
    Exit;
    end;

  bProp := {$IFDEF UNDERSCORE}_Lzma2Enc_WriteProperties{$ELSE}Lzma2Enc_WriteProperties{$ENDIF}( Encoder );

  if Header then
    OutStream.Write( HEADER_[ 1 ], HEADER_LEN_ );
  OutStream.Write( bProp, SizeOf( bProp ) );

  R.Proc := Lzma2ReadProcStream;
  R.Stream := InStream;

  W.Proc := Lzma2WriteProc;
  W.Stream := OutStream;

//  result := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode{$ELSE}Lzma2Enc_Encode{$ENDIF}( Encoder, @W, @R, nil );
  result := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode2{$ELSE}Lzma2Enc_Encode2{$ENDIF}( Encoder, @W, nil{outbuf}, nil{size}, @R, nil{inbuf}, nil{size}, nil{progress} );
  if ( result = SZ_OK ) then
    Result := OutStream.Size;

  {$IFDEF UNDERSCORE}_Lzma2Enc_Destroy{$ELSE}Lzma2Enc_Destroy{$ENDIF}( Encoder );

  if ToSource then
    begin
    InStream.Position  := 0;
    InStream.Size      := 0;
    OutStream.Position := 0;
    InStream.CopyFrom( OutStream, OutStream.Size );
    OutStream.free;
    end;
end;

function CompressStreamLZMA2( Source : PByte ; Len : Cardinal; OutStream: TStream; Header : boolean = False ) : Int64;
var
  Encoder : TCLzma2EncHandle;
  Props: TCLzma2EncProps;
  bProp : Byte;
  R: TISeqInStream;
  RS : TLZMA2ReadProcRec;
  W: TISeqOutStream;
begin
  result := -100;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  if NOT Assigned( OutStream ) then
    Exit;
  Encoder := {$IFDEF UNDERSCORE}_Lzma2Enc_Create{$ELSE}Lzma2Enc_Create{$ENDIF}( TISzAllocDefault, TISzAllocDefault );
  if NOT Assigned( Encoder ) then
    Exit;

  {$IFDEF UNDERSCORE}_Lzma2EncProps_Init{$ELSE}Lzma2EncProps_Init{$ENDIF}( Props );
  Props.lzmaProps.level := 9;
  Props.lzmaProps.writeEndMark := 1;

  result := {$IFDEF UNDERSCORE}_Lzma2Enc_SetProps{$ELSE}Lzma2Enc_SetProps{$ENDIF}( Encoder, Props );
  if ( result <> SZ_OK ) then
    Exit;

  bProp := {$IFDEF UNDERSCORE}_Lzma2Enc_WriteProperties{$ELSE}Lzma2Enc_WriteProperties{$ENDIF}( Encoder );

  if Header then
    OutStream.Write( HEADER_[ 1 ], HEADER_LEN_ );
  OutStream.Write( bProp, SizeOf( bProp ) );

  R.Proc := Lzma2ReadProc;
  RS.Data := Source;
  RS.Size := Len;
  R.Stream := @RS;

  W.Proc := Lzma2WriteProc;
  W.Stream := OutStream;

//  result := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode{$ELSE}Lzma2Enc_Encode{$ENDIF}( Encoder, @W, @R, nil );
  result := {$IFDEF UNDERSCORE}_Lzma2Enc_Encode2{$ELSE}Lzma2Enc_Encode2{$ENDIF}( Encoder, @W, nil{outbuf}, nil{size}, @R, nil{inbuf}, nil{size}, nil{progress} );
  if ( result = SZ_OK ) then
    Result := OutStream.Size;

  {$IFDEF UNDERSCORE}_Lzma2Enc_Destroy{$ELSE}Lzma2Enc_Destroy{$ENDIF}( Encoder );
end;

function ExtractStreamLZMA2( InStream : TStream; OutStream: TStream ) : Int64;
var
  bProp          : Byte;
  Head           : tHeader;
  ToSource       : Boolean;
  Lzma2State     : TCLzma2Dec;
  Data           : Array of Byte;
  Buffer         : Array of Byte;

  CurrentDataLen : Cardinal;
  Status         : ELzmaStatus;
  OutLen, InLen  : NativeInt;
begin
  result := -200;
  if NOT Assigned( InStream ) then
    Exit;
  if ( InStream = OutStream ) OR NOT Assigned( OutStream ) then
    begin
    ToSource := True;
    OutStream := TMemoryStream.Create;
    end
  else
    ToSource := False;

  if ( InStream.Read( Head[ 0 ], HEADER_LEN_ ) <> HEADER_LEN_ ) then
    Exit;
  if ( Head <> HEADER_ ) then
    InStream.Position := InStream.Position-HEADER_LEN_;
  InStream.Read( bProp, SizeOf( bProp ) );

  FillChar( Lzma2State, SizeOf( Lzma2State ), 0 );
  result := {$IFDEF UNDERSCORE}_Lzma2Dec_Allocate{$ELSE}Lzma2Dec_Allocate{$ENDIF}( Lzma2State, bProp, TISzAllocDefault );
  if ( result <> SZ_OK ) then
    begin
    if ToSource then
      OutStream.free;
    Exit;
    end;
  {$IFDEF UNDERSCORE}_Lzma2Dec_Init{$ELSE}Lzma2Dec_Init{$ENDIF}( Lzma2State );

  SetLength( Buffer, BufferSizeOut_ );
  SetLength( Data, BufferSizeIn_ );
  CurrentDataLen := 0;
  result := 0;

  Status := LZMA_STATUS_NOT_FINISHED;
  while ( Status <> LZMA_STATUS_FINISHED_WITH_MARK ) do
    begin
    if ( CurrentDataLen > 0 ) then
      InStream.Position := InStream.Position-CurrentDataLen;
    if ( InStream.Position = InStream.Size ) then
      break;
    CurrentDataLen := InStream.Read( Data[ 0 ], BufferSizeIn_ );

    InLen := CurrentDataLen;
    result := {$IFDEF UNDERSCORE}_Lzma2Dec_DecodeToBuf{$ELSE}Lzma2Dec_DecodeToBuf{$ENDIF}( Lzma2State, Buffer[ 0 ], OutLen, Data[ 0 ], InLen, LZMA_FINISH_ANY, Status );
    if ( result <> SZ_OK ) then
      break;

    Dec( CurrentDataLen, InLen );
//    Inc( DecompressSize, OutLen );

    if ( OutLen > 0 ) then
      begin
      result := OutStream.Write( Buffer[ 0 ], OutLen );
      if ( result <= 0 ) then
        Break;
      end
    else
      break;
    end;
  SetLength( Buffer, 0 );

  if ( result >= 0 ) then
    result := OutStream.Size;

  {$IFDEF UNDERSCORE}_LzmaDec_FreeProbs{$ELSE}LzmaDec_FreeProbs{$ENDIF}( Lzma2State.Decoder, TISzAllocDefault );
//  {$IFDEF UNDERSCORE}_LzmaDec_Free{$ELSE}LzmaDec_Free{$ENDIF}( Lzma2State.Decoder, TISzAllocDefault );
  FillChar( Lzma2State, SizeOf( Lzma2State ), 0 );
  SetLength( Data, 0 );

  if ToSource then
    begin
    InStream.Position  := 0;
    InStream.Size      := 0;
    OutStream.Position := 0;
    InStream.CopyFrom( OutStream, OutStream.Size );
    OutStream.free;
    end;
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Helper
{
function CompressStreamLZMA2( InStream, OutStream: TStream; Header : boolean = False ) : LongInt;
var
  Encoder: TLZMA2EncoderStream;
begin
  Encoder := TLZMA2EncoderStream.Create( OutStream, Header );
  try
    result := Encoder.Compress( InStream );
  finally
    Encoder.Free;
  end;
end;

function ExtractStreamLZMA2( InStream, OutStream: TStream ) : LongInt;
var
  Decoder: TLZMA2DecoderStream;
begin
  Decoder := TLZMA2DecoderStream.Create( InStream );
  try
    result := Decoder.Decompress( OutStream );
  finally
    Decoder.Free;
  end;
end;
}

{$IFDEF TESTCASE}
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function TestLZMA2Stream( FileName : string; Header : boolean = False; SaveDebugFiles : Boolean = False ) : Int64;
var
  sIn : TMemoryStream;

  function PointerToStream : Int64;
  var
    sCompress, sOut : TMemoryStream;
  begin
    sCompress := TMemoryStream.Create;
    result := CompressStreamLZMA2( sIn.Memory, sIn.Size, sCompress, Header );
    if ( result <= 0 ) then
      begin
      sCompress.free;
      result := -3;
      Exit;
      end;
    if SaveDebugFiles then
      sCompress.SaveToFile( ChangeFileExt( FileName, '.lzma2' ) );

    sOut := TMemoryStream.Create;
    sCompress.Position := 0;
    result := ExtractStreamLZMA2( sCompress, sOut );
    if ( result <= 0 ) then
      begin
      sOut.free;
      sCompress.free;
      result := -2;
      Exit;
      end;

    if ( sIn.Size <> sOut.Size ) OR NOT CompareMem( sIn.Memory, sOut.Memory, sIn.Size ) then
      result := -1;
    if SaveDebugFiles then
      sOut.SaveToFile( ChangeFileExt( FileName, '.extract' ) );

    sOut.free;
    sCompress.free;
  end;

  function StreamToStream : Int64;
  var
    sCompress, sOut : TMemoryStream;
  begin
    sCompress := TMemoryStream.Create;
    result := CompressStreamLZMA2( sIn, sCompress, Header );
    if ( result <= 0 ) then
      begin
      sCompress.free;
      result := -3;
      Exit;
      end;
    if SaveDebugFiles then
      sCompress.SaveToFile( ChangeFileExt( FileName, '.lzma2' ) );

    sOut := TMemoryStream.Create;
    sCompress.Position := 0;
    result := ExtractStreamLZMA2( sCompress, sOut );
    if ( result <= 0 ) then
      begin
      sOut.free;
      sCompress.free;
      result := -2;
      Exit;
      end;

    if ( sIn.Size <> sOut.Size ) OR NOT CompareMem( sIn.Memory, sOut.Memory, sIn.Size ) then
      result := -1;
    if SaveDebugFiles then
      sOut.SaveToFile( ChangeFileExt( FileName, '.extract' ) );

    sOut.free;
    sCompress.free;
  end;

  function StreamToStreamClass : Int64;
    function CompressStreamLZMA2( InStream, OutStream: TStream; Header : boolean = False ) : LongInt;
    var
      Encoder: TLZMA2EncoderStream;
    begin
      Encoder := TLZMA2EncoderStream.Create( OutStream, Header );
      try
        result := Encoder.Compress( InStream );
      finally
        Encoder.Free;
      end;
    end;

    function ExtractStreamLZMA2( InStream, OutStream: TStream ) : LongInt;
    var
      Decoder: TLZMA2DecoderStream;
    begin
      Decoder := TLZMA2DecoderStream.Create( InStream );
      try
        result := Decoder.Decompress( OutStream );
      finally
        Decoder.Free;
      end;
    end;
  var
    sCompress, sOut : TMemoryStream;
  begin
    sCompress := TMemoryStream.Create;
    result := CompressStreamLZMA2( sIn, sCompress, Header );
    if ( result <= 0 ) then
      begin
      sCompress.free;
      result := -3;
      Exit;
      end;
    if SaveDebugFiles then
      sCompress.SaveToFile( ChangeFileExt( FileName, '.lzma' ) );

    sOut := TMemoryStream.Create;
    sCompress.Position := 0;
    result := ExtractStreamLZMA2( sCompress, sOut );
    if ( result <= 0 ) then
      begin
      sOut.free;
      sCompress.free;
      result := -2;
      Exit;
      end;

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

  result := PointerToStream;
  case result of
  -999 : ShowMessage( 'PointerToStream: Invalid File' );
    -3 : ShowMessage( 'PointerToStream: Failed compress' );
    -2 : ShowMessage( 'PointerToStream: Failed decompress' );
    -1 : ShowMessage( 'PointerToStream: Size invalid or CompareMem failed' );
     0 : ShowMessage( 'PointerToStream: Failed to Extract' );
//    else
//       ShowMessage( 'PointerToStream: OK' );
  end;
  if ( result < 0 ) then
    begin
    sIn.Free;
    Exit;
    end;

  result := StreamToStream;
  case result of
  -999 : ShowMessage( 'StreamToStream: Invalid File' );
    -3 : ShowMessage( 'StreamToStream: Failed compress' );
    -2 : ShowMessage( 'StreamToStream: Failed decompress' );
    -1 : ShowMessage( 'StreamToStream: Size invalid or CompareMem failed' );
     0 : ShowMessage( 'StreamToStream: Failed to Extract' );
//    else
//       ShowMessage( 'StreamToStream: OK' );
  end;
  if ( result < 0 ) then
    begin
    sIn.Free;
    Exit;
    end;

  result := StreamToStreamClass;
  case result of
  -999 : ShowMessage( 'StreamToStreamClass: Invalid File' );
    -3 : ShowMessage( 'StreamToStreamClass: Failed compress' );
    -2 : ShowMessage( 'StreamToStreamClass: Failed decompress' );
    -1 : ShowMessage( 'StreamToStreamClass: Size invalid or CompareMem failed' );
     0 : ShowMessage( 'StreamToStreamClass: Failed to Extract' );
//    else
//       ShowMessage( 'StreamToStreamClass: OK' );
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
