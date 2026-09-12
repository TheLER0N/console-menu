using System;
using System.IO;
using System.IO.Compression;

namespace ConsoleMenu.Core.Services
{
    public static class SafeZip
    {
        public static void ExtractToDirectory(string zipPath, string destinationDir)
        {
            if (!File.Exists(zipPath)) throw new FileNotFoundException("Zip not found", zipPath);

            Directory.CreateDirectory(destinationDir);

            var root = Path.GetFullPath(destinationDir);
            if (!root.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal))
                root += Path.DirectorySeparatorChar;

            using (var archive = new ZipArchive(File.OpenRead(zipPath), ZipArchiveMode.Read))
            {
                foreach (var entry in archive.Entries)
                {
                    var targetPath = Path.GetFullPath(Path.Combine(root, entry.FullName));

                    if (!targetPath.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                        throw new IOException("Zip slip detected");

                    if (string.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(targetPath);
                        continue;
                    }

                    Directory.CreateDirectory(Path.GetDirectoryName(targetPath));

                    using (var entryStream = entry.Open())
                    using (var fileStream = File.Create(targetPath))
                    {
                        entryStream.CopyTo(fileStream);
                    }
                }
            }
        }
    }
}