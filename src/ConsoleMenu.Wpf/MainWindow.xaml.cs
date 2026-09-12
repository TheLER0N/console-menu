using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using ConsoleMenu.Core.Models;
using ConsoleMenu.Core.Storage;
using ConsoleMenu.Wpf.Services;

namespace ConsoleMenu.Wpf
{
    public partial class MainWindow : Window
    {
        private bool _loading;

        private AppSettings _settings;
        private StoreConfig _store;
        private GameStore _games;
        private ProfileStore _profiles;

        private HotkeyService _hotkey;
        private OverlayWindow _overlay;

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
            RegisterHotkey();
            _ = OpenStorePageAsync();
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

            GamesList.ItemsSource = _games.Games;
            ProfilesList.ItemsSource = _profiles.Profiles;
            EnableBoostCheck.IsChecked = _settings.EnableBoost;
            GitHubTokenBox.Text = _settings.GitHubToken;
        }

        private void InitThemeCombo()
        {
            _loading = true;
            ThemeCombo.SelectedIndex = string.Equals(_settings.Theme, "ps4", StringComparison.OrdinalIgnoreCase) ? 1 : 0;
            _loading = false;
        }

        private void InitStoreCombo()
        {
            StoreRepoCombo.ItemsSource = _store.Entries.Select(x => x.Repo).ToList();
            if (StoreRepoCombo.Items.Count > 0)
                StoreRepoCombo.SelectedIndex = 0;
        }

        private void ApplyTheme()
        {
            var theme = string.Equals(_settings.Theme, "ps4", StringComparison.OrdinalIgnoreCase) ? "PS4" : "PS5";
            var dictionary = new ResourceDictionary
            {
                Source = new Uri($"Themes/{theme}.xaml", UriKind.Relative)
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

        private void OpenStorePage_Click(object sender, RoutedEventArgs e)
        {
            _ = OpenStorePageAsync();
        }

        private async Task OpenStorePageAsync()
        {
            try
            {
                var page = Path.Combine(App.DataDirectory, "store-page.html");
                if (!File.Exists(page)) return;

                if (StoreWebView.CoreWebView2 == null)
                    await StoreWebView.EnsureCoreWebView2Async();

                StoreWebView.CoreWebView2.Navigate(new Uri(page).AbsoluteUri);
            }
            catch (Exception ex)
            {
                MessageBox.Show("WebView2 недоступен: " + ex.Message);
            }
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