using System.Collections.Generic;

namespace ConsoleMenu.Core.Models
{
    public class StoreConfig
    {
        public List<StoreEntry> Entries { get; set; } = new List<StoreEntry>();
    }

    public class StoreEntry
    {
        public string Repo { get; set; } = "";
        public string ReleaseMode { get; set; } = "latest";
        public string AssetPattern { get; set; } = "*.zip";
        public string PagePath { get; set; } = "store-page.html";
    }
}