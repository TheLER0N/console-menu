using System;
using System.IO;
using System.Text.Json;

namespace ConsoleMenu.Core.Storage
{
    public static class JsonStore
    {
        private static readonly JsonSerializerOptions Options = new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNameCaseInsensitive = true
        };

        public static T Load<T>(string path, T fallback) where T : class, new()
        {
            try
            {
                if (!File.Exists(path)) return fallback;
                var json = File.ReadAllText(path);
                if (string.IsNullOrWhiteSpace(json)) return fallback;
                return JsonSerializer.Deserialize<T>(json, Options) ?? fallback;
            }
            catch
            {
                return fallback;
            }
        }

        public static void Save<T>(string path, T value)
        {
            try
            {
                var dir = Path.GetDirectoryName(path);
                if (!string.IsNullOrWhiteSpace(dir)) Directory.CreateDirectory(dir);
                File.WriteAllText(path, JsonSerializer.Serialize(value, Options));
            }
            catch
            {
                // MVP: ошибки сохранения не должны ронять оболочку.
            }
        }
    }
}