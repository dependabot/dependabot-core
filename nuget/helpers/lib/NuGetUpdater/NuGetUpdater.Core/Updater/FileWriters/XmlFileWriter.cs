using System.Collections.Immutable;
using System.Text.RegularExpressions;
using System.Xml.Linq;

using NuGet.Versioning;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Updater.FileWriters;

public class XmlFileWriter : IFileWriter
{
    private const string IncludeAttributeName = "Include";
    private const string UpdateAttributeName = "Update";
    private const string VersionMetadataName = "Version";
    private const string VersionOverrideMetadataName = "VersionOverride";

    private const string ItemGroupElementName = "ItemGroup";
    private const string GlobalPackageReferenceElementName = "GlobalPackageReference";
    private const string PackageReferenceElementName = "PackageReference";
    private const string PackageVersionElementName = "PackageVersion";
    private const string PropertyGroupElementName = "PropertyGroup";

    private readonly ILogger _logger;

    // these file extensions are valid project entrypoints; everything else is ignored
    private static readonly HashSet<string> SupportedProjectFileExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".csproj",
        ".vbproj",
        ".fsproj",
    };

    // these file extensions are valid additional files and can be updated; everything else is ignored
    private static readonly HashSet<string> SupportedAdditionalFileExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".props",
        ".targets",
    };

    public XmlFileWriter(ILogger logger)
    {
        _logger = logger;
    }

    public async Task<bool> UpdatePackageVersionsAsync(
        DirectoryInfo repoContentsPath,
        ImmutableArray<string> relativeFilePaths,
        ImmutableArray<Dependency> originalDependencies,
        ImmutableArray<Dependency> requiredPackageVersions,
        bool addPackageReferenceElementForPinnedPackages
    )
    {
        if (relativeFilePaths.IsDefaultOrEmpty)
        {
            _logger.Warn("No files to update; skipping XML update.");
            return false;
        }

        var updatesPerformed = requiredPackageVersions.ToDictionary(d => d.Name, _ => false, StringComparer.OrdinalIgnoreCase);
        var projectRelativePath = relativeFilePaths[0];
        var projectExtension = Path.GetExtension(projectRelativePath);
        if (!SupportedProjectFileExtensions.Contains(projectExtension))
        {
            _logger.Warn($"Project extension '{projectExtension}' not supported; skipping XML update.");
            return false;
        }

        var filesAndContentsTasks = relativeFilePaths
            .Where(path => SupportedProjectFileExtensions.Contains(Path.GetExtension(path)) || SupportedAdditionalFileExtensions.Contains(Path.GetExtension(path)))
            .Select(async path =>
            {
                var content = await ReadFileContentsAsync(repoContentsPath, path);
                var document = XDocument.Parse(content, LoadOptions.PreserveWhitespace);
                return KeyValuePair.Create(path, document);
            })
            .ToArray();
        var filesAndContents = (await Task.WhenAll(filesAndContentsTasks))
            .ToDictionary();
        foreach (var requiredPackageVersion in requiredPackageVersions)
        {
            var oldVersionString = originalDependencies.FirstOrDefault(d => d.Name.Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase))?.Version;
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
                .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName == PackageReferenceElementName || e.Name.LocalName == GlobalPackageReferenceElementName))
                .Where(e =>
                {
                    var attributeValue = e.Attribute(IncludeAttributeName)?.Value ?? e.Attribute(UpdateAttributeName)?.Value ?? string.Empty;
                    var packageNames = attributeValue.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                    return packageNames.Any(name => name.Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase));
                })
                .ToArray();

            if (packageReferenceElements.Length == 0)
            {
                // no matching `<PackageReference>` elements found; pin it as a transitive dependency
                updatesPerformed[requiredPackageVersion.Name] = true; // all cases below add the dependency

                // find last `<ItemGroup>` in the project...
                Action addItemGroup = () => { }; // adding an ItemGroup to the project isn't always necessary, but it's much easier to prepare for it here
                var projectDocument = filesAndContents[projectRelativePath];
                var lastItemGroup = projectDocument.Root!.Elements()
                    .LastOrDefault(e => e.Name.LocalName.Equals(ItemGroupElementName, StringComparison.OrdinalIgnoreCase));
                if (lastItemGroup is null)
                {
                    _logger.Info($"No `<{ItemGroupElementName}>` element found in project; adding one.");
                    lastItemGroup = new XElement(XName.Get(ItemGroupElementName, projectDocument.Root.Name.NamespaceName));
                    addItemGroup = () => projectDocument.Root.Add(lastItemGroup);
                }

                // ...find where the new item should go...
                var packageReferencesBeforeNew = lastItemGroup.Elements()
                    .Where(e => e.Name.LocalName.Equals(PackageReferenceElementName, StringComparison.OrdinalIgnoreCase))
                    .TakeWhile(e => (e.Attribute(IncludeAttributeName)?.Value ?? e.Attribute(UpdateAttributeName)?.Value ?? string.Empty).CompareTo(requiredPackageVersion.Name) < 0)
                    .ToArray();

                // ...prepare a new `<PackageReference>` element...
                var newElement = new XElement(
                    XName.Get(PackageReferenceElementName, projectDocument.Root.Name.NamespaceName),
                    new XAttribute(IncludeAttributeName, requiredPackageVersion.Name));

                // ...add the `<PackageReference>` element if and where appropriate...
                if (addPackageReferenceElementForPinnedPackages)
                {
                    addItemGroup();
                    var lastPriorPackageReference = packageReferencesBeforeNew.LastOrDefault();
                    if (lastPriorPackageReference is not null)
                    {
                        AddAfterSiblingElement(lastPriorPackageReference, newElement);
                    }
                    else
                    {
                        // no prior package references; add to the front
                        var indent = GetIndentXTextFromElement(lastItemGroup, extraIndentationToAdd: "  ");
                        lastItemGroup.AddFirst(indent, newElement);
                    }
                }

                // ...find the best place to add the version...
                var matchingPackageVersionElement = filesAndContents.Values
                    .SelectMany(doc => doc.Descendants().Where(e => e.Name.LocalName.Equals(PackageVersionElementName, StringComparison.OrdinalIgnoreCase)))
                    .FirstOrDefault(e => (e.Attribute(IncludeAttributeName)?.Value ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase));
                if (matchingPackageVersionElement is not null)
                {
                    // found matching `<PackageVersion>` element; if `Version` attribute is appropriate we're done, otherwise set `VersionOverride` attribute on new element
                    var versionAttribute = matchingPackageVersionElement.Attributes().FirstOrDefault(a => a.Name.LocalName.Equals(VersionMetadataName, StringComparison.OrdinalIgnoreCase));
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
                            AddAfterSiblingElement(lastPriorPackageVersionElement, newVersionElement);
                        }
                        else
                        {
                            // no prior package versions; add to the front of the document
                            _logger.Info($"Adding new `<{PackageVersionElementName}>` element for {requiredPackageVersion.Name} with version {requiredVersion} at the start of the document.");
                            var packageVersionGroup = allPackageVersionElements.First().Parent!;
                            var indent = GetIndentXTextFromElement(packageVersionGroup, extraIndentationToAdd: "  ");
                            packageVersionGroup.AddFirst(indent, newVersionElement);
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
                    var versionAttribute = packageReferenceElement.Attributes().FirstOrDefault(a => a.Name.LocalName.Equals(VersionMetadataName, StringComparison.OrdinalIgnoreCase));
                    if (versionAttribute is not null)
                    {
                        currentVersionString = versionAttribute.Value;
                        updateVersionLocation = (version) => versionAttribute.Value = version;
                        goto doVersionUpdate;
                    }

                    // next check for `Version` child element
                    var versionElement = packageReferenceElement.Elements().FirstOrDefault(e => e.Name.LocalName.Equals(VersionMetadataName, StringComparison.OrdinalIgnoreCase));
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
                        var packageVersionAttribute = packageVersionElement.Attributes().FirstOrDefault(a => a.Name.LocalName.Equals(VersionMetadataName, StringComparison.OrdinalIgnoreCase));
                        if (packageVersionAttribute is not null)
                        {
                            currentVersionString = packageVersionAttribute.Value;
                            updateVersionLocation = (version) => packageVersionAttribute.Value = version;
                            goto doVersionUpdate;
                        }
                        else
                        {
                            var cpmVersionElement = packageVersionElement.Elements().FirstOrDefault(e => e.Name.LocalName.Equals(VersionMetadataName, StringComparison.OrdinalIgnoreCase));
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
                                else
                                {
                                    // no exact match found, but this may be a magic SDK package
                                    var packageMapper = DotNetPackageCorrelationManager.GetPackageMapper();
                                    var isSdkReplacementPackage = packageMapper.IsSdkReplacementPackage(requiredPackageVersion.Name);
                                    if (isSdkReplacementPackage &&
                                        candidateUpdateVersion < oldVersion && // version in XML is older than what was resolved by the SDK
                                        oldVersion < requiredVersion) // this ensures we don't downgrade the wrong one
                                    {
                                        // If we're updating a top level SDK replacement package, the version listed in the project file won't
                                        // necessarily match the resolved version that caused the update because the SDK might have replaced
                                        // the package.  To handle this scenario, we pretend the version we're searching for was actually found.
                                        candidateUpdater(requiredVersion.ToString());
                                        updatesPerformed[requiredPackageVersion.Name] = true;
                                        performedUpdate = true;
                                        _logger.Info($"Updated SDK-managed package {requiredPackageVersion.Name} from version {oldVersion} to {requiredVersion}.");
                                        break;
                                    }
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
                await WriteFileContentsAsync(repoContentsPath, path, contents.ToString());
            }
        }

        return performedAllUpdates;
    }

    private static XText? GetIndentXTextFromElement(XElement element, string extraIndentationToAdd = "")
    {
        var indentText = (element.PreviousNode as XText)?.Value;
        var indent = indentText is not null
            ? new XText(indentText + extraIndentationToAdd)
            : null;
        return indent;
    }

    private static void AddAfterSiblingElement(XElement siblingElement, XElement newElement, string extraIndentationToAdd = "")
    {
        var indent = GetIndentXTextFromElement(siblingElement, extraIndentationToAdd);
        XNode nodeToAddAfter = siblingElement;
        var done = false;
        while (!done && nodeToAddAfter.NextNode is not null)
        {
            // skip over XText and XComment nodes until we find a newline
            switch (nodeToAddAfter.NextNode)
            {
                case XText text:
                    if (text.Value.Contains('\n'))
                    {
                        done = true;
                    }
                    else
                    {
                        nodeToAddAfter = nodeToAddAfter.NextNode;
                    }

                    break;
                case XComment comment:
                    if (comment.Value.Contains('\n'))
                    {
                        done = true;
                    }
                    else
                    {
                        nodeToAddAfter = nodeToAddAfter.NextNode;
                    }

                    break;
                default:
                    done = true;
                    break;
            }
        }

        nodeToAddAfter.AddAfterSelf(indent, newElement);
    }

    private static async Task<string> ReadFileContentsAsync(DirectoryInfo repoContentsPath, string path)
    {
        var fullPath = Path.Join(repoContentsPath.FullName, path);
        var contents = await File.ReadAllTextAsync(fullPath);
        return contents;
    }

    private static async Task WriteFileContentsAsync(DirectoryInfo repoContentsPath, string path, string contents)
    {
        var fullPath = Path.Join(repoContentsPath.FullName, path);
        await File.WriteAllTextAsync(fullPath, contents);
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
