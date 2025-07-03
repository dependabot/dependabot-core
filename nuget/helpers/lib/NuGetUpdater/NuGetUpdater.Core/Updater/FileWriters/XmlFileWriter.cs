using System.Collections.Immutable;
using System.Xml.Linq;

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
            var oldVersionString = projectDiscovery.Dependencies.FirstOrDefault(d => d.Name.Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase))?.Version;
            if (oldVersionString is null)
            {
                // TODO: log?
                continue;
            }

            var oldVersion = NuGetVersion.Parse(oldVersionString);
            var requiredVersion = NuGetVersion.Parse(requiredPackageVersion.Version!);

            var packageReferenceElements = filesAndContents.Values
                .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName == "PackageReference"))
                .Where(e => (e.Attribute("Include")?.Value ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase))
                .ToArray();
            if (packageReferenceElements.Length == 1)
            {
                var packageReferenceElement = packageReferenceElements[0];

                // first check for matching `Version` attribute
                var versionAttribute = packageReferenceElement.Attribute("Version");
                if (versionAttribute is not null)
                {
                    var parsedVersion = NuGetVersion.Parse(versionAttribute.Value);
                    if (parsedVersion < requiredVersion)
                    {
                        // found inline version attribute; do direct update
                        versionAttribute.Value = requiredVersion.ToString();
                        updatesPerformed[requiredPackageVersion.Name] = true;
                        continue;
                    }
                }

                // next check for `Version` child element
                var versionElement = packageReferenceElement.Elements().FirstOrDefault(e => e.Name.LocalName == "Version");
                if (versionElement is not null)
                {
                    var parsedVersion = NuGetVersion.Parse(versionElement.Value);
                    if (parsedVersion < requiredVersion)
                    {
                        // found inline version element; do direct update
                        versionElement.Value = requiredVersion.ToString();
                        updatesPerformed[requiredPackageVersion.Name] = true;
                        continue;
                    }
                }

                // check for matching `<PackageVersion>` element
                var packageVersionElement = filesAndContents.Values
                    .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName == "PackageVersion"))
                    .FirstOrDefault(e => (e.Attribute("Include")?.Value ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase));
                if (packageVersionElement is not null)
                {
                    if (packageVersionElement.Attribute("Version") is { } packageVersionAttribute)
                    {
                        var parsedVersion = NuGetVersion.Parse(packageVersionAttribute.Value);
                        if (parsedVersion == oldVersion)
                        {
                            // found the correct elemtnt to update
                            packageVersionAttribute.Value = requiredVersion.ToString();
                            updatesPerformed[requiredPackageVersion.Name] = true;
                            continue;
                        }
                    }
                    else
                    {
                        var cpmVersionElement = packageVersionElement.Elements().FirstOrDefault(e => e.Name.LocalName == "Version");
                        if (cpmVersionElement is not null)
                        {
                            var parsedVersion = NuGetVersion.Parse(cpmVersionElement.Value);
                            if (parsedVersion == oldVersion)
                            {
                                // found the correct element to update
                                cpmVersionElement.Value = requiredVersion.ToString();
                                updatesPerformed[requiredPackageVersion.Name] = true;
                                continue;
                            }
                        }
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
