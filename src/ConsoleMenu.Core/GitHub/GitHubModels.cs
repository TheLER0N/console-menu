using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace ConsoleMenu.Core.GitHub
{
    public class GitHubAsset
    {
        [JsonPropertyName("name")]
        public string Name { get; set; }

        [JsonPropertyName("browser_download_url")]
        public string DownloadUrl { get; set; }

        [JsonPropertyName("size")]
        public long Size { get; set; }
    }

    public class GitHubRelease
    {
        [JsonPropertyName("tag_name")]
        public string TagName { get; set; }

        [JsonPropertyName("name")]
        public string Name { get; set; }

        [JsonPropertyName("published_at")]
        public string PublishedAt { get; set; }

        [JsonPropertyName("assets")]
        public List<GitHubAsset> Assets { get; set; } = new List<GitHubAsset>();

        [JsonPropertyName("zipball_url")]
        public string ZipballUrl { get; set; }
    }
}