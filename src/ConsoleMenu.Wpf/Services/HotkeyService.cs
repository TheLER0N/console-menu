using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace ConsoleMenu.Wpf.Services
{
    public sealed class HotkeyService : IDisposable
    {
        public const uint MOD_ALT = 0x0001;
        public const uint MOD_CONTROL = 0x0002;
        public const uint MOD_SHIFT = 0x0004;

        private const int WM_HOTKEY = 0x0312;

        private readonly IntPtr _hwnd;
        private readonly HwndSource _source;
        private readonly Action _callback;
        private readonly List<int> _ids = new List<int>();

        private int _nextId = 0xC000;

        public HotkeyService(Window window, Action callback)
        {
            _callback = callback;
            _hwnd = new WindowInteropHelper(window).EnsureHandle();
            _source = HwndSource.FromHwnd(_hwnd);
            _source?.AddHook(WndProc);
        }

        public bool Register(uint modifiers, uint vk)
        {
            int id = _nextId++;

            if (RegisterHotKey(_hwnd, id, modifiers, vk))
            {
                _ids.Add(id);
                return true;
            }

            return false;
        }

        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY && _callback != null)
            {
                _callback();
                handled = true;
            }

            return IntPtr.Zero;
        }

        public void Dispose()
        {
            foreach (var id in _ids)
                UnregisterHotKey(_hwnd, id);

            _source?.RemoveHook(WndProc);
        }

        [DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    }
}