unit LzmaDec;

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}

{$I LZMA.inc}

uses
  LzmaTypes;

const
  LZMA_REQUIRED_INPUT_MAX = 20;

{$Z4}
type
  {$define _LZMA_PROB32}

  PCLzmaProb = ^TCLzmaProb;
  {$ifdef _LZMA_PROB32}
  TCLzmaProb = Cardinal;
  {$else}
  TCLzmaProb = Word;
  {$endif}

  TCLzmaProps = record
    lc, lp, pb: Cardinal;
    dicSize: Cardinal;
  end;

  ELzmaFinishMode = (
    LZMA_FINISH_ANY,   { finish at any point }
    LZMA_FINISH_END    { block must be finished at the end }
  );

  ELzmaStatus = (
    LZMA_STATUS_NOT_SPECIFIED,               { use main error code instead }
    LZMA_STATUS_FINISHED_WITH_MARK,          { stream was finished with end mark. }
    LZMA_STATUS_NOT_FINISHED,                { stream was not finished }
    LZMA_STATUS_NEEDS_MORE_INPUT,            { you must provide more input bytes }
    LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK  { there is probability that stream was finished without end mark }
  );

  TCLzmaDec = record
    prob: TCLzmaProps;
    prop: PCLzmaProb;
    dic: PByte;
    buf: PByte;
    range, code: Cardinal;
    dicPos: NativeInt;
    dicBufSize: NativeInt;
    processedPos: Cardinal;
    checkDicSize: Cardinal;
    state: Cardinal;
    reps: array[0..3] of Cardinal;
    remainLen: Cardinal;
    needFlush: Integer;
    needInitState: Integer;
    numProbs: Cardinal;
    tempBufSize: Cardinal;
    tempBuf: array[0..LZMA_REQUIRED_INPUT_MAX - 1] of Byte;
  end;

{$IFDEF UNDERSCORE}
function _LzmaDec_Allocate(var state: TCLzmaDec; const prop; propsSize: Cardinal; var alloc: TISzAlloc): Integer; cdecl; external {$IF CompilerVersion >= 22}name _PU + 'LzmaDec_Allocate'{$IFEND};
{$ELSE}
function LzmaDec_Allocate(var state: TCLzmaDec; const prop; propsSize: Cardinal; var alloc: TISzAlloc): Integer; cdecl; external {$IF CompilerVersion >= 22}name _PU + 'LzmaDec_Allocate'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaDec_Init(var p: TCLzmaDec); cdecl; external {$IF CompilerVersion >= 22}name _PU + 'LzmaDec_Init'{$IFEND};
{$ELSE}
procedure LzmaDec_Init(var p: TCLzmaDec); cdecl; external {$IF CompilerVersion >= 22}name _PU + 'LzmaDec_Init'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaDec_Free(var state: TCLzmaDec; var alloc: TISzAlloc); cdecl; external {$IF CompilerVersion >= 22}name _PU + 'LzmaDec_Free'{$IFEND};
{$ELSE}
procedure LzmaDec_Free(var state: TCLzmaDec; var alloc: TISzAlloc); cdecl; external {$IF CompilerVersion >= 22}name _PU + 'LzmaDec_Free'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaDec_DecodeToBuf(var p: TCLzmaDec; var dest; var destLen: NativeInt; const src; var srcLen: NativeInt; finishMode: ElzmaFinishMode; var status: ELzmaStatus): Integer; cdecl; external {$IF CompilerVersion >= 22}name _PU + 'LzmaDec_DecodeToBuf'{$IFEND};
{$ELSE}
function LzmaDec_DecodeToBuf(var p: TCLzmaDec; var dest; var destLen: NativeInt; const src; var srcLen: NativeInt; finishMode: ElzmaFinishMode; var status: ELzmaStatus): Integer; cdecl; external {$IF CompilerVersion >= 22}name _PU + 'LzmaDec_DecodeToBuf'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaDec_AllocateProbs(var p : TCLzmaDec; const props : PByte; propsSize : Cardinal; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaDec_AllocateProbs'{$IFEND};
{$ELSE}
function LzmaDec_AllocateProbs(var p : TCLzmaDec; const props : PByte; propsSize : Cardinal; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaDec_AllocateProbs'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaDec_FreeProbs(var p : TCLzmaDec; var alloc : TISzAlloc); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaDec_FreeProbs'{$IFEND};
{$ELSE}
procedure LzmaDec_FreeProbs(var p : TCLzmaDec; var alloc : TISzAlloc); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaDec_FreeProbs'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaDec_DecodeToDic(var p : TCLzmaDec; dicLimit : NativeInt; const src : PByte; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaDec_DecodeToDic'{$IFEND};
{$ELSE}
function LzmaDec_DecodeToDic(var p : TCLzmaDec; dicLimit : NativeInt; const src : PByte; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaDec_DecodeToDic'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaDec_InitDicAndState(var P : TCLzmaDec; initDic : Boolean; initState : Boolean); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaDec_InitDicAndState'{$IFEND};
{$ELSE}
procedure LzmaDec_InitDicAndState(var P : TCLzmaDec; initDic : Boolean; initState : Boolean); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaDec_InitDicAndState'{$IFEND};
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\LzmaDec.obj}
{$else}
  {$L Win64\LzmaDec.o}
{$endif}

end.


