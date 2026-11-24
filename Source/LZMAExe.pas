unit LZMAExe;

// Executables (PE: EXE/DLL/BPL/OCX/SYS) packed in memory:
// branch filter (BCJ x86 / ARM64) + LZMA2, plus the BCJ2 4-stream split
// that 7z uses for x86/x64.
//
// Stream format of CompressExe (proposal, see README):
//   'lzx2' + 1 byte filter (0 none, 1 x86, 2 ARM64) + LZMA2 data as
//   CompressLZMA2( Header = False ) writes it (1 property byte + chunks).
// The filter is chosen from the content (PE machine field), not from a name.

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_CAST OFF}

{$I LZMA.inc}

uses
  Types;

type
  TExeFilter = ( efAuto, efNone, efX86, efARM64 );
  TBcj2Streams = array [ 0..3 ] of TByteDynArray; // MAIN, CALL, JUMP, RC

// efNone / efX86 (i386, AMD64) / efARM64 from the PE header, efNone otherwise
function DetectExeFilter( Source : PByte; Len : Cardinal ) : TExeFilter;

// In place; Filter efAuto is resolved with DetectExeFilter
procedure ExeFilterEncode( Data : PByte; Len : Cardinal; Filter : TExeFilter );
procedure ExeFilterDecode( Data : PByte; Len : Cardinal; Filter : TExeFilter );

// BCJ2 split (x86/x64). Decode: DestLen = original size; True = OK
function Bcj2Encode( Source : PByte; Len : Cardinal; var Streams : TBcj2Streams ) : Boolean;
function Bcj2Decode( const Streams : TBcj2Streams; Dest : PByte; DestLen : Cardinal ) : Boolean;

function CompressExe( Source : PByte; Len : Cardinal; var Compressed : TByteDynArray; Filter : TExeFilter = efAuto; Level : Integer = 9 ) : Int64;
function ExtractExe( Source : PByte; Len : Cardinal; var Decompressed : TByteDynArray ) : Int64;

implementation

uses
  LzmaTypes, Bra, Bcj2, LZMA2;

const
  HEADER_ = AnsiString( 'lzx2' );
  HEADER_LEN_ = Length( HEADER_ );
  FILTER_ID_ : array [ TExeFilter ] of Byte = ( 0, 0, 1, 2 );

  IMAGE_FILE_MACHINE_I386_  = $014C;
  IMAGE_FILE_MACHINE_AMD64_ = $8664;
  IMAGE_FILE_MACHINE_ARM64_ = $AA64;

type
  tHeader = Array [ 0..HEADER_LEN_-1 ] of AnsiChar;
  pHeader = ^tHeader;

function DetectExeFilter( Source : PByte; Len : Cardinal ) : TExeFilter;
var
  PEOfs : Cardinal;
  P     : PAnsiChar;
begin
  result := efNone;
  if ( Source = nil ) or ( Len < $40 ) then
    Exit;
  P := PAnsiChar( Source );
  if ( P[ 0 ] <> 'M' ) or ( P[ 1 ] <> 'Z' ) then
    Exit;
  PEOfs := PCardinal( P+$3C )^;
  if ( PEOfs > Len-6 ) then
    Exit;
  if ( PCardinal( P+PEOfs )^ <> $00004550 ) then // 'PE'#0#0
    Exit;
  case PWord( P+PEOfs+4 )^ of
    IMAGE_FILE_MACHINE_I386_, IMAGE_FILE_MACHINE_AMD64_ : result := efX86;
    IMAGE_FILE_MACHINE_ARM64_                           : result := efARM64;
  end;
end;

procedure ExeFilterEncode( Data : PByte; Len : Cardinal; Filter : TExeFilter );
var
  State : Cardinal;
begin
  if ( Data = nil ) or ( Len = 0 ) then
    Exit;
  if ( Filter = efAuto ) then
    Filter := DetectExeFilter( Data, Len );
  State := Z7_BRANCH_CONV_ST_X86_STATE_INIT_VAL;
  case Filter of
    efX86   : {$IFDEF UNDERSCORE}_z7_BranchConvSt_X86_Enc{$ELSE}z7_BranchConvSt_X86_Enc{$ENDIF}( Data, Len, 0, State );
    efARM64 : {$IFDEF UNDERSCORE}_z7_BranchConv_ARM64_Enc{$ELSE}z7_BranchConv_ARM64_Enc{$ENDIF}( Data, Len, 0 );
  end;
end;

procedure ExeFilterDecode( Data : PByte; Len : Cardinal; Filter : TExeFilter );
var
  State : Cardinal;
begin
  if ( Data = nil ) or ( Len = 0 ) then
    Exit;
  if ( Filter = efAuto ) then
    Filter := DetectExeFilter( Data, Len ); // only meaningful before encoding
  State := Z7_BRANCH_CONV_ST_X86_STATE_INIT_VAL;
  case Filter of
    efX86   : {$IFDEF UNDERSCORE}_z7_BranchConvSt_X86_Dec{$ELSE}z7_BranchConvSt_X86_Dec{$ENDIF}( Data, Len, 0, State );
    efARM64 : {$IFDEF UNDERSCORE}_z7_BranchConv_ARM64_Dec{$ELSE}z7_BranchConv_ARM64_Dec{$ENDIF}( Data, Len, 0 );
  end;
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function Bcj2Encode( Source : PByte; Len : Cardinal; var Streams : TBcj2Streams ) : Boolean;
var
  Enc  : TCBcj2Enc;
  i    : Integer;
  Used : NativeInt;
  NewSize : NativeInt;
begin
  result := False;
  for i := 0 to BCJ2_NUM_STREAMS-1 do
    SetLength( Streams[ i ], 0 );
  if ( Source = nil ) or ( Len = 0 ) then
    Exit;

  FillChar( Enc, SizeOf( Enc ), 0 );
  {$IFDEF UNDERSCORE}_Bcj2Enc_Init{$ELSE}Bcj2Enc_Init{$ENDIF}( Enc );
  for i := 0 to BCJ2_NUM_STREAMS-1 do
    begin
    // MAIN+CALL+JUMP = Len, RC is small; buffers grow on demand below
    if ( i = BCJ2_STREAM_MAIN ) then
      SetLength( Streams[ i ], ( Len+16 ) and not 3 )
    else
      SetLength( Streams[ i ], ( ( Len div 4 )+16 ) and not 3 );
    Enc.bufs[ i ] := @Streams[ i ][ 0 ];
    Enc.lims[ i ] := PByte( PAnsiChar( Enc.bufs[ i ] )+Length( Streams[ i ] ) );
    end;
  Enc.src               := Source;
  Enc.srcLim            := PByte( PAnsiChar( Source )+Len );
  Enc.fileIp64          := 0;
  Enc.fileSize64_minus1 := Int64( Len )-1;
  Enc.relatLimit        := BCJ2_ENC_RELAT_LIMIT_DEFAULT;
  Enc.finishMode        := BCJ2_ENC_FINISH_MODE_END_STREAM;

  repeat
    {$IFDEF UNDERSCORE}_Bcj2Enc_Encode{$ELSE}Bcj2Enc_Encode{$ENDIF}( Enc );
    if ( Enc.state < BCJ2_NUM_STREAMS ) then
      begin // output buffer full: double it (multiple of 4 for CALL/JUMP)
      i := Enc.state;
      Used := PAnsiChar( Enc.bufs[ i ] )-PAnsiChar( @Streams[ i ][ 0 ] );
      NewSize := ( Length( Streams[ i ] )*2+16 ) and not 3;
      SetLength( Streams[ i ], NewSize );
      Enc.bufs[ i ] := PByte( PAnsiChar( @Streams[ i ][ 0 ] )+Used );
      Enc.lims[ i ] := PByte( PAnsiChar( @Streams[ i ][ 0 ] )+NewSize );
      end
    else if ( Enc.state <> BCJ2_ENC_STATE_FINISHED ) then
      Exit; // ORIG = needs input, cannot happen with END_STREAM
  until ( Enc.state = BCJ2_ENC_STATE_FINISHED );

  for i := 0 to BCJ2_NUM_STREAMS-1 do
    SetLength( Streams[ i ], PAnsiChar( Enc.bufs[ i ] )-PAnsiChar( @Streams[ i ][ 0 ] ) );
  result := True;
end;

function Bcj2Decode( const Streams : TBcj2Streams; Dest : PByte; DestLen : Cardinal ) : Boolean;
var
  Dec : TCBcj2Dec;
  i   : Integer;
begin
  result := False;
  if ( Dest = nil ) or ( DestLen = 0 ) then
    Exit;
  if ( Cardinal( Length( Streams[ 0 ] )+Length( Streams[ 1 ] )+Length( Streams[ 2 ] ) ) <> DestLen ) then
    Exit;

  FillChar( Dec, SizeOf( Dec ), 0 );
  {$IFDEF UNDERSCORE}_Bcj2Dec_Init{$ELSE}Bcj2Dec_Init{$ENDIF}( Dec );
  for i := 0 to BCJ2_NUM_STREAMS-1 do
    if ( Length( Streams[ i ] ) > 0 ) then
      begin
      Dec.bufs[ i ] := @Streams[ i ][ 0 ];
      Dec.lims[ i ] := PByte( PAnsiChar( Dec.bufs[ i ] )+Length( Streams[ i ] ) );
      end;
  Dec.dest    := Dest;
  Dec.destLim := PByte( PAnsiChar( Dest )+DestLen );

  if ( {$IFDEF UNDERSCORE}_Bcj2Dec_Decode{$ELSE}Bcj2Dec_Decode{$ENDIF}( Dec ) <> SZ_OK ) then
    Exit;
  result := ( Dec.dest = Dec.destLim ) and
            ( Dec.bufs[ BCJ2_STREAM_MAIN ] = Dec.lims[ BCJ2_STREAM_MAIN ] ) and
            ( Dec.state = BCJ2_STREAM_MAIN ) and ( Dec.code = 0 ); // Bcj2Dec_IsMaybeFinished
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function CompressExe( Source : PByte; Len : Cardinal; var Compressed : TByteDynArray; Filter : TExeFilter = efAuto; Level : Integer = 9 ) : Int64;
var
  Work, Lz : TByteDynArray;
begin
  result := -100;
  SetLength( Compressed, 0 );
  if ( Source = nil ) or ( Len = 0 ) then
    Exit;
  if ( Filter = efAuto ) then
    Filter := DetectExeFilter( Source, Len );

  SetLength( Work, Len ); // the caller's data stays untouched
  Move( Source^, Work[ 0 ], Len );
  ExeFilterEncode( @Work[ 0 ], Len, Filter );

  result := CompressLZMA2( @Work[ 0 ], Len, Lz, False, Level );
  // CompressLZMA2 returns SZ_ERROR_* (positive) with an empty array on errors
  if ( result <= 0 ) or ( Length( Lz ) <> result ) then
    begin
    if ( result > 0 ) then
      result := -result;
    Exit;
    end;

  SetLength( Compressed, HEADER_LEN_+1+result );
  Move( HEADER_[ 1 ], Compressed[ 0 ], HEADER_LEN_ );
  Compressed[ HEADER_LEN_ ] := FILTER_ID_[ Filter ];
  Move( Lz[ 0 ], Compressed[ HEADER_LEN_+1 ], result );
  result := Length( Compressed );
end;

function ExtractExe( Source : PByte; Len : Cardinal; var Decompressed : TByteDynArray ) : Int64;
var
  Filter : TExeFilter;
begin
  result := -100;
  SetLength( Decompressed, 0 );
  if ( Source = nil ) or ( Len <= HEADER_LEN_+1 ) or ( pHeader( Source )^ <> HEADER_ ) then
    Exit;
  case PByte( PAnsiChar( Source )+HEADER_LEN_ )^ of
    0 : Filter := efNone;
    1 : Filter := efX86;
    2 : Filter := efARM64;
  else
    Exit; // unknown filter: refuse instead of returning garbage
  end;

  result := ExtractLZMA2( PByte( PAnsiChar( Source )+HEADER_LEN_+1 ), Len-Cardinal( HEADER_LEN_+1 ), Decompressed );
  // ExtractLZMA2 returns SZ_ERROR_* (positive) with an empty array on errors
  if ( result <= 0 ) or ( Length( Decompressed ) <> result ) then
    begin
    SetLength( Decompressed, 0 );
    if ( result > 0 ) then
      result := -result;
    Exit;
    end;
  ExeFilterDecode( @Decompressed[ 0 ], result, Filter );
end;

end.
