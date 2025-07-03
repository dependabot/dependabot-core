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

            // version numbers can be in attributes or elements and we may need to do some complicated navigation
            // this object is used to perform the update once we've walked back as far as necessary
            string? currentVersionString = null;
            Action<NuGetVersion>? updateVersionLocation = null;

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
                    currentVersionString = versionAttribute.Value;
                    updateVersionLocation = (version) => versionAttribute.Value = version.ToString();
                    goto doVersionUpdate;
                }

                // next check for `Version` child element
                var versionElement = packageReferenceElement.Elements().FirstOrDefault(e => e.Name.LocalName == "Version");
                if (versionElement is not null)
                {
                    currentVersionString = versionElement.Value;
                    updateVersionLocation = (version) => versionElement.Value = version.ToString();
                    goto doVersionUpdate;
                }

                // check for matching `<PackageVersion>` element
                var packageVersionElement = filesAndContents.Values
                    .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName == "PackageVersion"))
                    .FirstOrDefault(e => (e.Attribute("Include")?.Value ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase));
                if (packageVersionElement is not null)
                {
                    if (packageVersionElement.Attribute("Version") is { } packageVersionAttribute)
                    {
                        currentVersionString = packageVersionAttribute.Value;
                        updateVersionLocation = (version) => packageVersionAttribute.Value = version.ToString();
                        goto doVersionUpdate;
                    }
                    else
                    {
                        var cpmVersionElement = packageVersionElement.Elements().FirstOrDefault(e => e.Name.LocalName == "Version");
                        if (cpmVersionElement is not null)
                        {
                            currentVersionString = cpmVersionElement.Value;
                            updateVersionLocation = (version) => cpmVersionElement.Value = version.ToString();
                            goto doVersionUpdate;
                        }
                    }
                }

            doVersionUpdate:
                if (currentVersionString is not null && updateVersionLocation is not null)
                {
                    // we found a potential location to update
                    // if it looks like a propery, walk backwards
                    while (currentVersionString is not null
                        && currentVersionString.StartsWith("$(")
                        && currentVersionString.EndsWith(")"))
                    {
                        var propertyName = currentVersionString[2..^1];
                        var propertyDefinition = filesAndContents.Values
                            .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName.Equals(propertyName, StringComparison.OrdinalIgnoreCase)))
                            .FirstOrDefault(e => e.Parent?.Name.LocalName.Equals("PropertyGroup", StringComparison.OrdinalIgnoreCase) == true);
                        currentVersionString = propertyDefinition?.Value;
                        updateVersionLocation = (version) => propertyDefinition!.Value = version.ToString();
                    }

                    // if it's the correct old version, update it
                    if (currentVersionString is not null &&
                        NuGetVersion.TryParse(currentVersionString, out var currentVersion) &&
                        currentVersion == oldVersion)
                    {
                        updateVersionLocation(requiredVersion);
                        updatesPerformed[requiredPackageVersion.Name] = true;
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
