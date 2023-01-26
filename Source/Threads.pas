unit Threads;

interface

{$WARN UNSAFE_TYPE OFF}

{$I LZMA.inc}

uses
  Windows, LzmaTypes;

{$Z4}
{$IF NOT Declared( msvcrt )}
const
  msvcrt = 'msvcrt.dll';
{$IFEND}

type
  TThread_Func_Type = Pointer;
  THREAD_FUNC_RET_TYPE = Pointer;

{$ifdef UNDERSCORE}
function __beginthreadex(__security_attr: Pointer; __stksize: Cardinal; __start: TThread_Func_Type; __arg: Pointer; __create_flags: Cardinal; var __thread_id: Cardinal): Cardinal; cdecl; external msvcrt name '_beginthreadex';
{$ELSE}
function _beginthreadex(__security_attr: Pointer; __stksize: Cardinal; __start: TThread_Func_Type; __arg: Pointer; __create_flags: Cardinal; var __thread_id: Cardinal): Cardinal; cdecl; external msvcrt name '_beginthreadex';
{$ENDIF}

{$ifdef UNDERSCORE}
function _Event_Reset(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Event_Reset'{$IFEND};
{$ELSE}
function Event_Reset(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Event_Reset'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _Event_Set(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Event_Set'{$IFEND};
{$ELSE}
function Event_Set(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Event_Set'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _Handle_WaitObject(h: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Handle_WaitObject'{$IFEND};
{$ELSE}
function Handle_WaitObject(h: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Handle_WaitObject'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _Semaphore_Release1(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Semaphore_Release1'{$IFEND};
{$ELSE}
function Semaphore_Release1(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Semaphore_Release1'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _HandlePtr_Close(var h: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'HandlePtr_Close'{$IFEND};
{$ELSE}
function HandlePtr_Close(var h: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'HandlePtr_Close'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _CriticalSection_Init(var p: TRTLCriticalSection): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'CriticalSection_Init'{$IFEND};
{$ELSE}
function CriticalSection_Init(var p: TRTLCriticalSection): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'CriticalSection_Init'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _AutoResetEvent_CreateNotSignaled(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'AutoResetEvent_CreateNotSignaled'{$IFEND};
{$ELSE}
function AutoResetEvent_CreateNotSignaled(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'AutoResetEvent_CreateNotSignaled'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _Semaphore_Create(var p: THandle; initCount: Cardinal; maxCount: Cardinal): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Semaphore_Create'{$IFEND};
{$ELSE}
function Semaphore_Create(var p: THandle; initCount: Cardinal; maxCount: Cardinal): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Semaphore_Create'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _Semaphore_OptCreateInit(var p: THandle; initCount: Cardinal; maxCount: Cardinal): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Semaphore_OptCreateInit'{$IFEND};
{$ELSE}
function Semaphore_OptCreateInit(var p: THandle; initCount: Cardinal; maxCount: Cardinal): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Semaphore_OptCreateInit'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _Thread_Create(var p: THandle; func: TThread_Func_Type; param: Pointer): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Create'{$IFEND};
{$ELSE}
function Thread_Create(var p: THandle; func: TThread_Func_Type; param: Pointer): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Create'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _Thread_Wait_Close(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Wait_Close'{$IFEND};
{$ELSE}
function Thread_Wait_Close(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Wait_Close'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _Thread_Create_With_Affinity(var p: THandle; func: TThread_Func_Type; param: Pointer; var affinity : Cardinal): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Create_With_Affinity'{$IFEND};
{$ELSE}
function Thread_Create_With_Affinity(var p: THandle; func: TThread_Func_Type; param: Pointer; var affinity : Cardinal): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Create_With_Affinity'{$IFEND};
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\Threads.obj}
{$else}
  {$L Win64\Threads.o}
{$endif}

end.


