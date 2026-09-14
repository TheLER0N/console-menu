using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Win32;
using ConsoleMenu.Core.Models;
using ConsoleMenu.Wpf.Services;
namespace ConsoleMenu.Wpf.Views
{
    public class ShellTile
    {
        public string Label { get; set; }
        public string Glyph { get; set; }
        public string Page { get; set; }
    }
    public abstract class ShellViewBase : UserControl
    {
        private static readonly JsonSerializerOptions JsonOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        private DispatcherTimer _clockTimer;
        private DispatcherTimer _toastTimer;
        private string _currentPage;
        private bool _webHooked;
        protected abstract string ThemeName { get; }
        protected bool IsPs4 { get { return string.Equals(ThemeName, "ps4", StringComparison.OrdinalIgnoreCase); } }
        protected ShellViewBase() { Loaded += OnShellLoaded; Unloaded += OnShellUnloaded; }
        protected virtual void OnShellLoaded(object sender, RoutedEventArgs e)
        {
            if (ShellDataService.Settings == null) ShellDataService.Load();
            WireControls();
            BuildContextMenu();
            StartClock();
            RefreshProfile();
            RefreshGames();
            ShowHome();
        }
        private void OnShellUnloaded(object sender, RoutedEventArgs e)
        {
            if (_clockTimer != null) { _clockTimer.Stop(); _clockTimer = null; }
            if (_toastTimer != null) { _toastTimer.Stop(); _toastTimer = null; }
        }
        protected T Find<T>(string name) where T : class { return FindName(name) as T; }
        protected Window GetWindow() { return Window.GetWindow(this); }
        protected object SelectedItem { get { var list = Find<ListBox>("GamesList"); return list == null ? null : list.SelectedItem; } }
        protected GameEntry SelectedGame { get { return SelectedItem as GameEntry; } }
        private void WireControls()
        {
            var gamesList = Find<ListBox>("GamesList");
            if (gamesList != null)
            {
                gamesList.SelectionChanged += (s, e) => UpdateHero();
                gamesList.MouseDoubleClick += (s, e) =>
                {
                    var sel = SelectedItem;
                    if (sel is GameEntry) Launch_Click(null, null);
                    else if (sel is ShellTile) ActivateTile((ShellTile)sel);
                    else AddGame_Click(null, null);
                };
            }
            WireClick("OpenBrowserButton", OpenBrowser_Click);
            WireClick("PlayButton", Launch_Click);
            WireClick("MenuButton", (s, e) => { var menu = ContextMenu; if (menu != null) { menu.PlacementTarget = this; menu.IsOpen = true; } });
            WireClick("GamesTab", (s, e) => ShowHome());
            WireClick("MediaTab", (s, e) => ShowWeb("media.html"));
            WireClick("SettingsButton", (s, e) => ShowWeb("settings.html"));
            WireClick("SearchButton", (s, e) => ShowToast("Not implemented"));
            WireClick("MailButton", (s, e) => ShowToast("Not implemented"));
            WireClick("FriendsButton", (s, e) => ShowToast("Not implemented"));
            WireClick("PartyButton", (s, e) => ShowToast("Not implemented"));
            WireClick("TrophyButton", (s, e) => ShowToast("Not implemented"));
            WireClick("PowerButton", (s, e) => OpenPowerMenu());
            WireClick("EjectButton", (s, e) => ShowToast("Not implemented"));
            WireClick("DetailsButton", (s, e) => ShowToast("Not implemented"));
            WireClick("CustomizeButton", (s, e) => ShowToast("Not implemented"));
            var drag = Find<FrameworkElement>("DragArea");
            if (drag != null) drag.MouseLeftButtonDown += (s, e) => DragWindow();
        }
        private void OpenPowerMenu()
{
var menu = new ContextMenu();
menu.Items.Add(MenuCmd("Rest Mode", (s, e) => { var mw = GetWindow() as MainWindow; if (mw != null) mw.EnterRestMode(); }));
menu.Items.Add(MenuCmd("Restart", (s, e) => ShowToast("Not implemented")));
menu.Items.Add(MenuCmd("Close", (s, e) => CloseWindow()));
menu.PlacementTarget = this;
menu.IsOpen = true;
}
private void WireClick(string name, RoutedEventHandler handler) { var button = Find<Button>(name); if (button != null) button.Click += handler; }
        protected void ActivateTile(ShellTile tile)
        {
            if (tile == null) return;
            if (!string.IsNullOrWhiteSpace(tile.Page)) ShowWeb(tile.Page);
            else ShowToast("Not implemented");
        }
        public void ShowToast(string text)
        {
            var host = Find<Border>("ToastHost");
            var label = Find<TextBlock>("ToastText");
            if (host == null || label == null) return;
            label.Text = text ?? string.Empty;
            host.Visibility = Visibility.Visible;
            if (_toastTimer == null)
            {
                _toastTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.5) };
                _toastTimer.Tick += (s, e) => { _toastTimer.Stop(); host.Visibility = Visibility.Collapsed; };
            }
            _toastTimer.Stop();
            _toastTimer.Start();
        }
        private void BuildContextMenu()
        {
            var menu = new ContextMenu();
            menu.Items.Add(MenuCmd("Games", (s, e) => ShowHome()));
            menu.Items.Add(MenuCmd("Store", (s, e) => ShowWeb("store.html")));
            menu.Items.Add(MenuCmd("Settings", (s, e) => ShowWeb("settings.html")));
            menu.Items.Add(MenuCmd("Profiles", (s, e) => ShowWeb("profiles.html")));
            menu.Items.Add(MenuCmd("Media", (s, e) => ShowWeb("media.html")));
            menu.Items.Add(new Separator());
            menu.Items.Add(MenuCmd("Start", (s, e) => Launch_Click(null, null)));
            menu.Items.Add(MenuCmd("Add .exe", (s, e) => AddGame_Click(null, null)));
            menu.Items.Add(MenuCmd("Remove", (s, e) => RemoveGame_Click(null, null)));
            menu.Items.Add(new Separator());
            menu.Items.Add(MenuCmd("Switch Theme", (s, e) => ToggleTheme_Click(null, null)));
            menu.Items.Add(MenuCmd("Window / Fullscreen", (s, e) => { var mw = GetWindow() as MainWindow; if (mw != null) mw.ToggleFullscreen(); }));
            menu.Items.Add(MenuCmd("Minimize", (s, e) => MinimizeWindow()));
            menu.Items.Add(MenuCmd("Close", (s, e) => CloseWindow()));
            ContextMenu = menu;
        }
        private static MenuItem MenuCmd(string header, RoutedEventHandler h) { var mi = new MenuItem { Header = header }; mi.Click += h; return mi; }
        private void StartClock()
        {
            var clock = Find<TextBlock>("ClockText");
            if (clock == null) return;
            clock.Text = DateTime.Now.ToString("h:mm tt", CultureInfo.InvariantCulture);
            _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _clockTimer.Tick += (s, e) => clock.Text = DateTime.Now.ToString("h:mm tt", CultureInfo.InvariantCulture);
            _clockTimer.Start();
        }
        private void RefreshProfile() { var profile = ShellDataService.ActiveProfile(); SetText("ProfileNameText", profile == null ? "" : profile.Name); }
        private void RefreshGames()
        {
            var list = Find<ListBox>("GamesList");
            if (list == null) return;
            var games = ShellDataService.Games.Games;
            var items = new List<object>();
            if (IsPs4) items.Add(new ShellTile { Label = "STORE", Glyph = "\uE719", Page = "store.html" });
            foreach (var g in games) items.Add(g);
            if (games.Count == 0) { var start = items.Count; for (var i = 0; i < 4; i++) items.Add(start + i); }
            if (IsPs4)
            {
                items.Add(new ShellTile { Label = "MY GAMES", Glyph = "\uE7FC" });
                items.Add(new ShellTile { Label = "VIDEO", Glyph = "\uE714" });
                items.Add(new ShellTile { Label = "MUSIC", Glyph = "\uE767" });
                items.Add(new ShellTile { Label = "INTERNET BROWSER", Glyph = "\uE774" });
            }
            else
            {
                items.Add(new ShellTile { Label = "Store", Glyph = "\uE719", Page = "store.html" });
                items.Add(new ShellTile { Label = "Media", Glyph = "\uE7B8", Page = "media.html" });
                items.Add(new ShellTile { Label = "Video", Glyph = "\uE714" });
                items.Add(new ShellTile { Label = "Music", Glyph = "\uE767" });
            }
            list.ItemsSource = items;
            if (games.Count > 0) list.SelectedIndex = IsPs4 ? 1 : 0;
            else { list.SelectedIndex = -1; UpdateHero(); }
        }
        protected virtual void UpdateHero()
        {
            var game = SelectedGame;
            SetText("HeroTitle", game == null ? "Add a game" : game.Title);
            SetText("HeroSubtitle", game == null ? "Right click for menu, double click a slot to add .exe" : game.ExePath);
            SetText("HeroBadge", game == null || string.IsNullOrWhiteSpace(game.Source) ? "LOCAL" : game.Source.ToUpperInvariant());
            UpdateHeroBackground(game);
        }
        private void UpdateHeroBackground(GameEntry game)
        {
            var path = ResolveHeroPath(game);
            var image = Find<Image>("HeroImage");
            var background = Find<Border>("HeroBackground");
            if (image != null)
            {
                if (path != null)
                {
                    try { image.Source = new BitmapImage(new Uri(path)); image.Visibility = Visibility.Visible; }
                    catch { image.Visibility = Visibility.Collapsed; }
                }
                else image.Visibility = Visibility.Collapsed;
            }
            if (background != null) background.Background = HashBrushFor(game == null ? "console-menu" : game.Title);
        }
        protected string ResolveHeroPath(GameEntry game)
        {
            if (game == null) return null;
            if (!string.IsNullOrWhiteSpace(game.HeroPath) && File.Exists(game.HeroPath)) return game.HeroPath;
            var dir = Path.Combine(App.DataDirectory, "media", game.Id);
            var jpg = Path.Combine(dir, "hero.jpg");
            if (File.Exists(jpg)) return jpg;
            var png = Path.Combine(dir, "hero.png");
            if (File.Exists(png)) return png;
            return null;
        }
        private static SolidColorBrush HashBrushFor(string seed)
        {
            var hash = Math.Abs((seed ?? "console-menu").GetHashCode());
            var r = (byte)(12 + hash % 46); var g = (byte)(18 + (hash / 7) % 58); var b = (byte)(32 + (hash / 13) % 76);
            return new SolidColorBrush(Color.FromArgb(255, r, g, b));
        }
        private void SetText(string name, string value) { var text = Find<TextBlock>(name); if (text != null) text.Text = value ?? string.Empty; }
        private void Launch_Click(object sender, RoutedEventArgs e) { var game = SelectedGame; if (game == null) { ShowToast("Select a game"); return; } if (!ShellDataService.LaunchGame(game)) ShowToast("Failed to launch: " + game.ExePath); }
        private void AddGame_Click(object sender, RoutedEventArgs e) { var dialog = new OpenFileDialog { Filter = "Executable (*.exe)|*.exe", Title = "Select game .exe" }; if (dialog.ShowDialog() != true) return; ShellDataService.AddGame(dialog.FileName); RefreshGames(); }
        private void RemoveGame_Click(object sender, RoutedEventArgs e) { var game = SelectedGame; if (game == null) return; ShellDataService.RemoveGame(game); RefreshGames(); }
        private void ToggleTheme_Click(object sender, RoutedEventArgs e) { var current = string.Equals(ShellDataService.Settings == null ? null : ShellDataService.Settings.Theme, "ps4", StringComparison.OrdinalIgnoreCase) ? "ps4" : "ps5"; ShellDataService.Settings.Theme = current == "ps4" ? "ps5" : "ps4"; ShellDataService.SaveSettings(); var mw = GetWindow() as MainWindow; if (mw != null) mw.ApplyTheme(); }
        public virtual void ShowHome() { _currentPage = null; SetPanels(true); }
        public virtual void ShowWeb(string page) { _currentPage = page; SetPanels(false); _ = EnsureWebViewAsync(page); }
        private void SetPanels(bool home)
        {
            SetVisibility("HomePanel", home);
            SetVisibility("WebPanel", !home);
            if (!home)
            {
                var web = Find<WebView2>("ShellWebView"); if (web != null) web.Visibility = Visibility.Visible;
                var fallback = Find<Border>("WebFallback"); if (fallback != null) fallback.Visibility = Visibility.Collapsed;
            }
        }
        private void SetVisibility(string name, bool visible) { var element = Find<UIElement>(name); if (element != null) element.Visibility = visible ? Visibility.Visible : Visibility.Collapsed; }
        private async Task EnsureWebViewAsync(string page)
        {
            var web = Find<WebView2>("ShellWebView"); if (web == null) return;
            try
            {
                if (web.CoreWebView2 == null) await web.EnsureCoreWebView2Async();
                if (web.CoreWebView2 == null) { ShowWebFallback(); return; }
                if (!_webHooked)
                {
                    web.CoreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived;
                    web.CoreWebView2.NavigationStarting += CoreWebView2_NavigationStarting;
                    _webHooked = true;
                }
                NavigateCore(page);
            }
            catch { ShowWebFallback(); }
        }
        private void NavigateCore(string page)
        {
            var web = Find<WebView2>("ShellWebView"); if (web == null || web.CoreWebView2 == null) return;
            var path = Path.Combine(App.DataDirectory, "ui", ThemeName, page);
            if (File.Exists(path)) web.CoreWebView2.Navigate(NavigateUri(path, page));
            else web.CoreWebView2.NavigateToString("<html><body style='margin:0;min-height:100vh;display:grid;place-items:center;background:#000;color:#fff'>" + page + " not found</body></html>");
        }
        private string NavigateUri(string path, string page)
        {
            var uri = new Uri(path).AbsoluteUri;
            if (string.Equals(page, "settings.html", StringComparison.OrdinalIgnoreCase)) uri += "?theme=" + Uri.EscapeDataString(ShellDataService.Settings == null ? "ps5" : ShellDataService.Settings.Theme);
            return uri;
        }
        private void ShowWebFallback() { var web = Find<WebView2>("ShellWebView"); if (web != null) web.Visibility = Visibility.Collapsed; var fallback = Find<Border>("WebFallback"); if (fallback != null) fallback.Visibility = Visibility.Visible; }
        private void OpenBrowser_Click(object sender, RoutedEventArgs e) { var page = _currentPage ?? "store.html"; var path = Path.Combine(App.DataDirectory, "ui", ThemeName, page); if (!File.Exists(path)) return; try { Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true }); } catch { } }
        private void DragWindow() { var window = GetWindow(); if (window != null && Mouse.LeftButton == MouseButtonState.Pressed) window.DragMove(); }
        private void MinimizeWindow() { var window = GetWindow(); if (window == null) return; window.Topmost = false; window.WindowState = WindowState.Minimized; }
        private void CloseWindow() { var window = GetWindow(); if (window != null) window.Close(); }
        private void InstallLatestRelease() { _ = InstallLatestReleaseAsync(); }
        private async Task InstallLatestReleaseAsync() { try { var result = await ShellDataService.InstallLatestReleaseAsync(); ShowToast(result); RefreshGames(); } catch (Exception ex) { ShowToast("Install error: " + ex.Message); } }
        private void ApplyThemeDeferred()
        {
            Dispatcher.BeginInvoke(new Action(() =>
            {
                try
                {
                    var mw = GetWindow() as MainWindow;
                    if (mw != null) mw.ApplyTheme();
                }
                catch (Exception ex) { ShowToast("Theme apply error: " + ex.Message); }
            }));
        }
        private void ApplyThemeValue(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return;
            ShellDataService.Settings.Theme = value;
            ShellDataService.SaveSettings();
            ApplyThemeDeferred();
        }
        private void CoreWebView2_NavigationStarting(object sender, CoreWebView2NavigationStartingEventArgs e)
        {
            try
            {
                if (string.IsNullOrEmpty(e.Uri)) return;
                var uri = new Uri(e.Uri);
                if (!uri.IsAbsoluteUri || !uri.IsFile) return;
                var query = uri.Query;
                if (string.IsNullOrEmpty(query) || query.IndexOf("cmd=settheme", StringComparison.OrdinalIgnoreCase) < 0) return;
                e.Cancel = true;
                var value = string.Empty;
                var idx = query.IndexOf("value=", StringComparison.OrdinalIgnoreCase);
                if (idx >= 0) value = Uri.UnescapeDataString(query.Substring(idx + 6).Split('&')[0]);
                ApplyThemeValue(value);
            }
            catch (Exception ex) { ShowToast("Nav error: " + ex.Message); }
        }
        private void CoreWebView2_WebMessageReceived(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                var message = JsonSerializer.Deserialize<WebMessage>(e.WebMessageAsJson, JsonOptions);
                if (message == null || string.IsNullOrWhiteSpace(message.Action)) return;
                switch (message.Action.ToLowerInvariant())
                {
                    case "close": CloseWindow(); break;
                    case "minimize": MinimizeWindow(); break;
                    case "home": ShowHome(); break;
                    case "store": ShowWeb("store.html"); break;
                    case "settings": ShowWeb("settings.html"); break;
                    case "profiles": ShowWeb("profiles.html"); break;
                    case "media": ShowWeb("media.html"); break;
                    case "addgame": AddGame_Click(null, null); break;
                    case "launchselected": Launch_Click(null, null); break;
                    case "installlatest": InstallLatestRelease(); break;
                    case "refreshgames": RefreshGames(); break;
                    case "settheme": ApplyThemeValue(message.Value); break;
                    case "addprofile": if (!string.IsNullOrWhiteSpace(message.Value)) { ShellDataService.Profiles.Profiles.Add(new ProfileEntry { Name = message.Value }); ShellDataService.SaveProfiles(); RefreshProfile(); } break;
                }
            }
            catch (Exception ex) { ShowToast("Web message error: " + ex.Message); }
        }
    }
    public sealed class WebMessage { [JsonPropertyName("action")] public string Action { get; set; } [JsonPropertyName("value")] public string Value { get; set; } }
    public sealed class NotEmptyToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type t, object p, CultureInfo c) { return string.IsNullOrWhiteSpace(value as string) ? Visibility.Collapsed : Visibility.Visible; }
        public object ConvertBack(object value, Type t, object p, CultureInfo c) { return DependencyProperty.UnsetValue; }
    }
    public sealed class EmptyToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type t, object p, CultureInfo c) { return string.IsNullOrWhiteSpace(value as string) ? Visibility.Visible : Visibility.Collapsed; }
        public object ConvertBack(object value, Type t, object p, CultureInfo c) { return DependencyProperty.UnsetValue; }
    }
    public sealed class HashToBrushConverter : IValueConverter
    {
        public object Convert(object value, Type t, object p, CultureInfo c)
        {
            var hash = Math.Abs((value as string ?? "console-menu").GetHashCode());
            var r = (byte)(12 + hash % 46); var g = (byte)(18 + (hash / 7) % 58); var b = (byte)(32 + (hash / 13) % 76);
            return new SolidColorBrush(Color.FromArgb(255, r, g, b));
        }
        public object ConvertBack(object value, Type t, object p, CultureInfo c) { return DependencyProperty.UnsetValue; }
    }
    public sealed class InitialsConverter : IValueConverter
    {
        public object Convert(object value, Type t, object p, CultureInfo c)
        {
            var title = (value as string ?? "").Trim();
            if (title.Length == 0) return "+";
            var words = title.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            var s = words[0].Substring(0, 1).ToUpperInvariant();
            if (words.Length > 1) s += words[1].Substring(0, 1).ToUpperInvariant();
            return s;
        }
        public object ConvertBack(object value, Type t, object p, CultureInfo c) { return DependencyProperty.UnsetValue; }
    }
    public sealed class TileLabelConverter : IValueConverter
    {
        public object Convert(object value, Type t, object p, CultureInfo c)
        {
            var game = value as GameEntry;
            if (game != null) return game.Title;
            var tile = value as ShellTile;
            if (tile != null) return tile.Label;
            return string.Empty;
        }
        public object ConvertBack(object value, Type t, object p, CultureInfo c) { return DependencyProperty.UnsetValue; }
    }
}