using System;
using System.IO;
using System.Net;
using System.Windows;
using System.Windows.Threading;
using ConsoleMenu.Core.Models;
using ConsoleMenu.Core.Storage;

namespace ConsoleMenu.Wpf
{
    public partial class App : Application
    {
        public static string DataDirectory { get; private set; }

        public static string SettingsPath => Path.Combine(DataDirectory, "settings.json");
        public static string StorePath => Path.Combine(DataDirectory, "store.json");
        public static string GamesPath => Path.Combine(DataDirectory, "games.json");
        public static string ProfilesPath => Path.Combine(DataDirectory, "profiles.json");

        protected override void OnStartup(StartupEventArgs e)
        {
            DataDirectory = Path.Combine(AppContext.BaseDirectory, "data");

            Directory.CreateDirectory(DataDirectory);
            Directory.CreateDirectory(Path.Combine(DataDirectory, "installs"));
            Directory.CreateDirectory(Path.Combine(DataDirectory, "media"));

            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;

            EnsureDefaults();

            base.OnStartup(e);

            var splash = new SplashWindow();
            splash.Show();

            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1200) };
            timer.Tick += (s, args) =>
            {
                timer.Stop();
                var main = new MainWindow();
                main.Show();
                splash.Close();
            };
            timer.Start();
        }

        private void EnsureDefaults()
        {
            var settings = JsonStore.Load(SettingsPath, new AppSettings());

            if (string.IsNullOrWhiteSpace(settings.InstallDirectory))
                settings.InstallDirectory = Path.Combine(DataDirectory, "installs");

            JsonStore.Save(SettingsPath, settings);

            JsonStore.Save(StorePath, JsonStore.Load(StorePath, new StoreConfig()));
            JsonStore.Save(GamesPath, JsonStore.Load(GamesPath, new GameStore()));
            JsonStore.Save(ProfilesPath, JsonStore.Load(ProfilesPath, new ProfileStore()));
        }
    }
}