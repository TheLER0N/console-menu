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

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\ShellViewBase.cs') @'
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

        private void OnShellUnloaded(object sender, RoutedEventArgs e) { if (_clockTimer != null) { _clockTimer.Stop(); _clockTimer = null; } }

        protected T Find<T>(string name) where T : class { return FindName(name) as T; }
        protected Window GetWindow() { return Window.GetWindow(this); }
        protected GameEntry SelectedGame { get { var list = Find<ListBox>("GamesList"); return list == null ? null : list.SelectedItem as GameEntry; } }

        private void WireControls()
        {
            var gamesList = Find<ListBox>("GamesList");
            if (gamesList != null)
            {
                gamesList.SelectionChanged += GamesList_SelectionChanged;
                gamesList.MouseDoubleClick += (s, e) => { if (SelectedGame != null) Launch_Click(null, null); else AddGame_Click(null, null); };
            }
            WireClick("OpenBrowserButton", OpenBrowser_Click);
            var drag = Find<FrameworkElement>("DragArea");
            if (drag != null) drag.MouseLeftButtonDown += (s, e) => DragWindow();
        }

        private void WireClick(string name, RoutedEventHandler handler) { var button = Find<Button>(name); if (button != null) button.Click += handler; }

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

        private void StartClock() { var clock = Find<TextBlock>("ClockText"); if (clock == null) return; clock.Text = DateTime.Now.ToString("HH:mm"); _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) }; _clockTimer.Tick += (s, e) => clock.Text = DateTime.Now.ToString("HH:mm"); _clockTimer.Start(); }
        private void RefreshProfile() { var profile = ShellDataService.ActiveProfile(); SetText("ProfileNameText", profile == null ? "" : profile.Name); }

        private void RefreshGames()
        {
            var list = Find<ListBox>("GamesList"); if (list == null) return;
            var items = new List<object>();
            foreach (var g in ShellDataService.Games.Games) items.Add(g);
            while (items.Count < 4) items.Add(items.Count);
            list.ItemsSource = items;
            if (ShellDataService.Games.Games.Count > 0) list.SelectedIndex = 0; else UpdateHero();
        }

        private void GamesList_SelectionChanged(object sender, SelectionChangedEventArgs e) { UpdateHero(); }

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
            var background = Find<Border>("HeroBackground"); if (background == null) return;
            var hash = Math.Abs((game == null ? "console-menu" : game.Title).GetHashCode());
            var r = (byte)(12 + hash % 46); var g = (byte)(18 + (hash / 7) % 58); var b = (byte)(32 + (hash / 13) % 76);
            background.Background = new SolidColorBrush(Color.FromArgb(255, r, g, b));
        }

        private void SetText(string name, string value) { var text = Find<TextBlock>(name); if (text != null) text.Text = value ?? string.Empty; }

        private void Launch_Click(object sender, RoutedEventArgs e) { var game = SelectedGame; if (game == null) { MessageBox.Show("Select a game."); return; } if (!ShellDataService.LaunchGame(game)) MessageBox.Show("Failed to launch: " + game.ExePath); }
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
                if (!_webHooked) { web.CoreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived; _webHooked = true; }
                NavigateCore(page);
            }
            catch { ShowWebFallback(); }
        }

        private void NavigateCore(string page)
        {
            var web = Find<WebView2>("ShellWebView"); if (web == null || web.CoreWebView2 == null) return;
            var path = Path.Combine(App.DataDirectory, "ui", ThemeName, page);
            if (File.Exists(path)) web.CoreWebView2.Navigate(new Uri(path).AbsoluteUri);
            else web.CoreWebView2.NavigateToString("<html><body style='margin:0;min-height:100vh;display:grid;place-items:center;background:#000;color:#fff'>" + page + " not found</body></html>");
        }

        private void ShowWebFallback() { var web = Find<WebView2>("ShellWebView"); if (web != null) web.Visibility = Visibility.Collapsed; var fallback = Find<Border>("WebFallback"); if (fallback != null) fallback.Visibility = Visibility.Visible; }
        private void OpenBrowser_Click(object sender, RoutedEventArgs e) { var page = _currentPage ?? "store.html"; var path = Path.Combine(App.DataDirectory, "ui", ThemeName, page); if (!File.Exists(path)) return; try { Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true }); } catch { } }

        private void DragWindow() { var window = GetWindow(); if (window != null && Mouse.LeftButton == MouseButtonState.Pressed) window.DragMove(); }
        private void MinimizeWindow() { var window = GetWindow(); if (window == null) return; window.Topmost = false; window.WindowState = WindowState.Minimized; }
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
                    case "settheme": if (!string.IsNullOrWhiteSpace(message.Value)) { ShellDataService.Settings.Theme = message.Value; ShellDataService.SaveSettings(); var mw = GetWindow() as MainWindow; if (mw != null) mw.ApplyTheme(); } break;
                    case "addprofile": if (!string.IsNullOrWhiteSpace(message.Value)) { ShellDataService.Profiles.Profiles.Add(new ProfileEntry { Name = message.Value }); ShellDataService.SaveProfiles(); RefreshProfile(); } break;
                }
            }
            catch { }
        }

        private class WebMessage { [JsonPropertyName("action")] public string Action { get; set; } [JsonPropertyName("value")] public string Value { get; set; } }
    }

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
}
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
        private bool _fullscreen;

        public MainWindow() { InitializeComponent(); Loaded += MainWindow_Loaded; }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            if (ShellDataService.Settings == null) ShellDataService.Load();
            ApplyTheme();
            ApplyFullscreen();
            RegisterHotkey();
        }

        public void ApplyTheme()
        {
            var isPs4 = string.Equals(ShellDataService.Settings == null ? null : ShellDataService.Settings.Theme, "ps4", StringComparison.OrdinalIgnoreCase);
            var themeFile = isPs4 ? "PS4" : "PS5";
            var dictionary = new ResourceDictionary { Source = new Uri("pack://application:,,,/ConsoleMenu.Wpf;component/Themes/" + themeFile + ".xaml") };
            Application.Current.Resources.MergedDictionaries.Clear();
            Application.Current.Resources.MergedDictionaries.Add(dictionary);
            Root.Children.Clear();
            Root.Children.Add(isPs4 ? (UIElement)new Ps4ShellView() : (UIElement)new Ps5ShellView());
        }

        public void ApplyFullscreen()
        {
            WindowState = WindowState.Normal;
            Left = 0; Top = 0;
            Width = SystemParameters.PrimaryScreenWidth;
            Height = SystemParameters.PrimaryScreenHeight;
            Topmost = true;
            _fullscreen = true;
        }

        public void ToggleFullscreen()
        {
            if (_fullscreen)
            {
                Topmost = false;
                WindowState = WindowState.Normal;
                Width = 1280; Height = 760;
                Left = (SystemParameters.PrimaryScreenWidth - 1280) / 2;
                Top = (SystemParameters.PrimaryScreenHeight - 760) / 2;
                _fullscreen = false;
            }
            else ApplyFullscreen();
        }

        private void RegisterHotkey() { if (_hotkey != null) return; _hotkey = new HotkeyService(this, ShowOverlay); _hotkey.Register(HotkeyService.MOD_CONTROL | HotkeyService.MOD_SHIFT, 0x4D); }
        private void ShowOverlay() { if (_overlay == null) _overlay = new OverlayWindow(); if (!_overlay.IsVisible) _overlay.Show(); else _overlay.Activate(); }
        protected override void OnClosed(EventArgs e) { if (_hotkey != null) _hotkey.Dispose(); base.OnClosed(e); }
    }
}
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Themes\PS4.xaml') @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                    xmlns:sys="clr-namespace:System;assembly=mscorlib"
                    xmlns:m="clr-namespace:ConsoleMenu.Core.Models;assembly=ConsoleMenu.Core"
                    xmlns:views="clr-namespace:ConsoleMenu.Wpf.Views">
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
    <views:NotEmptyToVisibilityConverter x:Key="NotEmptyVis"/>
    <views:EmptyToVisibilityConverter x:Key="EmptyVis"/>
    <views:HashToBrushConverter x:Key="HashBrush"/>
    <views:InitialsConverter x:Key="Initials"/>
    <DataTemplate DataType="{x:Type m:GameEntry}">
        <Grid Width="150" Height="150">
            <Image Source="{Binding CoverPath}" Stretch="UniformToFill" Visibility="{Binding CoverPath, Converter={StaticResource NotEmptyVis}}"/>
            <Grid Visibility="{Binding CoverPath, Converter={StaticResource EmptyVis}}">
                <Rectangle Fill="{Binding Title, Converter={StaticResource HashBrush}}"/>
                <TextBlock Text="{Binding Title, Converter={StaticResource Initials}}" FontSize="42" FontWeight="Bold" Foreground="#DDFFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <Border VerticalAlignment="Bottom" Background="#99000000" Padding="6,3">
                <TextBlock Text="{Binding Title}" FontSize="11" Foreground="White" TextTrimming="CharacterEllipsis"/>
            </Border>
        </Grid>
    </DataTemplate>
    <DataTemplate DataType="{x:Type sys:Int32}">
        <Border Width="150" Height="150" Background="#10FFFFFF" BorderBrush="#30FFFFFF" BorderThickness="1">
            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <TextBlock Text="+" FontSize="40" Foreground="#88FFFFFF" HorizontalAlignment="Center"/>
                <TextBlock Text="&#x25B3; &#x25CB; &#x2715; &#x25A1;" FontSize="12" Foreground="#66FFFFFF" HorizontalAlignment="Center" Margin="0,6,0,0"/>
            </StackPanel>
        </Border>
    </DataTemplate>
    <Style TargetType="ListBox">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Foreground" Value="White"/>
    </Style>
    <Style TargetType="Button">
        <Setter Property="Padding" Value="14,7"/>
        <Setter Property="Margin" Value="0,0,8,0"/>
        <Setter Property="Background" Value="#0070CC"/>
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="Cursor" Value="Hand"/>
    </Style>
</ResourceDictionary>
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Themes\PS5.xaml') @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                    xmlns:sys="clr-namespace:System;assembly=mscorlib"
                    xmlns:m="clr-namespace:ConsoleMenu.Core.Models;assembly=ConsoleMenu.Core"
                    xmlns:views="clr-namespace:ConsoleMenu.Wpf.Views">
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
    <views:NotEmptyToVisibilityConverter x:Key="NotEmptyVis"/>
    <views:EmptyToVisibilityConverter x:Key="EmptyVis"/>
    <views:HashToBrushConverter x:Key="HashBrush"/>
    <views:InitialsConverter x:Key="Initials"/>
    <DataTemplate DataType="{x:Type m:GameEntry}">
        <Grid Width="150" Height="150">
            <Image Source="{Binding CoverPath}" Stretch="UniformToFill" Visibility="{Binding CoverPath, Converter={StaticResource NotEmptyVis}}"/>
            <Grid Visibility="{Binding CoverPath, Converter={StaticResource EmptyVis}}">
                <Rectangle Fill="{Binding Title, Converter={StaticResource HashBrush}}"/>
                <TextBlock Text="{Binding Title, Converter={StaticResource Initials}}" FontSize="42" FontWeight="Bold" Foreground="#DDFFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <Border VerticalAlignment="Bottom" Background="#99000000" Padding="6,3">
                <TextBlock Text="{Binding Title}" FontSize="11" Foreground="White" TextTrimming="CharacterEllipsis"/>
            </Border>
        </Grid>
    </DataTemplate>
    <DataTemplate DataType="{x:Type sys:Int32}">
        <Border Width="150" Height="150" Background="#10FFFFFF" BorderBrush="#30FFFFFF" BorderThickness="1" CornerRadius="10">
            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <TextBlock Text="+" FontSize="40" Foreground="#88FFFFFF" HorizontalAlignment="Center"/>
                <TextBlock Text="&#x25B3; &#x25CB; &#x2715; &#x25A1;" FontSize="12" Foreground="#66FFFFFF" HorizontalAlignment="Center" Margin="0,6,0,0"/>
            </StackPanel>
        </Border>
    </DataTemplate>
    <Style TargetType="ListBox">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Foreground" Value="White"/>
    </Style>
    <Style TargetType="Button">
        <Setter Property="Padding" Value="16,8"/>
        <Setter Property="Margin" Value="0,0,8,0"/>
        <Setter Property="Background" Value="#1FFFFFFF"/>
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="Cursor" Value="Hand"/>
    </Style>
</ResourceDictionary>
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps4ShellView.xaml') @'
<views:ShellViewBase x:Class="ConsoleMenu.Wpf.Views.Ps4ShellView"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:views="clr-namespace:ConsoleMenu.Wpf.Views"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:wv2="clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf"
             Background="Transparent">
    <Grid>
        <Grid.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                <GradientStop Color="#3A6BC8" Offset="0"/>
                <GradientStop Color="#274B9B" Offset="1"/>
            </LinearGradientBrush>
        </Grid.Background>
        <Grid.RowDefinitions>
            <RowDefinition Height="52"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Ellipse Grid.RowSpan="2" Width="1500" Height="1500" Stroke="#14FFFFFF" StrokeThickness="90" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="-520,-320,0,0" IsHitTestVisible="False"/>
        <Ellipse Grid.RowSpan="2" Width="1100" Height="1100" Stroke="#10FFFFFF" StrokeThickness="70" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,-420,-320" IsHitTestVisible="False"/>
        <Grid x:Name="DragArea" Grid.Row="0" Background="Transparent">
            <StackPanel Orientation="Horizontal" Margin="28,0,0,0" VerticalAlignment="Center">
                <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE7BF;" FontSize="20" Foreground="White" Margin="0,0,28,0"/>
                <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE783;" FontSize="20" Foreground="White"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,28,0" VerticalAlignment="Center">
                <Grid Margin="0,0,28,0">
                    <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE77B;" FontSize="20" Foreground="White"/>
                    <Border Background="#E3C93E" CornerRadius="7" Width="14" Height="14" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-7,-9,0">
                        <TextBlock Text="5" FontSize="9" Foreground="#111111" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                </Grid>
                <Ellipse Width="30" Height="30" Fill="#9FB3D1" Margin="0,0,8,0"/>
                <TextBlock x:Name="ProfileNameText" Text="Player" Foreground="White" FontSize="15" VerticalAlignment="Center" Margin="0,0,28,0"/>
                <Path Stroke="White" StrokeThickness="1.4" Fill="White" Width="18" Height="18" Stretch="Uniform" Margin="0,0,6,0"
                      Data="M4,1 h12 v5 a6,6 0 0 1 -12,0 z M9,12 h2 v3 h-2 z M6,16 h8 v2 h-8 z"/>
                <Border Background="#E3C93E" CornerRadius="8" Width="16" Height="16" Margin="0,0,28,0">
                    <TextBlock Text="14" FontSize="9" Foreground="#111111" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <TextBlock x:Name="ClockText" FontSize="16" Foreground="White" VerticalAlignment="Center"/>
            </StackPanel>
            <Rectangle Height="1" Fill="#33FFFFFF" VerticalAlignment="Bottom"/>
        </Grid>
        <Grid Grid.Row="1">
            <Grid x:Name="HomePanel">
                <Grid.RowDefinitions>
                    <RowDefinition Height="240"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0">
                    <ListBox x:Name="GamesList" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="24,0,0,0"
                             Background="Transparent" BorderThickness="0"
                             ScrollViewer.HorizontalScrollBarVisibility="Hidden" ScrollViewer.VerticalScrollBarVisibility="Disabled">
                        <ListBox.ItemsPanel><ItemsPanelTemplate><StackPanel Orientation="Horizontal"/></ItemsPanelTemplate></ListBox.ItemsPanel>
                        <ListBox.ItemContainerStyle>
                            <Style TargetType="ListBoxItem">
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="ListBoxItem">
                                            <Border x:Name="Bd" Width="150" Height="150" BorderThickness="2" BorderBrush="#00FFFFFF"
                                                    RenderTransformOrigin="0.5,0.5" Background="Transparent">
                                                <Grid>
                                                    <ContentPresenter/>
                                                    <Border x:Name="StartBar" Visibility="Collapsed" VerticalAlignment="Bottom" Height="32" Background="#D0000000">
                                                        <TextBlock Text="Start" Foreground="White" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                                    </Border>
                                                </Grid>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsSelected" Value="True">
                                                    <Setter TargetName="Bd" Property="BorderBrush" Value="#7FD4FF"/>
                                                    <Setter TargetName="StartBar" Property="Visibility" Value="Visible"/>
                                                    <Setter TargetName="Bd" Property="RenderTransform">
                                                        <Setter.Value><ScaleTransform ScaleX="1.28" ScaleY="1.28"/></Setter.Value>
                                                    </Setter>
                                                    <Setter TargetName="Bd" Property="Effect">
                                                        <Setter.Value><DropShadowEffect ShadowDepth="0" BlurRadius="18" Color="#7FD4FF" Opacity="0.85"/></Setter.Value>
                                                    </Setter>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </ListBox.ItemContainerStyle>
                    </ListBox>
                    <TextBlock x:Name="HeroTitle" Text="" FontSize="34" FontWeight="Light" Foreground="#EAF1FB"
                               VerticalAlignment="Center" HorizontalAlignment="Left" Margin="24,50,0,0"/>
                </Grid>
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <UniformGrid Columns="3" Margin="24,10,24,10">
                        <Border Background="#D8DBE0" Margin="8" Height="96">
                            <Grid Margin="10">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Top">
                                    <Rectangle Width="30" Height="30" Fill="#8899AA"/>
                                    <Rectangle Width="30" Height="30" Fill="#556677" Margin="4,0,0,0"/>
                                </StackPanel>
                                <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE7FC;" Foreground="#555555" HorizontalAlignment="Right" VerticalAlignment="Top"/>
                                <TextBlock VerticalAlignment="Bottom" TextWrapping="Wrap" FontSize="13" Foreground="#333333"><Run Foreground="#006BA8" FontWeight="SemiBold">Daniel Donizetti</Run><Run xml:space="preserve"> played </Run><Run FontWeight="SemiBold">RESOGUN</Run><Run>.</Run></TextBlock>
                            </Grid>
                        </Border>
                        <Border Background="#D8DBE0" Margin="8" Height="96">
                            <Grid Margin="10">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Top">
                                    <Rectangle Width="30" Height="30" Fill="#776688"/>
                                    <Rectangle Width="30" Height="30" Fill="#445566" Margin="4,0,0,0"/>
                                </StackPanel>
                                <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE7FC;" Foreground="#555555" HorizontalAlignment="Right" VerticalAlignment="Top"/>
                                <TextBlock VerticalAlignment="Bottom" TextWrapping="Wrap" FontSize="13" Foreground="#333333"><Run Foreground="#006BA8" FontWeight="SemiBold">Lukaz souza</Run><Run xml:space="preserve"> played </Run><Run FontWeight="SemiBold">Killzone Shadow Fall</Run><Run>.</Run></TextBlock>
                            </Grid>
                        </Border>
                        <Border Background="#D8DBE0" Margin="8" Height="96">
                            <Grid Margin="10">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Top">
                                    <Rectangle Width="30" Height="30" Fill="#99AA88"/>
                                    <Rectangle Width="30" Height="30" Fill="#667755" Margin="4,0,0,0"/>
                                </StackPanel>
                                <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE7FC;" Foreground="#555555" HorizontalAlignment="Right" VerticalAlignment="Top"/>
                                <TextBlock VerticalAlignment="Bottom" TextWrapping="Wrap" FontSize="13" Foreground="#333333"><Run Foreground="#006BA8" FontWeight="SemiBold">victorgomes1</Run><Run xml:space="preserve"> played </Run><Run FontWeight="SemiBold">FIFA 14</Run><Run>.</Run></TextBlock>
                            </Grid>
                        </Border>
                        <Border Background="#D8DBE0" Margin="8" Height="96">
                            <Grid Margin="10">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Top">
                                    <Rectangle Width="30" Height="30" Fill="#AA8877"/>
                                    <Rectangle Width="30" Height="30" Fill="#775544" Margin="4,0,0,0"/>
                                </StackPanel>
                                <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE7FC;" Foreground="#555555" HorizontalAlignment="Right" VerticalAlignment="Top"/>
                                <TextBlock VerticalAlignment="Bottom" TextWrapping="Wrap" FontSize="13" Foreground="#333333"><Run Foreground="#006BA8" FontWeight="SemiBold">Rick Ricardo</Run><Run xml:space="preserve"> played </Run><Run FontWeight="SemiBold">BATTLEFIELD 4</Run><Run>.</Run></TextBlock>
                            </Grid>
                        </Border>
                        <Border Background="#D8DBE0" Margin="8" Height="96">
                            <Grid Margin="10">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Top">
                                    <Rectangle Width="30" Height="30" Fill="#8899BB"/>
                                    <Rectangle Width="30" Height="30" Fill="#556688" Margin="4,0,0,0"/>
                                </StackPanel>
                                <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE7FC;" Foreground="#555555" HorizontalAlignment="Right" VerticalAlignment="Top"/>
                                <TextBlock VerticalAlignment="Bottom" TextWrapping="Wrap" FontSize="13" Foreground="#333333"><Run Foreground="#006BA8" FontWeight="SemiBold">Lukaz souza</Run><Run xml:space="preserve"> played </Run><Run FontWeight="SemiBold">ASSASSIN'S CREED IV</Run><Run>.</Run></TextBlock>
                            </Grid>
                        </Border>
                        <Border Background="#D8DBE0" Margin="8" Height="96">
                            <Grid Margin="10">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Top">
                                    <Rectangle Width="30" Height="30" Fill="#BB9966"/>
                                    <Rectangle Width="30" Height="30" Fill="#886633" Margin="4,0,0,0"/>
                                </StackPanel>
                                <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE7FC;" Foreground="#555555" HorizontalAlignment="Right" VerticalAlignment="Top"/>
                                <TextBlock VerticalAlignment="Bottom" TextWrapping="Wrap" FontSize="13" Foreground="#333333"><Run Foreground="#006BA8" FontWeight="SemiBold">Dean Alam</Run><Run xml:space="preserve"> played </Run><Run FontWeight="SemiBold">KNACK</Run><Run>.</Run></TextBlock>
                            </Grid>
                        </Border>
                    </UniformGrid>
                </ScrollViewer>
            </Grid>
            <Grid x:Name="WebPanel" Visibility="Collapsed">
                <wv2:WebView2 x:Name="ShellWebView"/>
                <Border x:Name="WebFallback" Visibility="Collapsed" Background="#26FFFFFF">
                    <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                        <TextBlock Text="WebView2 unavailable" FontSize="22" Foreground="White" HorizontalAlignment="Center" Margin="0,0,0,10"/>
                        <Button x:Name="OpenBrowserButton" Content="Open in browser" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
            </Grid>
        </Grid>
    </Grid>
</views:ShellViewBase>
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps5ShellView.xaml') @'
<views:ShellViewBase x:Class="ConsoleMenu.Wpf.Views.Ps5ShellView"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:views="clr-namespace:ConsoleMenu.Wpf.Views"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:wv2="clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf"
             Background="Transparent">
    <Border Background="{DynamicResource App.Background}" CornerRadius="{DynamicResource Window.CornerRadius}" BorderBrush="#33FFFFFF" BorderThickness="1">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="64"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Grid x:Name="DragArea" Grid.Row="0" Background="Transparent">
                <Grid Margin="28,0,16,0">
                    <TextBlock Text="{DynamicResource Brand.Text}" FontSize="24" FontWeight="SemiBold" Foreground="{DynamicResource Text.Primary}" VerticalAlignment="Center"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <TextBlock x:Name="ProfileNameText" Margin="0,0,16,0" Foreground="{DynamicResource Text.Secondary}" VerticalAlignment="Center"/>
                        <TextBlock x:Name="ClockText" FontSize="18" Foreground="{DynamicResource Text.Primary}" VerticalAlignment="Center"/>
                    </StackPanel>
                </Grid>
            </Grid>
            <Grid Grid.Row="1" Margin="28,0,28,24">
                <Grid x:Name="HomePanel">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="190"/>
                    </Grid.RowDefinitions>
                    <Border x:Name="HeroBackground" Grid.Row="0" CornerRadius="24" BorderBrush="#22FFFFFF" BorderThickness="1">
                        <Grid Margin="34">
                            <StackPanel VerticalAlignment="Bottom">
                                <TextBlock x:Name="HeroBadge" Text="LOCAL" FontSize="12" Foreground="{DynamicResource Text.Secondary}" Margin="0,0,0,8"/>
                                <TextBlock x:Name="HeroTitle" Text="Add a game" FontSize="46" FontWeight="Bold" Foreground="{DynamicResource Text.Primary}" TextWrapping="Wrap"/>
                                <TextBlock x:Name="HeroSubtitle" Text="Right click for menu, double click a slot to add .exe" FontSize="16" Foreground="{DynamicResource Text.Secondary}" Margin="0,8,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <ListBox x:Name="GamesList" Grid.Row="1" Margin="0,18,0,0" VerticalAlignment="Center"
                             Background="Transparent" BorderThickness="0"
                             ScrollViewer.HorizontalScrollBarVisibility="Hidden" ScrollViewer.VerticalScrollBarVisibility="Disabled">
                        <ListBox.ItemsPanel><ItemsPanelTemplate><StackPanel Orientation="Horizontal"/></ItemsPanelTemplate></ListBox.ItemsPanel>
                        <ListBox.ItemContainerStyle>
                            <Style TargetType="ListBoxItem">
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="ListBoxItem">
                                            <Border x:Name="Bd" Width="150" Height="150" BorderThickness="2" BorderBrush="#00FFFFFF"
                                                    RenderTransformOrigin="0.5,0.5" Background="Transparent">
                                                <ContentPresenter/>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsSelected" Value="True">
                                                    <Setter TargetName="Bd" Property="BorderBrush" Value="#7FD4FF"/>
                                                    <Setter TargetName="Bd" Property="RenderTransform">
                                                        <Setter.Value><ScaleTransform ScaleX="1.15" ScaleY="1.15"/></Setter.Value>
                                                    </Setter>
                                                    <Setter TargetName="Bd" Property="Effect">
                                                        <Setter.Value><DropShadowEffect ShadowDepth="0" BlurRadius="16" Color="#7FD4FF" Opacity="0.8"/></Setter.Value>
                                                    </Setter>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </ListBox.ItemContainerStyle>
                    </ListBox>
                </Grid>
                <Grid x:Name="WebPanel" Visibility="Collapsed">
                    <wv2:WebView2 x:Name="ShellWebView"/>
                    <Border x:Name="WebFallback" Visibility="Collapsed" CornerRadius="24" Background="{DynamicResource Tile.Background}">
                        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                            <TextBlock Text="WebView2 unavailable" FontSize="24" Foreground="{DynamicResource Text.Primary}" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                            <Button x:Name="OpenBrowserButton" Content="Open in browser" HorizontalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </Grid>
        </Grid>
    </Border>
</views:ShellViewBase>
'@

Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps4ShellView.xaml.cs') @'
using System.Windows.Controls;
using System.Windows.Media;

namespace ConsoleMenu.Wpf.Views
{
    public partial class Ps4ShellView : ShellViewBase
    {
        public Ps4ShellView() { InitializeComponent(); }
        protected override string ThemeName => "ps4";
        protected override void UpdateHero()
        {
            base.UpdateHero();
            var list = Find<ListBox>("GamesList");
            var title = Find<TextBlock>("HeroTitle");
            if (list == null || title == null) return;
            var idx = list.SelectedIndex < 0 ? 0 : list.SelectedIndex;
            title.RenderTransform = new TranslateTransform(idx * 150.0 + 178.0, 0);
            if (list.SelectedItem != null) list.ScrollIntoView(list.SelectedItem);
        }
    }
}
'@

Write-Host ''
Write-Host '[i] Building...'
if (Get-Command dotnet -ErrorAction SilentlyContinue) { dotnet build (Join-Path $Root 'ConsoleMenu.sln') -v q --nologo } else { Write-Host '[i] dotnet not found: build via Visual Studio' }