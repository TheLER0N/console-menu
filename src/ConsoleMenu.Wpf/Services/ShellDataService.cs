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