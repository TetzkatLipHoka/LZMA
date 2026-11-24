unit Bcj2;

// BCJ2 converter for x86/x64 code - Bcj2.c / Bcj2Enc.c of the LZMA SDK.
// One input stream <-> 4 streams (MAIN, CALL, JUMP, RC).

interface

{$WARN UNSAFE_TYPE OFF}

{$I LZMA.inc}

uses
  LzmaTypes;

const
  BCJ2_NUM_STREAMS = 4;
  BCJ2_STREAM_MAIN = 0;
  BCJ2_STREAM_CALL = 1;
  BCJ2_STREAM_JUMP = 2;
  BCJ2_STREAM_RC   = 3;

  BCJ2_DEC_STATE_ORIG  = BCJ2_NUM_STREAMS + 4;
  BCJ2_DEC_STATE_ERROR = BCJ2_NUM_STREAMS + 5;

  BCJ2_ENC_STATE_ORIG     = BCJ2_NUM_STREAMS;
  BCJ2_ENC_STATE_FINISHED = BCJ2_NUM_STREAMS + 1;

  BCJ2_ENC_FINISH_MODE_CONTINUE   = 0;
  BCJ2_ENC_FINISH_MODE_END_BLOCK  = 1;
  BCJ2_ENC_FINISH_MODE_END_STREAM = 2;

  BCJ2_ENC_RELAT_LIMIT_DEFAULT = Cardinal( $0F ) shl 24;
  BCJ2_ENC_FileSizeField_UNLIMITED = Int64( -1 ); // (UInt64)0 - 1

{$Z4}
type
  // Layout checked in Tests\pSizes.dpr (Win32 576/632, Win64 616/672)
  TCBcj2Dec = record
    bufs    : array [ 0..BCJ2_NUM_STREAMS-1 ] of PByte;
    lims    : array [ 0..BCJ2_NUM_STREAMS-1 ] of PByte;
    dest    : PByte;
    destLim : PByte;
    state   : Cardinal;
    ip      : Cardinal;
    temp    : Cardinal;
    range   : Cardinal;
    code    : Cardinal;
    probs   : array [ 0..2+256-1 ] of Word;
  end;

  TCBcj2Enc = record
    bufs              : array [ 0..BCJ2_NUM_STREAMS-1 ] of PByte;
    lims              : array [ 0..BCJ2_NUM_STREAMS-1 ] of PByte;
    src               : PByte;
    srcLim            : PByte;
    state             : Cardinal;
    finishMode        : Integer;
    context           : Byte;
    flushRem          : Byte;
    isFlushState      : Byte;
    cache             : Byte;
    range             : Cardinal;
    low               : Int64;   // C: UInt64
    cacheSize         : Int64;
    ip64              : Int64;
    fileIp64          : Int64;
    fileSize64_minus1 : Int64;
    relatLimit        : Cardinal;
    tempTarget        : Cardinal;
    tempPos           : Cardinal;
    temp              : array [ 0..7 ] of Byte;
    probs             : array [ 0..2+256-1 ] of Word;
  end;

{$IFDEF UNDERSCORE}
procedure _Bcj2Dec_Init( var p : TCBcj2Dec ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Bcj2Dec_Init'{$IFEND};
function _Bcj2Dec_Decode( var p : TCBcj2Dec ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Bcj2Dec_Decode'{$IFEND};
procedure _Bcj2Enc_Init( var p : TCBcj2Enc ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Bcj2Enc_Init'{$IFEND};
procedure _Bcj2Enc_Encode( var p : TCBcj2Enc ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Bcj2Enc_Encode'{$IFEND};
{$ELSE}
procedure Bcj2Dec_Init( var p : TCBcj2Dec ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Bcj2Dec_Init'{$IFEND};
function Bcj2Dec_Decode( var p : TCBcj2Dec ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Bcj2Dec_Decode'{$IFEND};
procedure Bcj2Enc_Init( var p : TCBcj2Enc ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Bcj2Enc_Init'{$IFEND};
procedure Bcj2Enc_Encode( var p : TCBcj2Enc ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Bcj2Enc_Encode'{$IFEND};
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\Bcj2.obj}
  {$L Win32\Bcj2Enc.obj}
{$else}
  {$L Win64\Bcj2.o}
  {$L Win64\Bcj2Enc.o}
{$endif}

end.
