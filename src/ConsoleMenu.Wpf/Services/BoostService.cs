using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace ConsoleMenu.Wpf.Services
{
    public static class BoostService
    {
        [Flags]
        private enum EXECUTION_STATE : uint
        {
            ES_CONTINUOUS = 0x80000000,
            ES_SYSTEM_REQUIRED = 0x00000001,
            ES_DISPLAY_REQUIRED = 0x00000002
        }

        [DllImport("kernel32.dll")]
        private static extern EXECUTION_STATE SetThreadExecutionState(EXECUTION_STATE esFlags);

        public static void PreventSleep()
        {
            SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS
                | EXECUTION_STATE.ES_SYSTEM_REQUIRED
                | EXECUTION_STATE.ES_DISPLAY_REQUIRED);
        }

        public static void ApplyBoost(Process process)
        {
            try
            {
                PreventSleep();

                if (process != null)
                    process.PriorityClass = ProcessPriorityClass.High;
            }
            catch
            {
                // Безопасный буст не должен ронять запуск игры.
            }
        }
    }
}