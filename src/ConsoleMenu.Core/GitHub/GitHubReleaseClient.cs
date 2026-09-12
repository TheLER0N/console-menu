using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading.Tasks;

namespace ConsoleMenu.Core.GitHub
{
    public class GitHubReleaseClient
    {
        private static readonly JsonSerializerOptions Options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        };

        private readonly HttpClient _http;

        public GitHubReleaseClient(string token = null)
        {
            _http = new HttpClient();
            _http.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "ConsoleMenu/1.0");

            if (!string.IsNullOrWhiteSpace(token))
                _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        public async Task<List<GitHubRelease>> GetReleasesAsync(string repo)
        {
            if (string.IsNullOrWhiteSpace(repo)) return new List<GitHubRelease>();

            var url = $"https://api.github.com/repos/{repo.Trim()}/releases?per_page=20";

            using (var response = await _http.GetAsync(url).ConfigureAwait(false))
            {
                if (!response.IsSuccessStatusCode) return new List<GitHubRelease>();

                var json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                if (string.IsNullOrWhiteSpace(json)) return new List<GitHubRelease>();

                return JsonSerializer.Deserialize<List<GitHubRelease>>(json, Options) ?? new List<GitHubRelease>();
            }
        }

        public async Task<string> DownloadFileAsync(string url, string targetPath)
        {
            var dir = Path.GetDirectoryName(targetPath);
            if (!string.IsNullOrWhiteSpace(dir)) Directory.CreateDirectory(dir);

            using (var response = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false))
            {
                response.EnsureSuccessStatusCode();

                using (var file = File.Create(targetPath))
                {
                    await response.Content.CopyToAsync(file).ConfigureAwait(false);
                }
            }

            return targetPath;
        }
    }
}