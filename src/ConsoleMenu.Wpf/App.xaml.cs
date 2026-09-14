using System;
using System.IO;
using System.Net;
using System.Windows;
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
            DispatcherUnhandledException += (s, args) =>
            {
                MessageBox.Show(args.Exception.ToString(), "Console Menu error");
                args.Handled = true;
            };
            EnsureDefaults();
            base.OnStartup(e);
            var main = new MainWindow();
            MainWindow = main;
            var boot = new BootWindow();
            boot.Closed += (s, args) =>
            {
                try { main.Show(); }
                catch (Exception ex) { MessageBox.Show(ex.ToString(), "Console Menu error"); }
            };
            boot.Show();
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