using System;
using System.Collections.Generic;

namespace ConsoleMenu.Core.Models
{
    public class ProfileEntry
    {
        public string Id { get; set; } = Guid.NewGuid().ToString("N");
        public string Name { get; set; } = "";
        public string AvatarPath { get; set; } = "";
        public List<string> FavoriteGameIds { get; set; } = new List<string>();
        public List<string> RecentGameIds { get; set; } = new List<string>();
    }

    public class ProfileStore
    {
        public List<ProfileEntry> Profiles { get; set; } = new List<ProfileEntry>();
        public string ActiveProfileId { get; set; } = "";
    }
}