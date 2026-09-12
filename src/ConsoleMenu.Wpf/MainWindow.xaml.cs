using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Microsoft.Win32;
using ConsoleMenu.Core.GitHub;
using ConsoleMenu.Core.Models;
using ConsoleMenu.Core.Services;
using ConsoleMenu.Core.Storage;
using ConsoleMenu.Wpf.Services;

namespace ConsoleMenu.Wpf
{
    public class NavItem
    {
        public string Glyph { get; set; }
        public string Label { get; set; }
    }

    public partial class MainWindow : Window
    {
        private bool _loading;

        private AppSettings _settings;
        private StoreConfig _store;
        private GameStore _games;
        private ProfileStore _profiles;
        private List<GitHubRelease> _releases = new List<GitHubRelease>();

        private HotkeyService _hotkey;
        private OverlayWindow _overlay;
        private DispatcherTimer _clockTimer;

        public MainWindow()
        {
            InitializeComponent();
            Loaded += MainWindow_Loaded;
        }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            LoadData();
            ApplyTheme();
            InitThemeCombo();
            InitStoreCombo();
            BuildNav();
            StartClock();
            RegisterHotkey();
            _ = InitStoreViewAsync();
        }

        private void LoadData()
        {
            _settings = JsonStore.Load(App.SettingsPath, new AppSettings());
            _store = JsonStore.Load(App.StorePath, new StoreConfig());
            _games = JsonStore.Load(App.GamesPath, new GameStore());
            _profiles = JsonStore.Load(App.ProfilesPath, new ProfileStore());

            if (_profiles.Profiles.Count == 0)
            {
                _profiles.Profiles.Add(new ProfileEntry { Name = "Default" });
                SaveProfiles();
            }

            ProfileNameText.Text = _profiles.Profiles[0].Name;
            GamesList.ItemsSource = _games.Games;
            ProfilesList.ItemsSource = _profiles.Profiles;
            EnableBoostCheck.IsChecked = _settings.EnableBoost;
            GitHubTokenBox.Text = _settings.GitHubToken;
        }

        private void BuildNav()
        {
            NavList.ItemsSource = new List<NavItem>
            {
                new NavItem { Glyph = "\uE7FC", Label = "Игры" },
                new NavItem { Glyph = "\uE7BF", Label = "Магазин" },
                new NavItem { Glyph = "\uE713", Label = "Настройки" },
                new NavItem { Glyph = "\uE77B", Label = "Профили" },
                new NavItem { Glyph = "\uE8B2", Label = "Медиа" }
            };

            NavList.SelectedIndex = 0;
        }

        private void NavList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            ShowPanel(NavList.SelectedIndex);
        }

        private void ShowPanel(int index)
        {
            GamesPanel.Visibility = index == 0 ? Visibility.Visible : Visibility.Collapsed;
            StorePanel.Visibility = index == 1 ? Visibility.Visible : Visibility.Collapsed;
            SettingsPanel.Visibility = index == 2 ? Visibility.Visible : Visibility.Collapsed;
            ProfilesPanel.Visibility = index == 3 ? Visibility.Visible : Visibility.Collapsed;
            MediaPanel.Visibility = index == 4 ? Visibility.Visible : Visibility.Collapsed;
        }

        private void StartClock()
        {
            ClockText.Text = DateTime.Now.ToString("HH:mm");
            _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _clockTimer.Tick += (s, e) => ClockText.Text = DateTime.Now.ToString("HH:mm");
            _clockTimer.Start();
        }

        private void InitThemeCombo()
        {
            _loading = true;
            ThemeCombo.SelectedIndex = string.Equals(_settings.Theme, "ps4", StringComparison.OrdinalIgnoreCase) ? 1 : 0;
            _loading = false;
        }

        private void ApplyTheme()
        {
            var theme = string.Equals(_settings.Theme, "ps4", StringComparison.OrdinalIgnoreCase) ? "PS4" : "PS5";

            var dictionary = new ResourceDictionary
            {
                Source = new Uri("pack://application:,,,/ConsoleMenu.Wpf;component/Themes/" + theme + ".xaml")
            };

            Application.Current.Resources.MergedDictionaries.Clear();
            Application.Current.Resources.MergedDictionaries.Add(dictionary);
        }

        private void ThemeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_settings == null || _loading) return;

            var item = ThemeCombo.SelectedItem as ComboBoxItem;
            var theme = item?.Tag as string;

            if (string.IsNullOrWhiteSpace(theme)) return;

            _settings.Theme = theme;
            SaveSettings();
            ApplyTheme();
        }

        private void InitStoreCombo()
        {
            StoreRepoCombo.ItemsSource = _store.Entries.Select(x => x.Repo).ToList();
            if (StoreRepoCombo.Items.Count > 0)
                StoreRepoCombo.SelectedIndex = 0;
        }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed)
                DragMove();
        }

        private void Minimize_Click(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState.Minimized;
        }

        private void Close_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }

        private void AddGameButton_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog
            {
                Filter = "Исполняемый файл (*.exe)|*.exe",
                Title = "Выбери .exe игры"
            };

            if (dialog.ShowDialog() != true) return;

            var game = new GameEntry
            {
                Title = Path.GetFileNameWithoutExtension(dialog.FileName),
                ExePath = dialog.FileName,
                WorkingDirectory = Path.GetDirectoryName(dialog.FileName),
                Source = "local"
            };

            _games.Games.Add(game);
            SaveGames();
            RefreshGames();
        }

        private void LaunchGameButton_Click(object sender, RoutedEventArgs e)
        {
            var game = GamesList.SelectedItem as GameEntry;

            if (game == null)
            {
                StoreStatus.Text = "";
                MessageBox.Show("Выбери игру.");
                return;
            }

            if (!File.Exists(game.ExePath))
            {
                MessageBox.Show("Файл не найден: " + game.ExePath);
                return;
            }

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = game.ExePath,
                    Arguments = game.Arguments ?? string.Empty,
                    WorkingDirectory = string.IsNullOrWhiteSpace(game.WorkingDirectory)
                        ? Path.GetDirectoryName(game.ExePath)
                        : game.WorkingDirectory,
                    UseShellExecute = false
                };

                using (var process = Process.Start(psi))
                {
                    if (_settings.EnableBoost)
                        BoostService.ApplyBoost(process);
                }

                game.LastLaunchUtc = DateTime.UtcNow;
                SaveGames();
                RefreshGames();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Не удалось запустить: " + ex.Message);
            }
        }

        private void RemoveGameButton_Click(object sender, RoutedEventArgs e)
        {
            var game = GamesList.SelectedItem as GameEntry;
            if (game == null) return;

            _games.Games.Remove(game);
            SaveGames();
            RefreshGames();
        }

        private void RefreshGames()
        {
            GamesList.ItemsSource = null;
            GamesList.ItemsSource = _games.Games;
        }

        private void RefreshProfiles()
        {
            ProfilesList.ItemsSource = null;
            ProfilesList.ItemsSource = _profiles.Profiles;
        }

        private async Task InitStoreViewAsync()
        {
            try
            {
                var page = Path.Combine(App.DataDirectory, "store-page.html");
                if (!File.Exists(page)) return;

                if (StoreWebView.CoreWebView2 == null)
                    await StoreWebView.EnsureCoreWebView2Async();

                StoreWebView.CoreWebView2.Navigate(new Uri(page).AbsoluteUri);
            }
            catch
            {
                ShowStoreFallback();
            }
        }

        private void ShowStoreFallback()
        {
            StoreWebView.Visibility = Visibility.Collapsed;
            StoreFallback.Visibility = Visibility.Visible;
        }

        private void OpenPageBrowser_Click(object sender, RoutedEventArgs e)
        {
            var page = Path.Combine(App.DataDirectory, "store-page.html");
            if (!File.Exists(page)) return;

            try
            {
                Process.Start(new ProcessStartInfo { FileName = page, UseShellExecute = true });
            }
            catch
            {
                // Браузер не открылся — не критично для оболочки.
            }
        }

        private async void RefreshReleases_Click(object sender, RoutedEventArgs e)
        {
            var repo = StoreRepoCombo.SelectedItem as string;
            if (string.IsNullOrWhiteSpace(repo)) return;

            StoreStatus.Text = "Загрузка релизов...";

            try
            {
                var client = new GitHubReleaseClient(TokenOrNull());
                _releases = await client.GetReleasesAsync(repo);

                ReleasesList.ItemsSource = null;
                ReleasesList.ItemsSource = _releases;

                StoreStatus.Text = "Релизов: " + _releases.Count;
            }
            catch (Exception ex)
            {
                StoreStatus.Text = "Ошибка: " + ex.Message;
            }
        }

        private async void InstallRelease_Click(object sender, RoutedEventArgs e)
        {
            var release = ReleasesList.SelectedItem as GitHubRelease;
            var repo = StoreRepoCombo.SelectedItem as string;

            if (release == null || string.IsNullOrWhiteSpace(repo))
            {
                StoreStatus.Text = "Выбери релиз.";
                return;
            }

            var entry = _store.Entries.FirstOrDefault(x => x.Repo == repo) ?? new StoreEntry();
            var asset = release.Assets?.FirstOrDefault(a => MatchesPattern(a.Name, entry.AssetPattern));
            var url = asset != null ? asset.DownloadUrl : release.ZipballUrl;

            if (string.IsNullOrWhiteSpace(url))
            {
                StoreStatus.Text = "У релиза нет ZIP.";
                return;
            }

            StoreStatus.Text = "Скачивание...";

            try
            {
                var client = new GitHubReleaseClient(TokenOrNull());

                var safeRepo = string.Join("_", repo.Split('/'));
                var safeTag = Sanitize(release.TagName ?? "release");

                var dest = Path.Combine(_settings.InstallDirectory, safeRepo, safeTag);
                var zipPath = Path.Combine(_settings.InstallDirectory, safeRepo, safeTag + ".zip");

                await client.DownloadFileAsync(url, zipPath);
                SafeZip.ExtractToDirectory(zipPath, dest);
                File.Delete(zipPath);

                var exe = Directory.GetFiles(dest, "*.exe", SearchOption.AllDirectories).FirstOrDefault();

                var game = new GameEntry
                {
                    Title = repo + " " + (release.TagName ?? ""),
                    ExePath = exe ?? "",
                    WorkingDirectory = exe != null ? Path.GetDirectoryName(exe) : dest,
                    Source = "github"
                };

                _games.Games.Add(game);
                SaveGames();
                RefreshGames();

                StoreStatus.Text = exe != null
                    ? "Установлено: " + game.Title
                    : "Установлено, но .exe не найден — укажи путь в Играх.";
            }
            catch (Exception ex)
            {
                StoreStatus.Text = "Ошибка установки: " + ex.Message;
            }
        }

        private string TokenOrNull()
        {
            return string.IsNullOrWhiteSpace(_settings?.GitHubToken) ? null : _settings.GitHubToken;
        }

        private static bool MatchesPattern(string name, string pattern)
        {
            if (string.IsNullOrWhiteSpace(name)) return false;

            if (string.IsNullOrWhiteSpace(pattern))
                return name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase);

            var ext = pattern.TrimStart('*');
            return name.EndsWith(ext, StringComparison.OrdinalIgnoreCase);
        }

        private static string Sanitize(string value)
        {
            return string.Join("_", value.Split(Path.GetInvalidFileNameChars()));
        }

        private void SaveSettings_Click(object sender, RoutedEventArgs e)
        {
            _settings.EnableBoost = EnableBoostCheck.IsChecked == true;
            _settings.GitHubToken = GitHubTokenBox.Text.Trim();

            SaveSettings();
            MessageBox.Show("Настройки сохранены.");
        }

        private void AddProfile_Click(object sender, RoutedEventArgs e)
        {
            var name = ProfileNameBox.Text.Trim();
            if (string.IsNullOrWhiteSpace(name)) return;

            _profiles.Profiles.Add(new ProfileEntry { Name = name });
            SaveProfiles();
            RefreshProfiles();

            ProfileNameBox.Clear();
        }

        private void RegisterHotkey()
        {
            _hotkey = new HotkeyService(this, ShowOverlay);
            _hotkey.Register(HotkeyService.MOD_CONTROL | HotkeyService.MOD_SHIFT, 0x4D);
        }

        private void ShowOverlay()
        {
            if (_overlay == null)
                _overlay = new OverlayWindow();

            if (!_overlay.IsVisible)
                _overlay.Show();
            else
                _overlay.Activate();
        }

        private void SaveSettings()
        {
            JsonStore.Save(App.SettingsPath, _settings);
        }

        private void SaveGames()
        {
            JsonStore.Save(App.GamesPath, _games);
        }

        private void SaveProfiles()
        {
            JsonStore.Save(App.ProfilesPath, _profiles);
        }
    }
}