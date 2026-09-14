namespace ConsoleMenu.Core.Models
{
public class AppSettings
{
public string Theme { get; set; } = "ps5";
public string InstallDirectory { get; set; } = "";
public string OverlayHotKey { get; set; } = "Ctrl+Shift+M";
public bool EnableBoost { get; set; } = true;
public string ActiveProfileId { get; set; } = "";
public string GitHubToken { get; set; } = "";
public bool RestMode { get; set; } = false;
}
}