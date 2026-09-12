using System;
using System.Windows;
using ConsoleMenu.Wpf.Services;
using ConsoleMenu.Wpf.Views;

namespace ConsoleMenu.Wpf
{
    public partial class MainWindow : Window
    {
        private HotkeyService _hotkey;
        private OverlayWindow _overlay;

        public MainWindow() { InitializeComponent(); Loaded += MainWindow_Loaded; }
        private void MainWindow_Loaded(object sender, RoutedEventArgs e) { if (ShellDataService.Settings == null) ShellDataService.Load(); ApplyTheme(); RegisterHotkey(); }

        public void ApplyTheme()
        {
            var isPs4 = string.Equals(ShellDataService.Settings?.Theme, "ps4", StringComparison.OrdinalIgnoreCase);
            var themeFile = isPs4 ? "PS4" : "PS5";
            var dictionary = new ResourceDictionary { Source = new Uri("pack://application:,,,/ConsoleMenu.Wpf;component/Themes/" + themeFile + ".xaml") };
            Application.Current.Resources.MergedDictionaries.Clear();
            Application.Current.Resources.MergedDictionaries.Add(dictionary);
            Root.Children.Clear();
            Root.Children.Add(isPs4 ? new Ps4ShellView() : new Ps5ShellView());
        }

        private void RegisterHotkey() { if (_hotkey != null) return; _hotkey = new HotkeyService(this, ShowOverlay); _hotkey.Register(HotkeyService.MOD_CONTROL | HotkeyService.MOD_SHIFT, 0x4D); }
        private void ShowOverlay() { if (_overlay == null) _overlay = new OverlayWindow(); if (!_overlay.IsVisible) _overlay.Show(); else _overlay.Activate(); }
        protected override void OnClosed(EventArgs e) { _hotkey?.Dispose(); base.OnClosed(e); }
    }
}