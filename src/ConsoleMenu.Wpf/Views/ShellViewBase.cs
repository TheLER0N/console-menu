using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Win32;
using ConsoleMenu.Core.Models;
using ConsoleMenu.Wpf.Services;

namespace ConsoleMenu.Wpf.Views
{
    public abstract class ShellViewBase : UserControl
    {
        private static readonly JsonSerializerOptions JsonOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        private DispatcherTimer _clockTimer;
        private string _currentPage;
        private bool _webHooked;

        protected abstract string ThemeName { get; }
        protected ShellViewBase() { Loaded += OnShellLoaded; Unloaded += OnShellUnloaded; }

        protected virtual void OnShellLoaded(object sender, RoutedEventArgs e) { if (ShellDataService.Settings == null) ShellDataService.Load(); WireControls(); StartClock(); RefreshProfile(); RefreshGames(); ShowHome(); }
        private void OnShellUnloaded(object sender, RoutedEventArgs e) { if (_clockTimer != null) { _clockTimer.Stop(); _clockTimer = null; } }
        protected T Find<T>(string name) where T : class { return FindName(name) as T; }
        protected Window GetWindow() { return Window.GetWindow(this); }
        protected GameEntry SelectedGame { get { var list = Find<ListBox>("GamesList"); return list?.SelectedItem as GameEntry; } }

        private void WireControls()
        {
            var gamesList = Find<ListBox>("GamesList"); if (gamesList != null) gamesList.SelectionChanged += GamesList_SelectionChanged;
            WireClick("PlayButton", Launch_Click); WireClick("AddGameButton", AddGame_Click); WireClick("RemoveGameButton", RemoveGame_Click);
            WireClick("NavGamesButton", (s, e) => ShowHome()); WireClick("NavStoreButton", (s, e) => ShowWeb("store.html"));
            WireClick("NavSettingsButton", (s, e) => ShowWeb("settings.html")); WireClick("NavProfilesButton", (s, e) => ShowWeb("profiles.html"));
            WireClick("NavMediaButton", (s, e) => ShowWeb("media.html")); WireClick("ThemeToggleButton", ToggleTheme_Click);
            WireClick("MinimizeButton", (s, e) => MinimizeWindow()); WireClick("CloseButton", (s, e) => CloseWindow());
            WireClick("OpenBrowserButton", OpenBrowser_Click);
            var drag = Find<FrameworkElement>("DragArea"); if (drag != null) drag.MouseLeftButtonDown += (s, e) => DragWindow();
        }
        private void WireClick(string name, RoutedEventHandler handler) { var button = Find<Button>(name); if (button != null) button.Click += handler; }

        private void StartClock() { var clock = Find<TextBlock>("ClockText"); if (clock == null) return; clock.Text = DateTime.Now.ToString("HH:mm"); _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) }; _clockTimer.Tick += (s, e) => clock.Text = DateTime.Now.ToString("HH:mm"); _clockTimer.Start(); }
        private void RefreshProfile() { var profile = ShellDataService.ActiveProfile(); SetText("ProfileNameText", profile?.Name ?? ""); }
        private void RefreshGames() { var list = Find<ListBox>("GamesList"); if (list == null) return; list.ItemsSource = null; list.ItemsSource = ShellDataService.Games.Games; if (list.Items.Count > 0) list.SelectedIndex = 0; else UpdateHero(); }
        private void GamesList_SelectionChanged(object sender, SelectionChangedEventArgs e) { UpdateHero(); }

        protected virtual void UpdateHero() { var game = SelectedGame; SetText("HeroTitle", game?.Title ?? "Add a game"); SetText("HeroSubtitle", game?.ExePath ?? "Select an .exe to launch"); SetText("HeroBadge", string.IsNullOrWhiteSpace(game?.Source) ? "LOCAL" : game.Source.ToUpperInvariant()); UpdateHeroBackground(game); }
        private void UpdateHeroBackground(GameEntry game) { var background = Find<Border>("HeroBackground"); if (background == null) return; var hash = Math.Abs((game?.Title ?? "console-menu").GetHashCode()); var r = (byte)(12 + hash % 46); var g = (byte)(18 + (hash / 7) % 58); var b = (byte)(32 + (hash / 13) % 76); background.Background = new SolidColorBrush(Color.FromArgb(255, r, g, b)); }
        private void SetText(string name, string value) { var text = Find<TextBlock>(name); if (text != null) text.Text = value ?? string.Empty; }

        private void Launch_Click(object sender, RoutedEventArgs e) { var game = SelectedGame; if (game == null) { MessageBox.Show("Select a game."); return; } if (!ShellDataService.LaunchGame(game)) MessageBox.Show("Failed to launch: " + game.ExePath); }
        private void AddGame_Click(object sender, RoutedEventArgs e) { var dialog = new OpenFileDialog { Filter = "Executable (*.exe)|*.exe", Title = "Select game .exe" }; if (dialog.ShowDialog() != true) return; ShellDataService.AddGame(dialog.FileName); RefreshGames(); }
        private void RemoveGame_Click(object sender, RoutedEventArgs e) { var game = SelectedGame; if (game == null) return; ShellDataService.RemoveGame(game); RefreshGames(); }
        private void ToggleTheme_Click(object sender, RoutedEventArgs e) { var current = string.Equals(ShellDataService.Settings?.Theme, "ps4", StringComparison.OrdinalIgnoreCase) ? "ps4" : "ps5"; ShellDataService.Settings.Theme = current == "ps4" ? "ps5" : "ps4"; ShellDataService.SaveSettings(); (GetWindow() as MainWindow)?.ApplyTheme(); }

        public virtual void ShowHome() { _currentPage = null; SetPanels(true); }
        public virtual void ShowWeb(string page) { _currentPage = page; SetPanels(false); _ = EnsureWebViewAsync(page); }
        private void SetPanels(bool home) { SetVisibility("HomePanel", home); SetVisibility("WebPanel", !home); if (!home) { var web = Find<WebView2>("ShellWebView"); if (web != null) web.Visibility = Visibility.Visible; var fallback = Find<Border>("WebFallback"); if (fallback != null) fallback.Visibility = Visibility.Collapsed; } }
        private void SetVisibility(string name, bool visible) { var element = Find<UIElement>(name); if (element != null) element.Visibility = visible ? Visibility.Visible : Visibility.Collapsed; }

        private async Task EnsureWebViewAsync(string page)
        {
            var web = Find<WebView2>("ShellWebView"); if (web == null) return;
            try { if (web.CoreWebView2 == null) await web.EnsureCoreWebView2Async(); if (web.CoreWebView2 == null) { ShowWebFallback(); return; } if (!_webHooked) { web.CoreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived; _webHooked = true; } NavigateCore(page); } catch { ShowWebFallback(); }
        }
        private void NavigateCore(string page) { var web = Find<WebView2>("ShellWebView"); if (web?.CoreWebView2 == null) return; var path = Path.Combine(App.DataDirectory, "ui", ThemeName, page); if (File.Exists(path)) web.CoreWebView2.Navigate(new Uri(path).AbsoluteUri); else web.CoreWebView2.NavigateToString("<html><body style='margin:0;min-height:100vh;display:grid;place-items:center;background:#000;color:#fff'>" + page + " not found</body></html>"); }
        private void ShowWebFallback() { var web = Find<WebView2>("ShellWebView"); if (web != null) web.Visibility = Visibility.Collapsed; var fallback = Find<Border>("WebFallback"); if (fallback != null) fallback.Visibility = Visibility.Visible; }
        private void OpenBrowser_Click(object sender, RoutedEventArgs e) { var page = _currentPage ?? "store.html"; var path = Path.Combine(App.DataDirectory, "ui", ThemeName, page); if (!File.Exists(path)) return; try { Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true }); } catch { } }

        private void DragWindow() { var window = GetWindow(); if (window != null && Mouse.LeftButton == MouseButtonState.Pressed) window.DragMove(); }
        private void MinimizeWindow() { var window = GetWindow(); if (window != null) window.WindowState = WindowState.Minimized; }
        private void CloseWindow() { var window = GetWindow(); if (window != null) window.Close(); }
        private void InstallLatestRelease() { _ = InstallLatestReleaseAsync(); }
        private async Task InstallLatestReleaseAsync() { try { var result = await ShellDataService.InstallLatestReleaseAsync(); MessageBox.Show(result); RefreshGames(); } catch (Exception ex) { MessageBox.Show("Install error: " + ex.Message); } }

        private void CoreWebView2_WebMessageReceived(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                var message = JsonSerializer.Deserialize<WebMessage>(e.WebMessageAsJson, JsonOptions);
                if (message == null || string.IsNullOrWhiteSpace(message.Action)) return;
                switch (message.Action.ToLowerInvariant())
                {
                    case "close": CloseWindow(); break; case "minimize": MinimizeWindow(); break; case "home": ShowHome(); break;
                    case "store": ShowWeb("store.html"); break; case "settings": ShowWeb("settings.html"); break;
                    case "profiles": ShowWeb("profiles.html"); break; case "media": ShowWeb("media.html"); break;
                    case "addgame": AddGame_Click(null, null); break; case "launchselected": Launch_Click(null, null); break;
                    case "installlatest": InstallLatestRelease(); break; case "refreshgames": RefreshGames(); break;
                    case "settheme": if (!string.IsNullOrWhiteSpace(message.Value)) { ShellDataService.Settings.Theme = message.Value; ShellDataService.SaveSettings(); (GetWindow() as MainWindow)?.ApplyTheme(); } break;
                    case "addprofile": if (!string.IsNullOrWhiteSpace(message.Value)) { ShellDataService.Profiles.Profiles.Add(new ProfileEntry { Name = message.Value }); ShellDataService.SaveProfiles(); RefreshProfile(); } break;
                }
            } catch { }
        }

        private class WebMessage { [JsonPropertyName("action")] public string Action { get; set; } [JsonPropertyName("value")] public string Value { get; set; } }
    }
}