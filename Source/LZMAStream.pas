unit LZMAStream;

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_CAST OFF}

{$I LZMA.inc}

uses
  Classes, types,
  LzmaTypes, LzmaDec, LzmaEnc;

type
  {$IF NOT Declared( TBytes )}
  TBytes = TByteDynArray;
  {$IFEND}

  TLZMAEncoderStream = class( TStream )
  private
    FStream  : TStream;
    FEncoder : TCLzmaEncHandle;
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

  TLZMADecoderStream = class( TStream )
  private
    fError          : Integer;
    FCurrentDataLen : Cardinal;
    FData           : Array of Byte;
    FLzmaState      : TCLzmaDec;
    FStream         : TStream;
    FDecompressSize : Int64;
  public
    constructor Create( const Stream: TStream ); reintroduce;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    function Read( Buffer: TBytes; {$IF CompilerVersion >= 22}Offset,{$IFEND} Count: Longint ): Longint; {$IF CompilerVersion >= 22}override;{$ELSE}reintroduce;{$IFEND}
//    function Read( var Buffer; Count: Longint ): Longint; override;
    function Write( const Buffer; Count: Longint ): Longint; override;
    function Decompress( OutStream: TStream ) : Longint;
    property Error : Integer read fError;
  end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function CompressStreamLZMA( InStream : TStream; OutStream: TStream; Header : boolean = False ) : Int64; overload;
function CompressStreamLZMA( Source : PByte ; Len : Cardinal; OutStream: TStream; Header : boolean = False ) : Int64; overload;
function ExtractStreamLZMA( InStream : TStream; OutStream: TStream ) : Int64;

{$IFDEF TESTCASE}
function TestLZMAStream( FileName : string; Header : boolean = False; SaveDebugFiles : Boolean = False ) : Int64;
{$ENDIF TESTCASE}

implementation

{$IFDEF TESTCASE}
uses
  SysUtils, Dialogs;
{$ENDIF TESTCASE}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
type
  TLZMAReadProcRec = record
    Data : PByte;
    Size : NativeInt;
  end;
  pLZMAReadProcRec = ^TLZMAReadProcRec;

const
  HEADER_ = AnsiString( 'lzma' );
  HEADER_LEN_ = Length( HEADER_ );
type
  tHeader = Array [ 0..HEADER_LEN_-1 ] of AnsiChar;
  pHeader = ^tHeader;

function LzmaReadProc( p: PISeqInStream; buf: PByte; var size: NativeInt ): Integer; cdecl;
var
  R : PLZMAReadProcRec;
begin
  R := PLZMAReadProcRec( P.Stream );
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

function LzmaReadProcStream( p: PISeqInStream; buf: PByte; var size: NativeInt ): Integer; cdecl;
begin
  try
    size := TStream( P.Stream ).Read( buf^, size );
    Result := SZ_OK;
  except
    Result := SZ_ERROR_DATA;
  end;
end;

function LzmaWriteProc( p: PISeqOutStream; const buf: Pointer; size: NativeInt ): NativeInt; cdecl;
begin
  Result := TStream( P.Stream ).Write( buf^, size );
end;

//function LzmaProgressProc( p: PICompressProgress; inSize: UInt64; outSize: UInt64 ): Integer; cdecl;
//begin
//  if Assigned( p.Progress ) then
//    p.Progress( nil, TEncoding.Default.GetString( p.ZipHeader.FileName ), p.ZipHeader, inSize );
//  Result := SZ_OK;
//end;

constructor TLZMAEncoderStream.Create( const Stream: TStream; Header : boolean = False );
begin
  inherited Create;
  FStream := Stream;
  FEncoder := nil;
  fError := 0;
  fHeader := Header;
end;

procedure TLZMAEncoderStream.AfterConstruction;
var
  Props: TCLzmaEncProps;
  PropData: Array [ 0..LZMA_PROPS_SIZE-1 ] of Byte;
  PropDataLen: NativeInt;
begin
  inherited;
  FEncoder := {$IFDEF UNDERSCORE}_LzmaEnc_Create{$ELSE}LzmaEnc_Create{$ENDIF}( TISzAllocDefault );
  if NOT Assigned( FEncoder ) then
    begin
    fError := -100;
    Exit;
    end;

  {$IFDEF UNDERSCORE}_LzmaEncProps_Init{$ELSE}LzmaEncProps_Init{$ENDIF}( Props );
  Props.level := 9;
  Props.writeEndMark := 1;  

  fError := {$IFDEF UNDERSCORE}_LzmaEnc_SetProps{$ELSE}LzmaEnc_SetProps{$ENDIF}( FEncoder, Props );
  if ( fError <> SZ_OK ) then
    Exit;

  PropDataLen := LZMA_PROPS_SIZE;
  fError := {$IFDEF UNDERSCORE}_LzmaEnc_WriteProperties{$ELSE}LzmaEnc_WriteProperties{$ENDIF}( FEncoder, @PropData[ 0 ], PropDataLen );
  if ( fError <> SZ_OK ) then
    Exit;

  if fHeader then
    FStream.Write( HEADER_[ 1 ], HEADER_LEN_ );

  FStream.Write( PropDataLen, SizeOf( Word ) );
  FStream.Write( PropData[ 0 ], PropDataLen );
end;

procedure TLZMAEncoderStream.BeforeDestruction;
begin
  inherited;
  if Assigned( FEncoder ) then
    {$IFDEF UNDERSCORE}_LzmaEnc_Destroy{$ELSE}LzmaEnc_Destroy{$ENDIF}( FEncoder, TISzAllocDefault, TISzAllocDefault );
end;

function TLZMAEncoderStream.Read( var Buffer; Count: Longint ): Longint;
begin
  result := FStream.Read( Buffer, Count );
end;

function TLZMAEncoderStream.Write( const Buffer; Count: Longint ): Longint;
var
  R: TISeqInStream;
  W: TISeqOutStream;
begin
  R.Proc := LzmaReadProcStream;
  R.Stream := TStream( Buffer );

  W.Proc := LzmaWriteProc;
  W.Stream := FStream;

  fError := {$IFDEF UNDERSCORE}_LzmaEnc_Encode{$ELSE}LzmaEnc_Encode{$ENDIF}( FEncoder, @W, @R, nil, TISzAllocDefault, TISzAllocDefault );
  if ( fError <> SZ_OK ) then
    begin
    result := fError;
    Exit;
    end
  else
    Result := FStream.Size;
end;

function TLZMAEncoderStream.Compress( InStream: TStream ) : LongInt;
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

constructor TLZMADecoderStream.Create( const Stream: TStream );
begin
  inherited Create;
  FStream := Stream;
  fError := 0;
  FDecompressSize := 0;
  SetLength( FData, 0 );
end;

procedure TLZMADecoderStream.AfterConstruction;
var
  PropData: Array [ 0..LZMA_PROPS_SIZE-1 ] of Byte;
  PropDataLen: Word;
  Head : tHeader;
begin
  inherited;

  if ( FStream.Read( Head[ 0 ], HEADER_LEN_ ) <> HEADER_LEN_ ) then
    begin
    fError := -300;
    Exit;
    end;
  if ( Head <> HEADER_ ) then
    FStream.Position := FStream.Position-HEADER_LEN_;

  FStream.Read( PropDataLen, 2 ); // Properties size
  if ( PropDataLen <> LZMA_PROPS_SIZE ) then
    begin
    fError := -200;
    Exit;
    end;

  FStream.Read( PropData[ 0 ], PropDataLen );
  FillChar( FLzmaState, SizeOf( FLzmaState ), 0 );
  fError := {$IFDEF UNDERSCORE}_LzmaDec_Allocate{$ELSE}LzmaDec_Allocate{$ENDIF}( FLzmaState, PropData[ 0 ], PropDataLen, TISzAllocDefault );
  if ( fError <> SZ_OK ) then
    Exit;
  {$IFDEF UNDERSCORE}_LzmaDec_Init{$ELSE}LzmaDec_Init{$ENDIF}( FLzmaState );

  SetLength( FData, BufferSizeIn_ );
end;

procedure TLZMADecoderStream.BeforeDestruction;
begin
  {$IFDEF UNDERSCORE}_LzmaDec_Free{$ELSE}LzmaDec_Free{$ENDIF}( FLzmaState, TISzAllocDefault );
  FillChar( FLzmaState, SizeOf( FLzmaState ), 0 );
  SetLength( FData, 0 );
  inherited;
end;

function TLZMADecoderStream.Read( Buffer: TBytes; {$IF CompilerVersion >= 22}Offset,{$IFEND} Count: Longint ): Longint;
//function TLZMADecoderStream.Read( var Buffer; Count: Longint ): Longint;
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

    fError := {$IFDEF UNDERSCORE}_LzmaDec_DecodeToBuf{$ELSE}LzmaDec_DecodeToBuf{$ENDIF}( FLzmaState, Buffer[ BufferPos ], OutLen, FData[ 0 ], InLen, LZMA_FINISH_ANY, Status );
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

function TLZMADecoderStream.Write( const Buffer; Count: Longint ): Longint;
begin
  result := -1;
end;

function TLZMADecoderStream.Decompress( OutStream: TStream ) : Longint;
var
  Buffer: TBytes;
  BytesRead: Integer;
  res : Integer;
  Head : tHeader;
begin
  result := 0;
  res := -400;
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
function CompressStreamLZMA( InStream : TStream; OutStream: TStream; Header : boolean = False ) : Int64;
var
  Encoder : TCLzmaEncHandle;
  Props: TCLzmaEncProps;
  PropData: Array [ 0..LZMA_PROPS_SIZE-1 ] of Byte;
  PropDataLen: NativeInt;
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

  Encoder := {$IFDEF UNDERSCORE}_LzmaEnc_Create{$ELSE}LzmaEnc_Create{$ENDIF}( TISzAllocDefault );
  if NOT Assigned( Encoder ) then
    begin
    if ToSource then
      OutStream.free;
    Exit;
    end;

  {$IFDEF UNDERSCORE}_LzmaEncProps_Init{$ELSE}LzmaEncProps_Init{$ENDIF}( Props );
  Props.level := 9;
  Props.writeEndMark := 1;  

  result := {$IFDEF UNDERSCORE}_LzmaEnc_SetProps{$ELSE}LzmaEnc_SetProps{$ENDIF}( Encoder, Props );
  if ( result <> SZ_OK ) then
    begin
    if ToSource then
      OutStream.free;
    Exit;
    end;

  PropDataLen := LZMA_PROPS_SIZE;
  result := {$IFDEF UNDERSCORE}_LzmaEnc_WriteProperties{$ELSE}LzmaEnc_WriteProperties{$ENDIF}( Encoder, @PropData[ 0 ], PropDataLen );
  if ( result <> SZ_OK ) then
    begin
    if ToSource then
      OutStream.free;
    Exit;
    end;

  if Header then
    OutStream.Write( HEADER_[ 1 ], HEADER_LEN_ );
  OutStream.Write( PropDataLen, SizeOf( Word ) );
  OutStream.Write( PropData[ 0 ], PropDataLen );

  R.Proc := LzmaReadProcStream;
  R.Stream := InStream;

  W.Proc := LzmaWriteProc;
  W.Stream := OutStream;

  result := {$IFDEF UNDERSCORE}_LzmaEnc_Encode{$ELSE}LzmaEnc_Encode{$ENDIF}( Encoder, @W, @R, nil, TISzAllocDefault, TISzAllocDefault );
  if ( result = SZ_OK ) then
    Result := OutStream.Size;

  {$IFDEF UNDERSCORE}_LzmaEnc_Destroy{$ELSE}LzmaEnc_Destroy{$ENDIF}( Encoder, TISzAllocDefault, TISzAllocDefault );

  if ToSource then
    begin
    InStream.Position  := 0;
    InStream.Size      := 0;
    OutStream.Position := 0;
    InStream.CopyFrom( OutStream, OutStream.Size );
    OutStream.free;
    end;
end;

function CompressStreamLZMA( Source : PByte ; Len : Cardinal; OutStream: TStream; Header : boolean = False ) : Int64;
var
  Encoder : TCLzmaEncHandle;
  Props: TCLzmaEncProps;
  PropData: Array [ 0..LZMA_PROPS_SIZE-1 ] of Byte;
  PropDataLen: NativeInt;
  R: TISeqInStream;
  RS : TLZMAReadProcRec;
  W: TISeqOutStream;
begin
  result := -100;
  if NOT Assigned( Source ) OR ( Len = 0 ) then
    Exit;
  if NOT Assigned( OutStream ) then
    Exit;
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

  if Header then
    OutStream.Write( HEADER_[ 1 ], HEADER_LEN_ );
  OutStream.Write( PropDataLen, SizeOf( Word ) );
  OutStream.Write( PropData[ 0 ], PropDataLen );

  R.Proc := LzmaReadProc;
  RS.Data := Source;
  RS.Size := Len;
  R.Stream := @RS;

  W.Proc := LzmaWriteProc;
  W.Stream := OutStream;

  result := {$IFDEF UNDERSCORE}_LzmaEnc_Encode{$ELSE}LzmaEnc_Encode{$ENDIF}( Encoder, @W, @R, nil, TISzAllocDefault, TISzAllocDefault );
  if ( result = SZ_OK ) then
    Result := OutStream.Size;

  {$IFDEF UNDERSCORE}_LzmaEnc_Destroy{$ELSE}LzmaEnc_Destroy{$ENDIF}( Encoder, TISzAllocDefault, TISzAllocDefault );
end;

function ExtractStreamLZMA( InStream : TStream; OutStream: TStream ) : Int64;
var
  Head           : tHeader;
  ToSource       : Boolean;
  LzmaState      : TCLzmaDec;
  PropData       : Array [ 0..LZMA_PROPS_SIZE-1 ] of Byte;
  PropDataLen    : Word;

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

  InStream.Read( PropDataLen, SizeOf( PropDataLen ) ); // Properties size
  if ( PropDataLen <> LZMA_PROPS_SIZE ) then
    Exit;

  InStream.Read( PropData[ 0 ], PropDataLen );
  FillChar( LzmaState, SizeOf( LzmaState ), 0 );
  result := {$IFDEF UNDERSCORE}_LzmaDec_Allocate{$ELSE}LzmaDec_Allocate{$ENDIF}( LzmaState, PropData[ 0 ], PropDataLen, TISzAllocDefault );
  if ( result <> SZ_OK ) then
    begin
    if ToSource then
      OutStream.free;
    Exit;
    end;
  {$IFDEF UNDERSCORE}_LzmaDec_Init{$ELSE}LzmaDec_Init{$ENDIF}( LzmaState );

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
    result := {$IFDEF UNDERSCORE}_LzmaDec_DecodeToBuf{$ELSE}LzmaDec_DecodeToBuf{$ENDIF}( LzmaState, Buffer[ 0 ], OutLen, Data[ 0 ], InLen, LZMA_FINISH_ANY, Status );
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

  {$IFDEF UNDERSCORE}_LzmaDec_Free{$ELSE}LzmaDec_Free{$ENDIF}( LzmaState, TISzAllocDefault );
  FillChar( LzmaState, SizeOf( LzmaState ), 0 );
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
function CompressStreamLZMA( InStream, OutStream: TStream; Header : boolean = False ) : LongInt;
var
  Encoder: TLZMAEncoderStream;
begin
  Encoder := TLZMAEncoderStream.Create( OutStream, Header );
  try
    result := Encoder.Compress( InStream );
  finally
    Encoder.Free;
  end;
end;

function ExtractStreamLZMA2( InStream, OutStream: TStream ) : LongInt;
var
  Decoder: TLZMADecoderStream;
begin
  Decoder := TLZMADecoderStream.Create( InStream );
  try
    result := Decoder.Decompress( OutStream );
  finally
    Decoder.Free;
  end;
end;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
{$IFDEF TESTCASE}
function TestLZMAStream( FileName : string; Header : boolean = False; SaveDebugFiles : Boolean = False ) : Int64;
var
  sIn : TMemoryStream;

  function PointerToStream : Int64;
  var
    sCompress, sOut : TMemoryStream;
  begin
    sCompress := TMemoryStream.Create;
    result := CompressStreamLZMA( sIn.Memory, sIn.Size, sCompress, Header );
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
    result := ExtractStreamLZMA( sCompress, sOut );
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
    result := CompressStreamLZMA( sIn, sCompress, Header );
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
    result := ExtractStreamLZMA( sCompress, sOut );
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
    function CompressStreamLZMA( InStream, OutStream: TStream; Header : boolean = False ) : LongInt;
    var
      Encoder: TLZMAEncoderStream;
    begin
      Encoder := TLZMAEncoderStream.Create( OutStream, Header );
      try
        result := Encoder.Compress( InStream );
      finally
        Encoder.Free;
      end;
    end;

    function ExtractStreamLZMA( InStream, OutStream: TStream ) : LongInt;
    var
      Decoder: TLZMADecoderStream;
    begin
      Decoder := TLZMADecoderStream.Create( InStream );
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
    result := CompressStreamLZMA( sIn, sCompress, Header );
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
    result := ExtractStreamLZMA( sCompress, sOut );
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
