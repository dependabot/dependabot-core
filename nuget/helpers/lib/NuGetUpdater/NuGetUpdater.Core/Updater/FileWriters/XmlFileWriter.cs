using System.Collections.Immutable;
using System.Text.RegularExpressions;

using Microsoft.Language.Xml;

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
    internal static readonly HashSet<string> SupportedProjectFileExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".csproj",
        ".vbproj",
        ".fsproj",
    };

    // these file extensions are valid additional files and can be updated; everything else is ignored
    internal static readonly HashSet<string> SupportedAdditionalFileExtensions = new(StringComparer.OrdinalIgnoreCase)
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
                var document = await ReadFileContentsAsync(repoContentsPath, path);
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

            var packageReferenceElementsAndPaths = filesAndContents
                .SelectMany(kvp =>
                {
                    var path = kvp.Key;
                    var doc = kvp.Value;
                    var elements = doc.Descendants().Where(e => e.Name == PackageReferenceElementName || e.Name == GlobalPackageReferenceElementName);
                    var pair = elements.Select(element => KeyValuePair.Create(element, path));
                    return pair;
                })
                .Where(pair =>
                {
                    var element = pair.Key;
                    var attributeValue = element.GetAttributeValue(IncludeAttributeName) ?? element.GetAttributeValue(UpdateAttributeName) ?? string.Empty;
                    var packageNames = attributeValue.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                    return packageNames.Any(name => name.Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase));
                })
                .ToArray();

            SyntaxNode ReplaceNode(string filePath, SyntaxNode original, SyntaxNode replacement)
            {
                var doc = filesAndContents[filePath];

#if DEBUG
                if (!doc.DescendantNodes().OfType<XmlNodeSyntax>().Any(n => n == original))
                {
                    throw new NotSupportedException("original node was not found");
                }
#endif

                var updatedDoc = doc.ReplaceNode(original, replacement);
#if DEBUG
                var docFullString = doc.ToFullString();
                var updatedDocFullString = updatedDoc.ToFullString();
#endif
                filesAndContents[filePath] = updatedDoc;
                var newlyAddedNode = updatedDoc.DescendantNodes().OfType<XmlNodeSyntax>().First(d => d.FullSpan.Start == original.FullSpan.Start);
                return newlyAddedNode;
            }

            if (packageReferenceElementsAndPaths.Length == 0)
            {
                // no matching `<PackageReference>` elements found; pin it as a transitive dependency
                updatesPerformed[requiredPackageVersion.Name] = true; // all cases below add the dependency

                // find last `<ItemGroup>` in the project...
                Action addItemGroup = () => { }; // adding an ItemGroup to the project isn't always necessary, but it's much easier to prepare for it here
                var projectDocument = filesAndContents[projectRelativePath];
                var lastItemGroup = projectDocument.RootSyntax.Elements
                    .LastOrDefault(e => e.Name.Equals(ItemGroupElementName, StringComparison.OrdinalIgnoreCase));
                if (lastItemGroup is null)
                {
                    _logger.Info($"No `<{ItemGroupElementName}>` element found in project; adding one.");
                    lastItemGroup = XmlExtensions.CreateOpenCloseXmlElementSyntax(ItemGroupElementName, []);
                    addItemGroup = () =>
                    {
                        projectDocument = (XmlDocumentSyntax)((IXmlElementSyntax)projectDocument).AddChild(lastItemGroup);
                        filesAndContents[projectRelativePath] = projectDocument;
                    };
                }

                // ...find where the new item should go...
                var elementsBeforeNew = GetOrderedElementsBeforeSpecified(lastItemGroup, PackageReferenceElementName, [IncludeAttributeName, UpdateAttributeName], requiredPackageVersion.Name);

                // ...prepare a new `<PackageReference>` element...
                var newElement = XmlExtensions.CreateSingleLineXmlElementSyntax(PackageReferenceElementName, leadingTrivia: new SyntaxList<SyntaxNode>())
                    .WithAttribute(IncludeAttributeName, requiredPackageVersion.Name);

                // ...add the `<PackageReference>` element if and where appropriate...
                if (addPackageReferenceElementForPinnedPackages)
                {
                    addItemGroup();
                    var lastPriorElement = elementsBeforeNew.LastOrDefault();
                    if (lastPriorElement is not null)
                    {
                        // find line number of last prior element
                        // find the offset of the first token on each newline
                        var firstOffsetForLine = new List<int>();
                        foreach (var tr in filesAndContents[projectRelativePath].DescendantTrivia(descendIntoChildren: _ => true, descendIntoTrivia: true))
                        {
                            if (tr.Kind == SyntaxKind.EndOfLineTrivia)
                            {
                                firstOffsetForLine.Add(tr.SpanStart);
                            }

                            if (tr.SpanStart >= lastPriorElement.SpanStart)
                            {
                                break;
                            }
                        }

                        var lastPriorElementLineNumber = firstOffsetForLine.Count(o => o < lastPriorElement.SpanStart);
                        var lastElementAtStartOfLine = lastPriorElement.Parent.ChildNodes
                            .First(n => firstOffsetForLine.Count(o => o < n.SpanStart) >= lastPriorElementLineNumber);
                        var trivia = lastElementAtStartOfLine.GetLeadingTrivia().ToList();
                        var priorEolIndex = trivia.FindLastIndex(t => t.Kind == SyntaxKind.EndOfLineTrivia);
                        var indentTrivia = trivia
                            .Skip(priorEolIndex + 1)
                            .Select(t => SyntaxFactory.WhitespaceTrivia(t.ToFullString()))
                            .ToArray();
                        var newTrivia = new SyntaxTriviaList([SyntaxFactory.EndOfLineTrivia("\n"), .. indentTrivia]);
                        newElement = (IXmlElementSyntax)newElement.AsNode.WithLeadingTrivia(newTrivia);
                        var replacementParent = lastPriorElement.Parent.InsertNodesAfter(lastPriorElement, [newElement.AsNode]);
                        var actualReplacementParent = ReplaceNode(projectRelativePath, lastPriorElement.Parent, replacementParent);
                        var insertionIndex = elementsBeforeNew.Length;
                        var actualNewElement = ((IXmlElementSyntax)actualReplacementParent).Content[insertionIndex];
                        newElement = (IXmlElementSyntax)actualNewElement;
                    }
                    else
                    {
                        // no prior package references; add to the front
                        var itemGroupTrivia = lastItemGroup.AsNode.GetLeadingTrivia().ToList();
                        var priorEolIndex = itemGroupTrivia.FindLastIndex(t => t.Kind == SyntaxKind.EndOfLineTrivia);
                        var indentTrivia = itemGroupTrivia
                            .Skip(priorEolIndex + 1)
                            .Select(t => SyntaxFactory.WhitespaceTrivia(t.ToFullString()))
                            .ToArray();
                        var newTrivia = new SyntaxTriviaList([SyntaxFactory.EndOfLineTrivia("\n"), SyntaxFactory.WhitespaceTrivia("  "), .. indentTrivia]);
                        newElement = (IXmlElementSyntax)newElement.AsNode.WithLeadingTrivia(newTrivia);
                        var updatedItemGroup = (IXmlElementSyntax)ReplaceNode(
                            projectRelativePath,
                            lastItemGroup.AsNode,
                            lastItemGroup.InsertChild(newElement, 0).AsNode
                        );
                        newElement = (IXmlElementSyntax)updatedItemGroup.Content[0];
                    }
                }

                // ...find the best place to add the version...
                var matchingPackageVersionElementsAndPaths = filesAndContents
                    .SelectMany(kvp =>
                    {
                        var path = kvp.Key;
                        var doc = kvp.Value;
                        var packageVersionElements = doc.Descendants()
                            .Where(e => e.Name.Equals(PackageVersionElementName, StringComparison.OrdinalIgnoreCase))
                            .Where(element => (element.GetAttributeValue(IncludeAttributeName) ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase))
                            .ToArray();
                        return packageVersionElements.Select(element => KeyValuePair.Create(element, path));
                    })
                    .ToArray();
                if (matchingPackageVersionElementsAndPaths.Length > 0)
                {
                    // found matching `<PackageVersion>` element; if `Version` attribute is appropriate we're done, otherwise set `VersionOverride` attribute on new element
                    var (matchingPackageVersionElement, filePath) = matchingPackageVersionElementsAndPaths.First();
                    var versionAttribute = matchingPackageVersionElement.GetAttributeCaseInsensitive(VersionMetadataName);
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
                        newElement = (IXmlElementSyntax)ReplaceNode(
                            projectRelativePath,
                            newElement.AsNode,
                            newElement.WithAttribute(VersionOverrideMetadataName, requiredVersion.ToString()).AsNode
                        );
                    }
                }
                else
                {
                    // no matching `<PackageVersion>` element; either add a new one, or directly set the `Version` attribute on the new element
                    var allPackageVersionElementsAndPaths = filesAndContents
                        .SelectMany(kvp =>
                        {
                            var path = kvp.Key;
                            var doc = kvp.Value;
                            return doc.Descendants()
                                .Where(e => e.Name.Equals(PackageVersionElementName, StringComparison.OrdinalIgnoreCase))
                                .Select(element => KeyValuePair.Create(element, path));
                        })
                        .ToArray();
                    if (allPackageVersionElementsAndPaths.Length > 0)
                    {
                        // add a new `<PackageVersion>` element
                        var newVersionElement = XmlExtensions.CreateSingleLineXmlElementSyntax(PackageVersionElementName)
                            .WithAttribute(IncludeAttributeName, requiredPackageVersion.Name)
                            .WithAttribute(VersionMetadataName, requiredVersion.ToString());
                        var priorPackageVersionElementsAndPaths = allPackageVersionElementsAndPaths
                            .TakeWhile(pair => (pair.Key.GetAttributeValue(IncludeAttributeName) ?? string.Empty).Trim().CompareTo(requiredPackageVersion.Name) < 0)
                            .ToArray();
                        if (priorPackageVersionElementsAndPaths.Length > 0)
                        {
                            _logger.Info($"Adding new `<{PackageVersionElementName}>` element for {requiredPackageVersion.Name} with version {requiredVersion}.");
                            var (lastPriorPackageVersionElement, filePath) = priorPackageVersionElementsAndPaths.Last();
                            var trivia = lastPriorPackageVersionElement.AsNode.GetLeadingTrivia().ToList();
                            var priorEolIndex = trivia.FindLastIndex(t => t.Kind == SyntaxKind.EndOfLineTrivia);
                            var indentTrivia = trivia
                                .Skip(priorEolIndex + 1)
                                .Select(t => SyntaxFactory.WhitespaceTrivia(t.ToFullString()))
                                .ToArray();
                            var newTrivia = new SyntaxTriviaList([SyntaxFactory.EndOfLineTrivia("\n"), .. indentTrivia]);
                            newVersionElement = (IXmlElementSyntax)newVersionElement.AsNode.WithLeadingTrivia(newTrivia).WithoutTrailingTrivia();
                            var insertionIndex = lastPriorPackageVersionElement.Parent.Content.IndexOf(lastPriorPackageVersionElement.AsNode) + 1;
                            var replacementParent = lastPriorPackageVersionElement.Parent
                                .InsertChild(newVersionElement, insertionIndex);
                            var actualReplacementParent = ReplaceNode(filePath, lastPriorPackageVersionElement.Parent.AsNode, replacementParent.AsNode);
                            var actualNewElement = ((IXmlElementSyntax)actualReplacementParent).Content[insertionIndex];
                            newVersionElement = (IXmlElementSyntax)actualNewElement;
                        }
                        else
                        {
                            // no prior package versions; add to the front of the document
                            _logger.Info($"Adding new `<{PackageVersionElementName}>` element for {requiredPackageVersion.Name} with version {requiredVersion} at the start of the document.");
                            var (packageVersionGroup, filePath) = allPackageVersionElementsAndPaths.First();
                            packageVersionGroup = packageVersionGroup.Parent;
                            var itemGroupTrivia = packageVersionGroup.AsNode.GetLeadingTrivia().ToList();
                            var priorEolIndex = itemGroupTrivia.FindLastIndex(t => t.Kind == SyntaxKind.EndOfLineTrivia);
                            var indentTrivia = itemGroupTrivia
                                .Skip(priorEolIndex + 1)
                                .Select(t => SyntaxFactory.WhitespaceTrivia(t.ToFullString()))
                                .ToArray();
                            var newTrivia = new SyntaxTriviaList([SyntaxFactory.EndOfLineTrivia("\n"), SyntaxFactory.WhitespaceTrivia("  "), .. indentTrivia]);
                            newVersionElement = (IXmlElementSyntax)newVersionElement.AsNode.WithLeadingTrivia(newTrivia).WithoutTrailingTrivia();
                            var insertionIndex = 0;
                            var replacementPackageVersionGroup = packageVersionGroup
                                .InsertChild(newVersionElement, insertionIndex);
                            ReplaceNode(
                                filePath,
                                packageVersionGroup.AsNode,
                                replacementPackageVersionGroup.AsNode
                            );
                        }
                    }
                    else
                    {
                        // add a direct `Version` attribute
                        var newElementWithVersion = newElement.WithAttribute(VersionMetadataName, requiredVersion.ToString());
                        newElement = (IXmlElementSyntax)ReplaceNode(projectRelativePath, newElement.AsNode, newElementWithVersion.AsNode);
                    }
                }
            }
            else
            {
                // found matching `<PackageReference>` elements to update
                foreach (var (packageReferenceElement, filePath) in packageReferenceElementsAndPaths)
                {
                    // first check for matching `Version` attribute
                    var versionAttribute = packageReferenceElement.GetAttribute(VersionMetadataName, StringComparison.OrdinalIgnoreCase);
                    if (versionAttribute is not null)
                    {
                        currentVersionString = versionAttribute.Value;
                        updateVersionLocation = version =>
                        {
                            var refoundVersionAttribute = filesAndContents[filePath]
                                .DescendantNodes()
                                .OfType<XmlAttributeSyntax>()
                                .First(a => a.FullSpan.Start == versionAttribute.FullSpan.Start);
                            ReplaceNode(filePath, refoundVersionAttribute, refoundVersionAttribute.WithValue(version));
                        };
                        goto doVersionUpdate;
                    }

                    // next check for `Version` child element
                    var versionElement = packageReferenceElement.Elements.FirstOrDefault(e => e.Name.Equals(VersionMetadataName, StringComparison.OrdinalIgnoreCase));
                    if (versionElement is not null)
                    {
                        currentVersionString = versionElement.GetContentValue();
                        updateVersionLocation = version =>
                        {
                            var refoundVersionElement = filesAndContents[filePath]
                                .DescendantNodes()
                                .OfType<IXmlElementSyntax>()
                                .First(e => e.AsNode.FullSpan.Start == versionElement.AsNode.FullSpan.Start);
                            ReplaceNode(filePath, refoundVersionElement.AsNode, refoundVersionElement.WithContent(version).AsNode);
                        };
                        goto doVersionUpdate;
                    }

                    // check for matching `<PackageVersion>` element
                    var packageVersionElementsAndPaths = filesAndContents
                        .SelectMany(kvp =>
                        {
                            var path = kvp.Key;
                            var doc = kvp.Value;
                            return doc.Descendants()
                                .Where(e => e.Name.Equals(PackageVersionElementName, StringComparison.OrdinalIgnoreCase))
                                .Where(e => (e.GetAttributeValue(IncludeAttributeName) ?? string.Empty).Trim().Equals(requiredPackageVersion.Name, StringComparison.OrdinalIgnoreCase))
                                .Select(element => KeyValuePair.Create(element, path));
                        })
                        .ToArray();
                    if (packageVersionElementsAndPaths.Length > 0)
                    {
                        var (packageVersionElement, packageVersionFilePath) = packageVersionElementsAndPaths.First();
                        var packageVersionAttribute = packageVersionElement.GetAttributeCaseInsensitive(VersionMetadataName);
                        if (packageVersionAttribute is not null)
                        {
                            currentVersionString = packageVersionAttribute.Value;
                            updateVersionLocation = version => ReplaceNode(packageVersionFilePath, packageVersionAttribute, packageVersionAttribute.WithValue(version));
                            goto doVersionUpdate;
                        }
                        else
                        {
                            var cpmVersionElement = packageVersionElement.GetElements(VersionMetadataName, StringComparison.OrdinalIgnoreCase).FirstOrDefault();
                            if (cpmVersionElement is not null)
                            {
                                currentVersionString = cpmVersionElement.GetContentValue();
                                updateVersionLocation = version => ReplaceNode(packageVersionFilePath, cpmVersionElement.AsNode, cpmVersionElement.WithContent(version).AsNode);
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
                                var propertyDefinitionsAndPaths = filesAndContents
                                    .SelectMany(kvp =>
                                    {
                                        var path = kvp.Key;
                                        var doc = kvp.Value;
                                        return doc.Descendants()
                                            .Where(e => e.Name.Equals(propertyName, StringComparison.OrdinalIgnoreCase))
                                            .Where(e => e.Parent?.Name.Equals(PropertyGroupElementName, StringComparison.OrdinalIgnoreCase) == true)
                                            .Select(element => KeyValuePair.Create(element, path));
                                    })
                                    .ToArray();
                                foreach (var (propertyDefinition, propertyFilePath) in propertyDefinitionsAndPaths)
                                {
                                    var updateAction = new Action<string>(version => ReplaceNode(propertyFilePath, propertyDefinition.AsNode, propertyDefinition.WithContent(version).AsNode));
                                    candidateUpdateLocations.Enqueue((propertyDefinition.GetContentValue(), updateAction));
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
                await WriteFileContentsAsync(repoContentsPath, path, contents);
            }
        }

        return performedAllUpdates;
    }

    private static ImmutableArray<SyntaxNode> GetOrderedElementsBeforeSpecified(IXmlElementSyntax parentElement, string elementName, IEnumerable<string> attributeNamesToCheck, string attributeValue)
    {
        var elementsBeforeNew = parentElement.Content
            .TakeWhile(
                e => e is XmlCommentSyntax ||
                (e is IXmlElementSyntax element &&
                    element.Name.Equals(elementName, StringComparison.OrdinalIgnoreCase) &&
                    (attributeNamesToCheck.Select(attributeName => element.GetAttributeValue(attributeName)).FirstOrDefault(value => value is not null) ?? string.Empty)
                    .CompareTo(attributeValue) < 0))
            .ToImmutableArray();
        return elementsBeforeNew;
    }

    private static async Task<XmlDocumentSyntax> ReadFileContentsAsync(DirectoryInfo repoContentsPath, string path)
    {
        var fullPath = Path.Join(repoContentsPath.FullName, path);
        var contents = await File.ReadAllTextAsync(fullPath);
        var document = Parser.ParseText(contents);
        return document;
    }

    private static async Task WriteFileContentsAsync(DirectoryInfo repoContentsPath, string path, XmlDocumentSyntax document)
    {
        var fullPath = Path.Join(repoContentsPath.FullName, path);
        var content = document.ToFullString();
        await File.WriteAllTextAsync(fullPath, content);
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
