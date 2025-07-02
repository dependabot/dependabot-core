using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;
using System.Xml.XPath;

using NuGet.Versioning;

using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Updater.FileWriters;

public class XmlFileWriter : IFileWriter
{
    public Task<bool> UpdatePackageVersionsAsync(DirectoryInfo repoContentsPath, ProjectDiscoveryResult projectDiscovery, ImmutableArray<Dependency> requiredPackageVersions)
    {
        var updatesPerformed = requiredPackageVersions.ToDictionary(d => d.Name, _ => false, StringComparer.OrdinalIgnoreCase);
        var filesAndContents = new[] { projectDiscovery.FilePath }.Concat(projectDiscovery.ImportedFiles)
            .ToDictionary(path => path, path => XDocument.Parse(ReadFileContents(repoContentsPath, path)));
        foreach (var requiredPackageVersion in requiredPackageVersions)
        {
            var packageHandled = false;
            var filesAndContentsEnumerator = filesAndContents.GetEnumerator();
            while (!packageHandled && filesAndContentsEnumerator.MoveNext())
            {
                var (path, document) = filesAndContentsEnumerator.Current;
                var candidateElements = document.Descendants()
                    .Where(e => e.Name.LocalName == "PackageReference")
                    .Where(e => (e.Attribute("Include")?.Value ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase))
                    .ToArray();
                foreach (var candidateElement in candidateElements)
                {
                    var candidateVersionAttribute = candidateElement.Attribute("Version");
                    if (candidateVersionAttribute is null)
                    {
                        continue;
                    }

                    var candidateVersion = NuGetVersion.Parse(candidateVersionAttribute.Value);
                    var requiredVersion = NuGetVersion.Parse(requiredPackageVersion.Version!);
                    if (candidateVersion < requiredVersion)
                    {
                        candidateVersionAttribute.Value = requiredVersion.ToString();
                        updatesPerformed[requiredPackageVersion.Name] = true;
                        packageHandled = true;
                    }
                }
            }
        }

        var performedAllUpdates = updatesPerformed.Values.All(v => v);
        if (performedAllUpdates)
        {
            foreach (var (path, contents) in filesAndContents)
            {
                WriteFileContents(repoContentsPath, path, contents.ToString());
            }
        }

        return Task.FromResult(performedAllUpdates);
    }

    private string ReadFileContents(DirectoryInfo repoContentsPath, string path)
    {
        var fullPath = Path.Join(repoContentsPath.FullName, path);
        var contents = File.ReadAllText(fullPath);
        return contents;
    }

    private void WriteFileContents(DirectoryInfo repoContentsPath, string path, string contents)
    {
        var fullPath = Path.Join(repoContentsPath.FullName, path);
        File.WriteAllText(fullPath, contents);
    }
}
