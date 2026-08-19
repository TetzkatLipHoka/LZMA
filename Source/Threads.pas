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

// SDK 26.02 sync: affinity is CAffinityMask (DWORD_PTR) BY VALUE, not var -
// the old var-Cardinal declaration passed a pointer instead of the mask.
{$ifdef UNDERSCORE}
function _Thread_Create_With_Affinity(var p: THandle; func: TThread_Func_Type; param: Pointer; affinity : NativeUInt): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Create_With_Affinity'{$IFEND};
{$ELSE}
function Thread_Create_With_Affinity(var p: THandle; func: TThread_Func_Type; param: Pointer; affinity : NativeUInt): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Create_With_Affinity'{$IFEND};
{$ENDIF}

// ~~~~~ Added with the SDK 26.02 sync ~~~~~
type
  TCThreadNextGroup = record
    NumGroups: Cardinal;
    NextGroup: Cardinal;
  end;

// On Windows, Thread_Close/Event_Close/Semaphore_Close are only C macros
// mapping to HandlePtr_Close - implemented as Pascal wrappers below.
{$ifdef UNDERSCORE}
function _Thread_Close(var p: THandle): Cardinal; cdecl;
function _Event_Close(var p: THandle): Cardinal; cdecl;
function _Semaphore_Close(var p: THandle): Cardinal; cdecl;
function _Thread_Create_With_Group(var p: THandle; func: TThread_Func_Type; param: Pointer; group: Cardinal; affinityMask: NativeUInt): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Create_With_Group'{$IFEND};
procedure _ThreadNextGroup_Init(var p: TCThreadNextGroup; numGroups: Cardinal; startGroup: Cardinal); cdecl; external {$IF CompilerVersion > 22}name _PU + 'ThreadNextGroup_Init'{$IFEND};
function _ThreadNextGroup_GetNext(var p: TCThreadNextGroup): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'ThreadNextGroup_GetNext'{$IFEND};
function _Semaphore_ReleaseN(var p: THandle; num: Cardinal): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Semaphore_ReleaseN'{$IFEND};
function _ManualResetEvent_Create(var p: THandle; signaled: Integer): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'ManualResetEvent_Create'{$IFEND};
function _ManualResetEvent_CreateNotSignaled(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'ManualResetEvent_CreateNotSignaled'{$IFEND};
function _AutoResetEvent_Create(var p: THandle; signaled: Integer): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'AutoResetEvent_Create'{$IFEND};
function _AutoResetEvent_OptCreate_And_Reset(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'AutoResetEvent_OptCreate_And_Reset'{$IFEND};
{$ELSE}
function Thread_Close(var p: THandle): Cardinal; cdecl;
function Event_Close(var p: THandle): Cardinal; cdecl;
function Semaphore_Close(var p: THandle): Cardinal; cdecl;
function Thread_Create_With_Group(var p: THandle; func: TThread_Func_Type; param: Pointer; group: Cardinal; affinityMask: NativeUInt): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Thread_Create_With_Group'{$IFEND};
procedure ThreadNextGroup_Init(var p: TCThreadNextGroup; numGroups: Cardinal; startGroup: Cardinal); cdecl; external {$IF CompilerVersion > 22}name _PU + 'ThreadNextGroup_Init'{$IFEND};
function ThreadNextGroup_GetNext(var p: TCThreadNextGroup): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'ThreadNextGroup_GetNext'{$IFEND};
function Semaphore_ReleaseN(var p: THandle; num: Cardinal): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Semaphore_ReleaseN'{$IFEND};
function ManualResetEvent_Create(var p: THandle; signaled: Integer): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'ManualResetEvent_Create'{$IFEND};
function ManualResetEvent_CreateNotSignaled(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'ManualResetEvent_CreateNotSignaled'{$IFEND};
function AutoResetEvent_Create(var p: THandle; signaled: Integer): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'AutoResetEvent_Create'{$IFEND};
function AutoResetEvent_OptCreate_And_Reset(var p: THandle): Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'AutoResetEvent_OptCreate_And_Reset'{$IFEND};
{$ENDIF}

implementation

// SDK 26.02 sync, Win64/COFF: MSVC objects call the WinAPI through dllimport
// slots (__imp_* = pointer to the function, indirect call). The slots are
// recreated here as initialized pointer variables; __C_specific_handler
// (SEH personality from __try in Threads.c) is exported natively by ntdll.
{$ifNdef Win32}
function CloseHandle_(hObject: THandle): LongBool; stdcall; external 'kernel32.dll' name 'CloseHandle';
function CreateEventW_(lpEventAttributes: Pointer; bManualReset, bInitialState: LongBool; lpName: PWideChar): THandle; stdcall; external 'kernel32.dll' name 'CreateEventW';
function CreateSemaphoreW_(lpSemaphoreAttributes: Pointer; lInitialCount, lMaximumCount: Integer; lpName: PWideChar): THandle; stdcall; external 'kernel32.dll' name 'CreateSemaphoreW';
procedure DeleteCriticalSection_(var lpCriticalSection: TRTLCriticalSection); stdcall; external 'kernel32.dll' name 'DeleteCriticalSection';
procedure EnterCriticalSection_(var lpCriticalSection: TRTLCriticalSection); stdcall; external 'kernel32.dll' name 'EnterCriticalSection';
function GetLastError_: Cardinal; stdcall; external 'kernel32.dll' name 'GetLastError';
function GetModuleHandleW_(lpModuleName: PWideChar): THandle; stdcall; external 'kernel32.dll' name 'GetModuleHandleW';
function GetProcAddress_(hModule: THandle; lpProcName: PAnsiChar): Pointer; stdcall; external 'kernel32.dll' name 'GetProcAddress';
procedure InitializeCriticalSection_(var lpCriticalSection: TRTLCriticalSection); stdcall; external 'kernel32.dll' name 'InitializeCriticalSection';
procedure LeaveCriticalSection_(var lpCriticalSection: TRTLCriticalSection); stdcall; external 'kernel32.dll' name 'LeaveCriticalSection';
function ReleaseSemaphore_(hSemaphore: THandle; lReleaseCount: Integer; lpPreviousCount: Pointer): LongBool; stdcall; external 'kernel32.dll' name 'ReleaseSemaphore';
function ResetEvent_(hEvent: THandle): LongBool; stdcall; external 'kernel32.dll' name 'ResetEvent';
function ResumeThread_(hThread: THandle): Cardinal; stdcall; external 'kernel32.dll' name 'ResumeThread';
function SetEvent_(hEvent: THandle): LongBool; stdcall; external 'kernel32.dll' name 'SetEvent';
function SetThreadAffinityMask_(hThread: THandle; dwThreadAffinityMask: NativeUInt): NativeUInt; stdcall; external 'kernel32.dll' name 'SetThreadAffinityMask';
function WaitForSingleObject_(hHandle: THandle; dwMilliseconds: Cardinal): Cardinal; stdcall; external 'kernel32.dll' name 'WaitForSingleObject';
procedure __C_specific_handler; external 'ntdll.dll' name '__C_specific_handler';
var
  __imp_CloseHandle: Pointer = @CloseHandle_;
  __imp_CreateEventW: Pointer = @CreateEventW_;
  __imp_CreateSemaphoreW: Pointer = @CreateSemaphoreW_;
  __imp_DeleteCriticalSection: Pointer = @DeleteCriticalSection_;
  __imp_EnterCriticalSection: Pointer = @EnterCriticalSection_;
  __imp_GetLastError: Pointer = @GetLastError_;
  __imp_GetModuleHandleW: Pointer = @GetModuleHandleW_;
  __imp_GetProcAddress: Pointer = @GetProcAddress_;
  __imp_InitializeCriticalSection: Pointer = @InitializeCriticalSection_;
  __imp_LeaveCriticalSection: Pointer = @LeaveCriticalSection_;
  __imp_ReleaseSemaphore: Pointer = @ReleaseSemaphore_;
  __imp_ResetEvent: Pointer = @ResetEvent_;
  __imp_ResumeThread: Pointer = @ResumeThread_;
  __imp_SetEvent: Pointer = @SetEvent_;
  __imp_SetThreadAffinityMask: Pointer = @SetThreadAffinityMask_;
  __imp_WaitForSingleObject: Pointer = @WaitForSingleObject_;
{$endif}

{$ifdef Win32}
  {$L Win32\Threads.obj}
{$else}
  {$L Win64\Threads.o}
{$endif}

// C-side macros mapping to HandlePtr_Close (Threads.h) - real functions here:
{$ifdef UNDERSCORE}
function _Thread_Close(var p: THandle): Cardinal; cdecl;
begin
  Result := _HandlePtr_Close(p);
end;

function _Event_Close(var p: THandle): Cardinal; cdecl;
begin
  Result := _HandlePtr_Close(p);
end;

function _Semaphore_Close(var p: THandle): Cardinal; cdecl;
begin
  Result := _HandlePtr_Close(p);
end;
{$ELSE}
function Thread_Close(var p: THandle): Cardinal; cdecl;
begin
  Result := HandlePtr_Close(p);
end;

function Event_Close(var p: THandle): Cardinal; cdecl;
begin
  Result := HandlePtr_Close(p);
end;

function Semaphore_Close(var p: THandle): Cardinal; cdecl;
begin
  Result := HandlePtr_Close(p);
end;
{$ENDIF}

end.


