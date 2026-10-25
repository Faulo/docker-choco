#include "shell32-proxy.cpp"
#include "MinHook/include/MinHook.h"

static unsigned int chocoHookStatus = 0;

extern "C" __declspec(dllexport) unsigned int WINAPI ChocoHookStatus()
{
    return chocoHookStatus;
}

extern "C" BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void*)
{
    if (reason != DLL_PROCESS_ATTACH) return TRUE;
    DisableThreadLibraryCalls(instance);
    if (MH_Initialize() != MH_OK) return TRUE;
    chocoHookStatus |= 1;
    void* findExecutable = reinterpret_cast<void*>(&::FindExecutableW);
    void* shellExecuteEx = reinterpret_cast<void*>(&::ShellExecuteExW);
    if (MH_CreateHook(findExecutable, reinterpret_cast<void*>(HookFindExecutableW), &hooks[0].Original) != MH_OK) return TRUE;
    chocoHookStatus |= 2;
    if (MH_CreateHook(shellExecuteEx, reinterpret_cast<void*>(HookShellExecuteExW), &hooks[1].Original) != MH_OK) return TRUE;
    chocoHookStatus |= 4;
    if (MH_QueueEnableHook(findExecutable) != MH_OK) return TRUE;
    if (MH_QueueEnableHook(shellExecuteEx) != MH_OK) return TRUE;
    if (MH_ApplyQueued() != MH_OK) return TRUE;
    chocoHookStatus |= 8;
    return TRUE;
}
