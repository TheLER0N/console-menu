using System;
using System.Collections.Generic;

namespace ConsoleMenu.Core.Models
{
    public class GameEntry
    {
        public string Id { get; set; } = Guid.NewGuid().ToString("N");
        public string Title { get; set; } = "";
        public string ExePath { get; set; } = "";
        public string Arguments { get; set; } = "";
        public string WorkingDirectory { get; set; } = "";
        public string CoverPath { get; set; } = "";
        public string BoostProfile { get; set; } = "balanced";
        public string Source { get; set; } = "local";
        public DateTime? LastLaunchUtc { get; set; }
    }

    public class GameStore
    {
        public List<GameEntry> Games { get; set; } = new List<GameEntry>();
    }
}