param([string]$Root)
if (-not $Root) { $Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path } }
Set-Location -LiteralPath $Root
if (-not (Test-Path (Join-Path $Root 'ConsoleMenu.sln'))) { Write-Host '[XX] Run from project root'; exit 1 }

$utf8 = New-Object Text.UTF8Encoding($true)

function Write-Text([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, $utf8)
    Write-Host "[OK] $Path"
}

foreach ($d in @('src\ConsoleMenu.Wpf\Views','data\ui\ps5','data\ui\ps4','data\media\placeholders')) {
    New-Item -ItemType Directory -Path (Join-Path $Root $d) -Force | Out-Null
}

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Services\ShellDataService.cs') @'
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using ConsoleMenu.Core.GitHub;
using ConsoleMenu.Core.Models;
using ConsoleMenu.Core.Services;
using ConsoleMenu.Core.Storage;

namespace ConsoleMenu.Wpf.Services
{
    public static class ShellDataService
    {
        public static AppSettings Settings { get; private set; }
        public static GameStore Games { get; private set; }
        public static ProfileStore Profiles { get; private set; }
        public static StoreConfig Store { get; private set; }

        public static void Load()
        {
            Settings = JsonStore.Load(App.SettingsPath, new AppSettings());
            Games = JsonStore.Load(App.GamesPath, new GameStore());
            Profiles = JsonStore.Load(App.ProfilesPath, new ProfileStore());
            Store = JsonStore.Load(App.StorePath, new StoreConfig());
            if (Profiles.Profiles.Count == 0) { Profiles.Profiles.Add(new ProfileEntry { Name = "Default" }); SaveProfiles(); }
        }

        public static void SaveSettings() => JsonStore.Save(App.SettingsPath, Settings);
        public static void SaveGames() => JsonStore.Save(App.GamesPath, Games);
        public static void SaveProfiles() => JsonStore.Save(App.ProfilesPath, Profiles);

        public static ProfileEntry ActiveProfile()
        {
            if (Profiles == null || Profiles.Profiles.Count == 0) return null;
            if (string.IsNullOrWhiteSpace(Profiles.ActiveProfileId)) return Profiles.Profiles[0];
            return Profiles.Profiles.FirstOrDefault(x => x.Id == Profiles.ActiveProfileId) ?? Profiles.Profiles[0];
        }

        public static GameEntry AddGame(string exePath)
        {
            if (string.IsNullOrWhiteSpace(exePath) || !File.Exists(exePath)) return null;
            var game = new GameEntry { Title = Path.GetFileNameWithoutExtension(exePath), ExePath = exePath, WorkingDirectory = Path.GetDirectoryName(exePath), Source = "local" };
            Games.Games.Add(game); SaveGames(); return game;
        }

        public static void RemoveGame(GameEntry game) { if (game == null) return; Games.Games.Remove(game); SaveGames(); }

        public static bool LaunchGame(GameEntry game)
        {
            if (game == null || string.IsNullOrWhiteSpace(game.ExePath) || !File.Exists(game.ExePath)) return false;
            try
            {
                var psi = new ProcessStartInfo { FileName = game.ExePath, Arguments = game.Arguments ?? string.Empty, WorkingDirectory = string.IsNullOrWhiteSpace(game.WorkingDirectory) ? Path.GetDirectoryName(game.ExePath) : game.WorkingDirectory, UseShellExecute = false };
                using (var process = Process.Start(psi)) { if (Settings != null && Settings.EnableBoost) BoostService.ApplyBoost(process); }
                game.LastLaunchUtc = DateTime.UtcNow; SaveGames(); return true;
            } catch { return false; }
        }

        public static async Task<string> InstallLatestReleaseAsync()
        {
            if (Store == null || Store.Entries.Count == 0) return "No repositories in store.json.";
            var entry = Store.Entries[0];
            if (string.IsNullOrWhiteSpace(entry.Repo)) return "Repository is empty.";
            var client = new GitHubReleaseClient(string.IsNullOrWhiteSpace(Settings?.GitHubToken) ? null : Settings.GitHubToken);
            var releases = await client.GetReleasesAsync(entry.Repo);
            var release = releases?.FirstOrDefault();
            if (release == null) return "No releases found: " + entry.Repo;
            var asset = release.Assets?.FirstOrDefault(a => MatchesPattern(a.Name, entry.AssetPattern));
            var url = asset != null ? asset.DownloadUrl : release.ZipballUrl;
            if (string.IsNullOrWhiteSpace(url)) return "Release has no ZIP.";
            var installDir = string.IsNullOrWhiteSpace(Settings.InstallDirectory) ? Path.Combine(App.DataDirectory, "installs") : Settings.InstallDirectory;
            var safeRepo = string.Join("_", entry.Repo.Split('/'));
            var safeTag = Sanitize(release.TagName ?? "release");
            var dest = Path.Combine(installDir, safeRepo, safeTag);
            var zipPath = Path.Combine(installDir, safeRepo, safeTag + ".zip");
            await client.DownloadFileAsync(url, zipPath);
            SafeZip.ExtractToDirectory(zipPath, dest);
            File.Delete(zipPath);
            var exe = Directory.GetFiles(dest, "*.exe", SearchOption.AllDirectories).FirstOrDefault();
            var game = new GameEntry { Title = entry.Repo + " " + (release.TagName ?? ""), ExePath = exe ?? "", WorkingDirectory = exe != null ? Path.GetDirectoryName(exe) : dest, Source = "github" };
            Games.Games.Add(game); SaveGames();
            return exe != null ? "Installed: " + game.Title : "Installed, but no .exe found.";
        }

        private static bool MatchesPattern(string name, string pattern) { if (string.IsNullOrWhiteSpace(name)) return false; if (string.IsNullOrWhiteSpace(pattern)) return name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase); var ext = pattern.TrimStart('*'); return name.EndsWith(ext, StringComparison.OrdinalIgnoreCase); }
        private static string Sanitize(string value) { return string.Join("_", value.Split(Path.GetInvalidFileNameChars())); }
    }
}
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\ShellViewBase.cs') @'
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
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps5ShellView.xaml') @'
<UserControl x:Class="ConsoleMenu.Wpf.Views.Ps5ShellView"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:wv2="clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf"
             Background="Transparent">
    <Border Background="{DynamicResource App.Background}" CornerRadius="{DynamicResource Window.CornerRadius}" BorderBrush="#33FFFFFF" BorderThickness="1">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="64"/>
                <RowDefinition Height="64"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Grid x:Name="DragArea" Grid.Row="0" Background="Transparent">
                <Grid Margin="28,0,16,0">
                    <TextBlock Text="{DynamicResource Brand.Text}" FontSize="24" FontWeight="SemiBold" Foreground="{DynamicResource Text.Primary}" VerticalAlignment="Center"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <TextBlock x:Name="ProfileNameText" Margin="0,0,16,0" Foreground="{DynamicResource Text.Secondary}" VerticalAlignment="Center"/>
                        <TextBlock x:Name="ClockText" FontSize="18" Foreground="{DynamicResource Text.Primary}" VerticalAlignment="Center" Margin="0,0,18,0"/>
                        <Button x:Name="ThemeToggleButton" Content="Theme" Width="70" Margin="0,0,8,0"/>
                        <Button x:Name="MinimizeButton" Content="-" Width="42"/>
                        <Button x:Name="CloseButton" Content="X" Width="42"/>
                    </StackPanel>
                </Grid>
            </Grid>
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Disabled" HorizontalScrollBarVisibility="Auto">
                <StackPanel Orientation="Horizontal" Margin="28,0" VerticalAlignment="Center">
                    <Button x:Name="NavGamesButton" Content="Games" Margin="0,0,10,0"/>
                    <Button x:Name="NavStoreButton" Content="Store" Margin="0,0,10,0"/>
                    <Button x:Name="NavSettingsButton" Content="Settings" Margin="0,0,10,0"/>
                    <Button x:Name="NavProfilesButton" Content="Profiles" Margin="0,0,10,0"/>
                    <Button x:Name="NavMediaButton" Content="Media"/>
                </StackPanel>
            </ScrollViewer>
            <Grid Grid.Row="2" Margin="28,0,28,24">
                <Grid x:Name="HomePanel">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="160"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Border x:Name="HeroBackground" Grid.Row="0" CornerRadius="24" BorderBrush="#22FFFFFF" BorderThickness="1">
                        <Grid Margin="34">
                            <StackPanel VerticalAlignment="Bottom">
                                <TextBlock x:Name="HeroBadge" Text="LOCAL" FontSize="12" Foreground="{DynamicResource Text.Secondary}" Margin="0,0,0,8"/>
                                <TextBlock x:Name="HeroTitle" Text="Add a game" FontSize="46" FontWeight="Bold" Foreground="{DynamicResource Text.Primary}" TextWrapping="Wrap"/>
                                <TextBlock x:Name="HeroSubtitle" Text="Select an .exe to launch" FontSize="16" Foreground="{DynamicResource Text.Secondary}" Margin="0,8,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <ListBox x:Name="GamesList" Grid.Row="1" Margin="0,18,0,0">
                        <ListBox.ItemsPanel><ItemsPanelTemplate><StackPanel Orientation="Horizontal"/></ItemsPanelTemplate></ListBox.ItemsPanel>
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <Border Width="180" Height="104" Margin="0,0,14,0" CornerRadius="{DynamicResource Tile.CornerRadius}" Background="{DynamicResource Tile.Background}">
                                    <TextBlock Text="{Binding Title}" TextWrapping="Wrap" TextAlignment="Center" VerticalAlignment="Center" Margin="12" Foreground="{DynamicResource Text.Primary}"/>
                                </Border>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
                    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,16,0,0">
                        <Button x:Name="PlayButton" Content="Play" FontSize="18" Padding="28,10" Margin="0,0,12,0"/>
                        <Button x:Name="AddGameButton" Content="Add .exe" Margin="0,0,12,0"/>
                        <Button x:Name="RemoveGameButton" Content="Remove"/>
                    </StackPanel>
                </Grid>
                <Grid x:Name="WebPanel" Visibility="Collapsed">
                    <wv2:WebView2 x:Name="ShellWebView"/>
                    <Border x:Name="WebFallback" Visibility="Collapsed" CornerRadius="24" Background="{DynamicResource Tile.Background}">
                        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                            <TextBlock Text="WebView2 unavailable" FontSize="24" Foreground="{DynamicResource Text.Primary}" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                            <TextBlock Text="Open in browser" Foreground="{DynamicResource Text.Secondary}" HorizontalAlignment="Center" Margin="0,0,0,12"/>
                            <Button x:Name="OpenBrowserButton" Content="Open in browser" HorizontalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </Grid>
        </Grid>
    </Border>
</UserControl>
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps5ShellView.xaml.cs') @'
namespace ConsoleMenu.Wpf.Views { public partial class Ps5ShellView : ShellViewBase { public Ps5ShellView() { InitializeComponent(); } protected override string ThemeName => "ps5"; } }
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps4ShellView.xaml') @'
<UserControl x:Class="ConsoleMenu.Wpf.Views.Ps4ShellView"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:wv2="clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf"
             Background="Transparent">
    <Border Background="{DynamicResource App.Background}" BorderBrush="#33FFFFFF" BorderThickness="0">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="48"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Grid x:Name="DragArea" Grid.Row="0" Background="Transparent">
                <Grid Margin="36,0,18,0">
                    <TextBlock Text="{DynamicResource Brand.Text}" FontSize="20" FontWeight="Bold" Foreground="{DynamicResource Text.Primary}" VerticalAlignment="Center"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <TextBlock x:Name="ProfileNameText" Margin="0,0,14,0" Foreground="{DynamicResource Text.Secondary}" VerticalAlignment="Center"/>
                        <TextBlock x:Name="ClockText" FontSize="16" Foreground="{DynamicResource Text.Primary}" VerticalAlignment="Center" Margin="0,0,16,0"/>
                        <Button x:Name="ThemeToggleButton" Content="Theme" Width="64" Margin="0,0,8,0"/>
                        <Button x:Name="MinimizeButton" Content="-" Width="38"/>
                        <Button x:Name="CloseButton" Content="X" Width="38"/>
                    </StackPanel>
                </Grid>
            </Grid>
            <Grid Grid.Row="1">
                <Grid x:Name="HomePanel">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="150"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="36,14,36,0">
                        <Button x:Name="NavGamesButton" Content="Games" Margin="0,0,8,0"/>
                        <Button x:Name="NavStoreButton" Content="Store" Margin="0,0,8,0"/>
                        <Button x:Name="NavSettingsButton" Content="Settings" Margin="0,0,8,0"/>
                        <Button x:Name="NavProfilesButton" Content="Profiles" Margin="0,0,8,0"/>
                        <Button x:Name="NavMediaButton" Content="Media"/>
                    </StackPanel>
                    <ListBox x:Name="GamesList" Grid.Row="1" Margin="36,8">
                        <ListBox.ItemsPanel><ItemsPanelTemplate><StackPanel Orientation="Horizontal"/></ItemsPanelTemplate></ListBox.ItemsPanel>
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <Border Width="110" Height="110" Margin="0,0,12,0" CornerRadius="{DynamicResource Tile.CornerRadius}" Background="{DynamicResource Tile.Background}">
                                    <TextBlock Text="{Binding Title}" TextWrapping="Wrap" TextAlignment="Center" VerticalAlignment="Center" Margin="8" FontSize="12" Foreground="{DynamicResource Text.Primary}"/>
                                </Border>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
                    <Border x:Name="HeroBackground" Grid.Row="2" Margin="36,0,36,28" CornerRadius="8" BorderBrush="#22FFFFFF" BorderThickness="1">
                        <Grid Margin="24">
                            <StackPanel VerticalAlignment="Center">
                                <TextBlock x:Name="HeroBadge" Text="LOCAL" FontSize="11" Foreground="{DynamicResource Text.Secondary}" Margin="0,0,0,6"/>
                                <TextBlock x:Name="HeroTitle" Text="Add a game" FontSize="32" FontWeight="Bold" Foreground="{DynamicResource Text.Primary}" TextWrapping="Wrap"/>
                                <TextBlock x:Name="HeroSubtitle" Text="Select an .exe to launch" FontSize="14" Foreground="{DynamicResource Text.Secondary}" Margin="0,6,0,0" TextWrapping="Wrap"/>
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="PlayButton" Content="Launch" Margin="0,0,10,0"/>
                                    <Button x:Name="AddGameButton" Content="Add" Margin="0,0,10,0"/>
                                    <Button x:Name="RemoveGameButton" Content="Remove"/>
                                </StackPanel>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>
                <Grid x:Name="WebPanel" Visibility="Collapsed">
                    <wv2:WebView2 x:Name="ShellWebView"/>
                    <Border x:Name="WebFallback" Visibility="Collapsed" CornerRadius="8" Background="{DynamicResource Tile.Background}">
                        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                            <TextBlock Text="WebView2 unavailable" FontSize="24" Foreground="{DynamicResource Text.Primary}" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                            <TextBlock Text="Open in browser" Foreground="{DynamicResource Text.Secondary}" HorizontalAlignment="Center" Margin="0,0,0,12"/>
                            <Button x:Name="OpenBrowserButton" Content="Open in browser" HorizontalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </Grid>
        </Grid>
    </Border>
</UserControl>
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps4ShellView.xaml.cs') @'
namespace ConsoleMenu.Wpf.Views { public partial class Ps4ShellView : ShellViewBase { public Ps4ShellView() { InitializeComponent(); } protected override string ThemeName => "ps4"; } }
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\MainWindow.xaml') @'
<Window x:Class="ConsoleMenu.Wpf.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Console Menu" Height="760" Width="1280"
        WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" ResizeMode="CanResize">
    <Grid x:Name="Root"/>
</Window>
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\MainWindow.xaml.cs') @'
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
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Themes\PS5.xaml') @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                    xmlns:sys="clr-namespace:System;assembly=mscorlib">
    <sys:String x:Key="Brand.Text">PS5</sys:String>
    <LinearGradientBrush x:Key="App.Background" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#090D16" Offset="0"/>
        <GradientStop Color="#1B2A47" Offset="1"/>
    </LinearGradientBrush>
    <SolidColorBrush x:Key="Tile.Background" Color="#18FFFFFF"/>
    <SolidColorBrush x:Key="Tile.Selected" Color="#33FFFFFF"/>
    <SolidColorBrush x:Key="Text.Primary" Color="#F5F7FF"/>
    <SolidColorBrush x:Key="Text.Secondary" Color="#9FB3D1"/>
    <CornerRadius x:Key="Window.CornerRadius">16</CornerRadius>
    <CornerRadius x:Key="Tile.CornerRadius">14</CornerRadius>
    <Style TargetType="ListBox">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Foreground" Value="White"/>
    </Style>
    <Style TargetType="ListBoxItem">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Padding" Value="4"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ListBoxItem">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource Tile.CornerRadius}" Padding="{TemplateBinding Padding}">
                        <ContentPresenter/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Tile.Selected}"/></Trigger>
                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Tile.Background}"/></Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="Button">
        <Setter Property="Padding" Value="16,8"/>
        <Setter Property="Margin" Value="0,0,8,0"/>
        <Setter Property="Background" Value="#1FFFFFFF"/>
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource Tile.CornerRadius}" Padding="{TemplateBinding Padding}">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.92"/></Trigger>
                        <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.78"/></Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Themes\PS4.xaml') @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                    xmlns:sys="clr-namespace:System;assembly=mscorlib">
    <sys:String x:Key="Brand.Text">PS4</sys:String>
    <LinearGradientBrush x:Key="App.Background" StartPoint="0,0" EndPoint="0,1">
        <GradientStop Color="#00439C" Offset="0"/>
        <GradientStop Color="#00265E" Offset="1"/>
    </LinearGradientBrush>
    <SolidColorBrush x:Key="Tile.Background" Color="#220070CC"/>
    <SolidColorBrush x:Key="Tile.Selected" Color="#5500A0FF"/>
    <SolidColorBrush x:Key="Text.Primary" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="Text.Secondary" Color="#BBDEFB"/>
    <CornerRadius x:Key="Window.CornerRadius">0</CornerRadius>
    <CornerRadius x:Key="Tile.CornerRadius">6</CornerRadius>
    <Style TargetType="ListBox">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Foreground" Value="White"/>
    </Style>
    <Style TargetType="ListBoxItem">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Padding" Value="3"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ListBoxItem">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource Tile.CornerRadius}" Padding="{TemplateBinding Padding}">
                        <ContentPresenter/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Tile.Selected}"/></Trigger>
                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Tile.Background}"/></Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="Button">
        <Setter Property="Padding" Value="14,7"/>
        <Setter Property="Margin" Value="0,0,8,0"/>
        <Setter Property="Background" Value="#0070CC"/>
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource Tile.CornerRadius}" Padding="{TemplateBinding Padding}">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.92"/></Trigger>
                        <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.78"/></Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>
'@

function Write-UiPage([string]$Dir,[string]$Theme,[string]$Bg,[string]$Card,[string]$Accent,[string]$File,[string]$Title,[string]$Content) {
    $html = @"
<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<title>$Theme - $Title</title>
<style>
body { margin:0; min-height:100vh; font-family:Segoe UI,Arial; color:#fff; background:$Bg; }
.top { padding:18px 24px; font-size:24px; font-weight:600; color:$Accent; }
.card { margin:0 24px 24px; padding:24px; border-radius:18px; background:$Card; border:1px solid rgba(255,255,255,.12); }
button, select { background:rgba(255,255,255,.16); color:#fff; border:0; padding:10px 14px; border-radius:10px; margin:0 8px 8px 0; cursor:pointer; }
img { border-radius:12px; }
</style>
</head>
<body>
<div class='top'>$Theme - $Title</div>
<div class='card'>$Content</div>
<script>
function send(action, value) { if (window.chrome && chrome.webview) { chrome.webview.postMessage(JSON.stringify({ action: action, value: value || '' })); } }
</script>
</body>
</html>
"@
    Write-Text (Join-Path $Dir $File) $html
}

$storeContent = "<p>Store: GitHub releases and local .exe.</p><button onclick='send(`"installLatest`")'>Install latest release</button> <button onclick='send(`"addGame`")'>Add .exe</button> <button onclick='send(`"launchSelected`")'>Launch selected</button> <button onclick='send(`"refreshGames`")'>Refresh</button> <button onclick='send(`"home`")'>Back</button>"
$settingsContent = "<p>Shell theme</p><select onchange='send(`"setTheme`", this.value)'><option value='ps5'>PS5</option><option value='ps4'>PS4</option></select><br><button onclick='send(`"home`")'>Back</button>"
$profilesContent = "<p>Profiles</p><button onclick='send(`"addProfile`", `"Player 1`")'>Add Player 1</button> <button onclick='send(`"home`")'>Back</button>"
$mediaContent = "<p>Media placeholders in data/media/placeholders.</p><img style='width:320px;height:180px' src='../../media/placeholders/cover.svg'><br><button onclick='send(`"home`")'>Back</button>"

foreach ($theme in @(@{Name='ps5';Bg='linear-gradient(135deg,#090D16,#1B2A47)';Card='rgba(255,255,255,.08)';Accent='#FFFFFF'},@{Name='ps4';Bg='linear-gradient(180deg,#00439C,#00265E)';Card='rgba(0,112,204,.22)';Accent='#BBDEFB'})) {
    $dir = Join-Path $Root "data\ui\$($theme.Name)"
    Write-UiPage $dir $theme.Name.ToUpper() $theme.Bg $theme.Card $theme.Accent 'store.html' 'Store' $storeContent
    Write-UiPage $dir $theme.Name.ToUpper() $theme.Bg $theme.Card $theme.Accent 'settings.html' 'Settings' $settingsContent
    Write-UiPage $dir $theme.Name.ToUpper() $theme.Bg $theme.Card $theme.Accent 'profiles.html' 'Profiles' $profilesContent
    Write-UiPage $dir $theme.Name.ToUpper() $theme.Bg $theme.Card $theme.Accent 'media.html' 'Media' $mediaContent
}

$coverSvg = "<svg xmlns='http://www.w3.org/2000/svg' width='640' height='360'><rect width='100%' height='100%' fill='#111827'/><text x='50%' y='50%' fill='#FFFFFF' font-size='42' text-anchor='middle'>Cover</text></svg>"
$heroSvg = "<svg xmlns='http://www.w3.org/2000/svg' width='1920' height='1080'><rect width='100%' height='100%' fill='#0B1220'/><circle cx='1500' cy='180' r='280' fill='#1FFFFFFF'/><text x='50%' y='50%' fill='#FFFFFF' font-size='120' text-anchor='middle'>Hero</text></svg>"
$avatarSvg = "<svg xmlns='http://www.w3.org/2000/svg' width='128' height='128'><rect width='100%' height='100%' fill='#182742'/><circle cx='64' cy='48' r='24' fill='#FFFFFF'/><rect x='28' y='80' width='64' height='32' rx='16' fill='#FFFFFF'/></svg>"
$iconSvg = "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'><rect width='100%' height='100%' rx='14' fill='#111827'/><circle cx='32' cy='32' r='14' fill='#4FA3FF'/></svg>"
Write-Text (Join-Path $Root 'data\media\placeholders\cover.svg') $coverSvg
Write-Text (Join-Path $Root 'data\media\placeholders\hero.svg') $heroSvg
Write-Text (Join-Path $Root 'data\media\placeholders\avatar.svg') $avatarSvg
Write-Text (Join-Path $Root 'data\media\placeholders\icon.svg') $iconSvg

Write-Host ''
Write-Host '[i] Building...'
if (Get-Command dotnet -ErrorAction SilentlyContinue) { dotnet build (Join-Path $Root 'ConsoleMenu.sln') -v q --nologo } else { Write-Host '[i] dotnet not found' }