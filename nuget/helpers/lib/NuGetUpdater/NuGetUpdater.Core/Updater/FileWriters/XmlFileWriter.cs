using System.Collections.Immutable;
using System.Text.RegularExpressions;
using System.Xml.Linq;

using NuGet.Versioning;

using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Updater.FileWriters;

public class XmlFileWriter : IFileWriter
{
    private const string IncludeAttributeName = "Include";
    private const string UpdateAttributeName = "Update";
    private const string VersionMetadataName = "Version";
    private const string VersionOverrideMetadataName = "VersionOverride";

    private const string ItemGroupElementName = "ItemGroup";
    private const string PackageReferenceElementName = "PackageReference";
    private const string PackageVersionElementName = "PackageVersion";
    private const string PropertyGroupElementName = "PropertyGroup";

    private readonly ILogger _logger;

    public XmlFileWriter(ILogger logger)
    {
        _logger = logger;
    }

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
                _logger.Warn($"Unable to find project dependency with name {requiredPackageVersion.Name}; skipping XML update.");
                continue;
            }

            var oldVersion = NuGetVersion.Parse(oldVersionString);
            var requiredVersion = NuGetVersion.Parse(requiredPackageVersion.Version!);

            if (oldVersion == requiredVersion)
            {
                _logger.Info($"Dependency {requiredPackageVersion.Name} is already at version {requiredVersion}; no update needed.");
                updatesPerformed[requiredPackageVersion.Name] = true;
                continue;
            }

            // version numbers can be in attributes or elements and we may need to do some complicated navigation
            // this object is used to perform the update once we've walked back as far as necessary
            string? currentVersionString = null;
            Action<string>? updateVersionLocation = null;

            var packageReferenceElements = filesAndContents.Values
                .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName == PackageReferenceElementName))
                .Where(e => (e.Attribute(IncludeAttributeName)?.Value ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase))
                .ToArray();

            if (packageReferenceElements.Length == 0)
            {
                // no matching `<PackageReference>` elements found; pin it as a transitive dependency
                updatesPerformed[requiredPackageVersion.Name] = true; // all cases below add the dependency

                // find last `<ItemGroup>` in the project...
                var projectDocument = filesAndContents[projectDiscovery.FilePath];
                var lastItemGroup = projectDocument.Root!.Elements()
                    .LastOrDefault(e => e.Name.LocalName.Equals(ItemGroupElementName, StringComparison.OrdinalIgnoreCase));
                if (lastItemGroup is null)
                {
                    _logger.Info($"No `<{ItemGroupElementName}>` element found in project; adding one.");
                    lastItemGroup = new XElement(XName.Get(ItemGroupElementName, projectDocument.Root.Name.NamespaceName));
                    projectDocument.Root.Add(lastItemGroup);
                }

                // ...find where the new item should go...
                var packageReferencesBeforeNew = lastItemGroup.Elements()
                    .Where(e => e.Name.LocalName.Equals(PackageReferenceElementName, StringComparison.OrdinalIgnoreCase))
                    .TakeWhile(e => (e.Attribute(IncludeAttributeName)?.Value ?? e.Attribute(UpdateAttributeName)?.Value ?? string.Empty).CompareTo(requiredPackageVersion.Name) < 0)
                    .ToArray();

                // ...add a new `<PackageReference>` element...
                var newElement = new XElement(
                    XName.Get(PackageReferenceElementName, projectDocument.Root.Name.NamespaceName),
                    new XAttribute(IncludeAttributeName, requiredPackageVersion.Name));
                var lastPriorPackageReference = packageReferencesBeforeNew.LastOrDefault();
                if (lastPriorPackageReference is not null)
                {
                    lastPriorPackageReference.AddAfterSelf(newElement);
                }
                else
                {
                    // no prior package references; add to the front
                    lastItemGroup.AddFirst(newElement);
                }

                // ...find the best place to add the version...
                var matchingPackageVersionElement = filesAndContents.Values
                    .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName.Equals(PackageVersionElementName, StringComparison.OrdinalIgnoreCase)))
                    .FirstOrDefault(e => (e.Attribute(IncludeAttributeName)?.Value ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase));
                if (matchingPackageVersionElement is not null)
                {
                    // found matching `<PackageVersion>` element; if `Version` attribute is appropriate we're done, otherwise set `VersionOverride` attribute on new element
                    var versionAttribute = matchingPackageVersionElement.Attribute(VersionMetadataName);
                    if (versionAttribute is not null &&
                        NuGetVersion.TryParse(versionAttribute.Value, out var existingVersion) &&
                        existingVersion == requiredVersion)
                    {
                        // version matches; no update needed
                        _logger.Info($"Dependency {requiredPackageVersion.Name} already set to {requiredVersion}; no override needed.");
                    }
                    else
                    {
                        // version doesn't match; use `VersionOverride` attribute on new element
                        _logger.Info($"Dependency {requiredPackageVersion.Name} set to {requiredVersion}; using `{VersionOverrideMetadataName}` attribute on new element.");
                        newElement.SetAttributeValue(VersionOverrideMetadataName, requiredVersion.ToString());
                    }
                }
                else
                {
                    // no matching `<PackageVersion>` element; either add a new one, or directly set the `Version` attribute on the new element
                    var allPackageVersionElements = filesAndContents.Values
                        .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName.Equals(PackageVersionElementName, StringComparison.OrdinalIgnoreCase)))
                        .ToArray();
                    if (allPackageVersionElements.Length > 0)
                    {
                        // add a new `<PackageVersion>` element
                        var newVersionElement = new XElement(XName.Get(PackageVersionElementName, projectDocument.Root.Name.NamespaceName),
                            new XAttribute(IncludeAttributeName, requiredPackageVersion.Name),
                            new XAttribute(VersionMetadataName, requiredVersion.ToString()));
                        var lastPriorPackageVersionElement = allPackageVersionElements
                            .TakeWhile(e => (e.Attribute(IncludeAttributeName)?.Value ?? string.Empty).Trim().CompareTo(requiredPackageVersion.Name) < 0)
                            .LastOrDefault();
                        if (lastPriorPackageVersionElement is not null)
                        {
                            _logger.Info($"Adding new `<{PackageVersionElementName}>` element for {requiredPackageVersion.Name} with version {requiredVersion}.");
                            lastPriorPackageVersionElement.AddAfterSelf(newVersionElement);
                        }
                        else
                        {
                            // no prior package versions; add to the front of the document
                            _logger.Info($"Adding new `<{PackageVersionElementName}>` element for {requiredPackageVersion.Name} with version {requiredVersion} at the start of the document.");
                            allPackageVersionElements.First().AddBeforeSelf(newVersionElement);
                        }
                    }
                    else
                    {
                        // add a direct `Version` attribute
                        newElement.SetAttributeValue(VersionMetadataName, requiredVersion.ToString());
                    }
                }
            }
            else
            {
                // found matching `<PackageReference>` elements to update
                foreach (var packageReferenceElement in packageReferenceElements)
                {
                    // first check for matching `Version` attribute
                    var versionAttribute = packageReferenceElement.Attribute(VersionMetadataName);
                    if (versionAttribute is not null)
                    {
                        currentVersionString = versionAttribute.Value;
                        updateVersionLocation = (version) => versionAttribute.Value = version;
                        goto doVersionUpdate;
                    }

                    // next check for `Version` child element
                    var versionElement = packageReferenceElement.Elements().FirstOrDefault(e => e.Name.LocalName == VersionMetadataName);
                    if (versionElement is not null)
                    {
                        currentVersionString = versionElement.Value;
                        updateVersionLocation = (version) => versionElement.Value = version;
                        goto doVersionUpdate;
                    }

                    // check for matching `<PackageVersion>` element
                    var packageVersionElement = filesAndContents.Values
                        .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName == PackageVersionElementName))
                        .FirstOrDefault(e => (e.Attribute(IncludeAttributeName)?.Value ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase));
                    if (packageVersionElement is not null)
                    {
                        if (packageVersionElement.Attribute(VersionMetadataName) is { } packageVersionAttribute)
                        {
                            currentVersionString = packageVersionAttribute.Value;
                            updateVersionLocation = (version) => packageVersionAttribute.Value = version;
                            goto doVersionUpdate;
                        }
                        else
                        {
                            var cpmVersionElement = packageVersionElement.Elements().FirstOrDefault(e => e.Name.LocalName == VersionMetadataName);
                            if (cpmVersionElement is not null)
                            {
                                currentVersionString = cpmVersionElement.Value;
                                updateVersionLocation = (version) => cpmVersionElement.Value = version;
                                goto doVersionUpdate;
                            }
                        }
                    }

                doVersionUpdate:
                    if (currentVersionString is not null && updateVersionLocation is not null)
                    {
                        var performedUpdate = false;
                        var candidateUpdateLocations = new Queue<(string VersionString, Action<string> Updater)>();
                        candidateUpdateLocations.Enqueue((currentVersionString, updateVersionLocation));

                        while (candidateUpdateLocations.TryDequeue(out var candidateUpdateLocation))
                        {
                            var candidateUpdateVersionString = candidateUpdateLocation.VersionString;
                            var candidateUpdater = candidateUpdateLocation.Updater;

                            if (NuGetVersion.TryParse(candidateUpdateVersionString, out var candidateUpdateVersion))
                            {
                                // most common: direct update
                                if (candidateUpdateVersion == requiredVersion)
                                {
                                    // already up to date from a previous pass
                                    updatesPerformed[requiredPackageVersion.Name] = true;
                                    performedUpdate = true;
                                    _logger.Info($"Dependency {requiredPackageVersion.Name} already set to {requiredVersion}; no update needed.");
                                    break;
                                }
                                else if (candidateUpdateVersion == oldVersion)
                                {
                                    // do the update here and call it good
                                    candidateUpdater(requiredVersion.ToString());
                                    updatesPerformed[requiredPackageVersion.Name] = true;
                                    performedUpdate = true;
                                    _logger.Info($"Updated dependency {requiredPackageVersion.Name} from version {oldVersion} to {requiredVersion}.");
                                    break;
                                }
                            }
                            else if (VersionRange.TryParse(candidateUpdateVersionString, out var candidateUpdateVersionRange))
                            {
                                // less common: version range
                                if (candidateUpdateVersionRange.Satisfies(oldVersion))
                                {
                                    var updatedVersionRange = CreateUpdatedVersionRangeString(candidateUpdateVersionRange, oldVersion, requiredVersion);
                                    candidateUpdater(updatedVersionRange);
                                    updatesPerformed[requiredPackageVersion.Name] = true;
                                    performedUpdate = true;
                                    _logger.Info($"Updated dependency {requiredPackageVersion.Name} from version {oldVersion} to {requiredVersion}.");
                                    break;
                                }
                                else if (candidateUpdateVersionRange.Satisfies(requiredVersion))
                                {
                                    // already up to date from a previous pass
                                    updatesPerformed[requiredPackageVersion.Name] = true;
                                    performedUpdate = true;
                                    _logger.Info($"Dependency {requiredPackageVersion.Name} version range '{candidateUpdateVersionRange}' already includes {requiredVersion}; no update needed.");
                                    break;
                                }
                            }

                            // find something that looks like it contains a property expansion, even if it's surrounded by other text
                            var propertyInSubstringPattern = new Regex(@"(?<Prefix>[^$]*)\$\((?<PropertyName>[A-Za-z0-9_]+)\)(?<Suffix>.*$)");
                            // e.g.,                                    not-a-dollar-sign $ ( alphanumeric-or-underscore    ) everything-else
                            var propertyMatch = propertyInSubstringPattern.Match(candidateUpdateVersionString);
                            if (propertyMatch.Success)
                            {
                                // this looks like a property; keep walking backwards with all possible elements
                                var propertyName = propertyMatch.Groups["PropertyName"].Value;
                                var propertyDefinitions = filesAndContents.Values
                                    .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName.Equals(propertyName, StringComparison.OrdinalIgnoreCase)))
                                    .Where(e => e.Parent?.Name.LocalName.Equals(PropertyGroupElementName, StringComparison.OrdinalIgnoreCase) == true)
                                    .ToArray();
                                foreach (var propertyDefinition in propertyDefinitions)
                                {
                                    candidateUpdateLocations.Enqueue((propertyDefinition.Value, (version) => propertyDefinition.Value = version));
                                }
                            }
                        }

                        if (!performedUpdate)
                        {
                            _logger.Warn($"Unable to find appropriate location to update package {requiredPackageVersion.Name} to version {requiredPackageVersion.Version}; no update performed");
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

    public static string CreateUpdatedVersionRangeString(VersionRange existingRange, NuGetVersion existingVersion, NuGetVersion requiredVersion)
    {
        var newMinVersion = requiredVersion;
        Func<NuGetVersion, NuGetVersion, bool> maxVersionComparer = existingRange.IsMaxInclusive
            ? (a, b) => a >= b
            : (a, b) => a > b;
        var newMaxVersion = existingVersion == existingRange.MaxVersion
            ? requiredVersion
            : existingRange.MaxVersion is not null && maxVersionComparer(existingRange.MaxVersion, requiredVersion)
                ? existingRange.MaxVersion
                : null;
        var newRange = new VersionRange(
            minVersion: newMinVersion,
            includeMinVersion: true,
            maxVersion: newMaxVersion,
            includeMaxVersion: newMaxVersion is not null && existingRange.IsMaxInclusive
        );

        // special case common scenarios

        // e.g., "[2.0.0, 2.0.0]" => "[2.0.0]"
        if (newRange.MinVersion == newRange.MaxVersion &&
            newRange.IsMaxInclusive)
        {
            return $"[{newRange.MinVersion}]";
        }

        // e.g., "[2.0.0, )" => "2.0.0"
        if (newRange.MaxVersion is null)
        {
            return requiredVersion.ToString();
        }

        return newRange.ToString();
    }
}
