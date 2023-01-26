unit MtCoder;

interface

{$WARN UNSAFE_TYPE OFF}

{$I LZMA.inc}

uses
  Windows,
  LzmaTypes, Threads, MtDec;

{$Z4}
type
  TCLoopThread = record
    thread : THandle;
    startEvent : THandle;
    finishedEvent : THandle;
    stop : Integer;

    func : TTHREAD_FUNC_TYPE;
    param : Pointer;
    res : THREAD_FUNC_RET_TYPE;
  end;  

const
{$IFNDEF _7ZIP_ST}
  NUM_MT_CODER_THREADS_MAX = 32;
{$ELSE}
  NUM_MT_CODER_THREADS_MAX = 1;
{$ENDIF}

type
  TCMtProgress = record
    totalInSize : UInt64;
    totalOutSize : UInt64;
    progress : PICompressProgress;
    res : Integer;
    cs : TRTLCriticalSection;
    inSizes : Array [0..NUM_MT_CODER_THREADS_MAX-1] of UInt64;
    outSizes : Array [0..NUM_MT_CODER_THREADS_MAX-1] of UInt64;
  end;

  TCMtCoder = Pointer;

  TCMtThread = record
    mtCoder : TCMtCoder;
    outBuf : PByte;
    outBufSize : NativeInt;
    inBuf : PByte;
    inBufSize : NativeInt;
    index : Cardinal ;
    thread : TCLoopThread;

    stopReading : Boolean;
    stopWriting : Boolean;
    canRead : THandle;
    canWrite : THandle;
  end;

  IMtCoderCallbackFunc = function(p : Pointer; index : Cardinal; dest : PByte; var destSize : NativeInt; const src : PByte; srcSize : NativeInt; finished : Integer) : Integer; cdecl;

  IMtCoderCallback = record
    Code : IMtCoderCallbackFunc; 
  end;
  PIMtCoderCallback = ^IMtCoderCallback;

  CMtCoder = record
    blockSize : NativeInt;
    destBlockSize : NativeInt;
    numThreads : Cardinal;
    
    inStream : PISeqInStream;
    outStream : PISeqOutStream;
    progress : PICompressProgress;
    alloc : PISzAlloc;

    mtCallback : PIMtCoderCallback;
    cs : TRTLCriticalSection;
    res : Integer;

    mtProgress : TCMtProgress;
    threads : Array [0..NUM_MT_CODER_THREADS_MAX-1] of TCMtThread;
  end;

  TCMtProgressThunk = record
    vt : TICompressProgress;
    mtProgress : PCMtProgress;
    inSize : UInt64;
    outSize : UInt64;
  end;

(*
{$IFDEF UNDERSCORE}
procedure _LoopThread_Construct(var p : TCLoopThread); cdecl; external;
{$ELSE}
procedure LoopThread_Construct(var p : TCLoopThread); cdecl; external;
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LoopThread_Close(var p : TCLoopThread); cdecl; external;
{$ELSE}
procedure LoopThread_Close(var p : TCLoopThread); cdecl; external;
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LoopThread_Create(var p : TCLoopThread) : Cardinal; cdecl; external;
{$ELSE}
function LoopThread_Create(var p : TCLoopThread) : Cardinal; cdecl; external;
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LoopThread_StopAndWait(var p : TCLoopThread) : Cardinal; cdecl; external;
{$ELSE}
function LoopThread_StopAndWait(var p : TCLoopThread) : Cardinal; cdecl; external;
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LoopThread_StartSubThread(var p : TCLoopThread) : Cardinal; cdecl; external;
{$ELSE}
function LoopThread_StartSubThread(var p : TCLoopThread) : Cardinal; cdecl; external;
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LoopThread_WaitSubThread(var p : TCLoopThread) : Cardinal; cdecl; external;
{$ELSE}
function LoopThread_WaitSubThread(var p : TCLoopThread) : Cardinal; cdecl; external;
{$ENDIF}

{$IFDEF UNDERSCORE}
function _MtProgress_Set(var p : TCMtProgress; index : Cardinal; inSize : UInt64; outSize : UInt64) : Integer; cdecl; external;
{$ELSE}
function MtProgress_Set(var p : TCMtProgress; index : Cardinal; inSize : UInt64; outSize : UInt64) : Integer; cdecl; external;
{$ENDIF}
*)

{$IFDEF UNDERSCORE}
procedure _MtCoder_Construct(var p : TCMtCoder); cdecl; external;
{$ELSE}
procedure MtCoder_Construct(var p : TCMtCoder); cdecl; external;
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _MtCoder_Destruct(var p : TCMtCoder); cdecl; external;
{$ELSE}
procedure MtCoder_Destruct(var p : TCMtCoder); cdecl; external;
{$ENDIF}

{$IFDEF UNDERSCORE}
function _MtCoder_Code(var p : TCMtCoder) : Integer; cdecl; external;
{$ELSE}
function MtCoder_Code(var p : TCMtCoder) : Integer; cdecl; external;
{$ENDIF}

{$IFDEF UNDERSCORE}
function _MtProgressThunk_CreateVTable(var p : TCMtProgressThunk) : Integer; cdecl; external;
{$ELSE}
function MtProgressThunk_CreateVTable(var p : TCMtProgressThunk) : Integer; cdecl; external;
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\MtCoder.obj}
{$else}
  {$L Win64\MtCoder.o}
{$endif}

end.

