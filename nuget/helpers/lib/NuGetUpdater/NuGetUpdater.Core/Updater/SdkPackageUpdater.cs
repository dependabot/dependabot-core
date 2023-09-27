using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Xml.Linq;

using Microsoft.Language.Xml;

using NuGet.Versioning;

namespace NuGetUpdater.Core;

internal static partial class SdkPackageUpdater
{
    public static async Task UpdateDependencyAsync(string repoRootPath, string projectPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive, Logger logger)
    {
        // SDK-style project, modify the XML directly
        logger.Log("  Running for SDK-style project");
        var buildFiles = LoadBuildFiles(repoRootPath, projectPath);

        var newDependencySemanticVersion = SemanticVersion.Parse(newDependencyVersion);

        // update all dependencies, including transitive
        var tfms = MSBuildHelper.GetTargetFrameworkMonikers(buildFiles);

        // Get the set of all top-level dependencies in the current project
        var topLevelDependencies = MSBuildHelper.GetTopLevelPackageDependenyInfos(buildFiles).ToArray();

        var packageFoundInDependencies = false;
        var packageNeedsUpdating = false;

        foreach (var tfm in tfms)
        {
            var dependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(repoRootPath, tfm, topLevelDependencies);
            foreach (var (packageName, version) in dependencies)
            {
                if (packageName.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
                {
                    packageFoundInDependencies = true;

                    var semanticVersion = SemanticVersion.Parse(version);
                    if (semanticVersion < newDependencySemanticVersion)
                    {
                        packageNeedsUpdating = true;
                    }
                }
            }
        }

        // Skip updating the project if the dependency does not exist in the graph
        if (!packageFoundInDependencies)
        {
            logger.Log($"    Package [{dependencyName}] Does not exist as a dependency in [{projectPath}].");
            return;
        }

        // Skip updating the project if the dependency version meets or exceeds the newDependencyVersion
        if (!packageNeedsUpdating)
        {
            logger.Log($"    Package [{dependencyName}] already meets the requested dependency version in [{projectPath}].");
            return;
        }

        var tfmsAndDependencies = new Dictionary<string, (string PackageName, string Version)[]>();
        foreach (var tfm in tfms)
        {
            var dependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(repoRootPath, tfm, new[] { (dependencyName, newDependencyVersion) });
            tfmsAndDependencies[tfm] = dependencies;
        }

        // stop update process if we find conflicting package versions
        var conflictingPackageVersionsFound = false;
        var packagesAndVersions = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (tfm, dependencies) in tfmsAndDependencies)
        {
            foreach (var (packageName, packageVersion) in dependencies)
            {
                if (packagesAndVersions.TryGetValue(packageName, out var existingVersion) &&
                    existingVersion != packageVersion)
                {
                    logger.Log($"    Package [{packageName}] tried to update to version [{packageVersion}], but found conflicting package version of [{existingVersion}].");
                    conflictingPackageVersionsFound = true;
                }
                else
                {
                    packagesAndVersions[packageName] = packageVersion;
                }
            }
        }

        if (conflictingPackageVersionsFound)
        {
            return;
        }

        var unupgradableTfms = tfmsAndDependencies.Where(kvp => !kvp.Value.Any()).Select(kvp => kvp.Key);
        if (unupgradableTfms.Any())
        {
            logger.Log($"    The following target frameworks could not find packages to upgrade: {string.Join(", ", unupgradableTfms)}");
            return;
        }

        if (isTransitive)
        {
            var directoryPackagesWithPinning = buildFiles.FirstOrDefault(bf => IsCpmTransitivePinningEnabled(bf));
            if (directoryPackagesWithPinning is not null)
            {
                PinTransitiveDependency(directoryPackagesWithPinning, dependencyName, newDependencyVersion, logger);
            }
            else
            {
                await AddTransitiveDependencyAsync(projectPath, dependencyName, newDependencyVersion, logger);
            }
        }
        else
        {
            await UpdateTopLevelDepdendencyAsync(buildFiles, dependencyName, previousDependencyVersion, newDependencyVersion, packagesAndVersions, logger);
        }

        foreach (var buildFile in buildFiles)
        {
            if (await buildFile.SaveAsync())
            {
                logger.Log($"    Saved [{buildFile.RepoRelativePath}].");
            }
        }
    }

    private static bool IsCpmTransitivePinningEnabled(BuildFile buildFile)
    {
        var buildFileName = Path.GetFileName(buildFile.Path);
        if (!buildFileName.Equals("Directory.Packages.props", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var propertyElements = buildFile.Xml.RootSyntax
            .GetElements("PropertyGroup")
            .SelectMany(e => e.Elements);

        var isCpmEnabledValue = propertyElements.FirstOrDefault(e => e.Name.Equals("ManagePackageVersionsCentrally", StringComparison.OrdinalIgnoreCase))?.GetContentValue();
        if (isCpmEnabledValue is null || !string.Equals(isCpmEnabledValue, "true", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var isTransitivePinningEnabled = propertyElements.FirstOrDefault(e => e.Name.Equals("CentralPackageTransitivePinningEnabled", StringComparison.OrdinalIgnoreCase))?.GetContentValue();
        return isTransitivePinningEnabled is not null && string.Equals(isTransitivePinningEnabled, "true", StringComparison.OrdinalIgnoreCase);
    }

    private static void PinTransitiveDependency(BuildFile directoryPackages, string dependencyName, string newDependencyVersion, Logger logger)
    {
        logger.Log($"    Pinning [{dependencyName}/{newDependencyVersion}] as a package version.");

        var lastItemGroup = directoryPackages.Xml.RootSyntax.GetElements("ItemGroup")
            .Where(e => e.Elements.Any(se => se.Name.Equals("PackageVersion", StringComparison.OrdinalIgnoreCase)))
            .LastOrDefault();

        if (lastItemGroup is null)
        {
            logger.Log($"    Transitive dependency [{dependencyName}/{newDependencyVersion}] was not pinned.");
            return;
        }

        var lastPackageVersion = lastItemGroup.Elements.Last(se => se.Name.Equals("PackageVersion", StringComparison.OrdinalIgnoreCase));
        var leadingTrivia = lastPackageVersion.AsNode.GetLeadingTrivia();

        var packageVersionElement = XmlExtensions.CreateSingleLineXmlElementSyntax("PackageVersion", new SyntaxList<SyntaxNode>(leadingTrivia))
            .WithAttribute("Include", dependencyName)
            .WithAttribute("Version", newDependencyVersion);

        var updatedItemGroup = lastItemGroup.AddChild(packageVersionElement);
        var updatedXml = directoryPackages.Xml.ReplaceNode(lastItemGroup.AsNode, updatedItemGroup.AsNode);
        directoryPackages.Update(updatedXml);
    }

    private static async Task AddTransitiveDependencyAsync(string projectPath, string dependencyName, string newDependencyVersion, Logger logger)
    {
        logger.Log($"    Adding [{dependencyName}/{newDependencyVersion}] as a top-level package reference.");

        // see https://learn.microsoft.com/nuget/consume-packages/install-use-packages-dotnet-cli
        var (exitCode, _, _) = await ProcessEx.RunAsync("dotnet", $"add {projectPath} package {dependencyName} --version {newDependencyVersion}");
        if (exitCode != 0)
        {
            logger.Log($"    Transitive dependency [{dependencyName}/{newDependencyVersion}] was not added.");
        }
    }

    private static async Task UpdateTopLevelDepdendencyAsync(ImmutableArray<BuildFile> buildFiles, string dependencyName, string previousDependencyVersion, string newDependencyVersion, Dictionary<string, string> packagesAndVersions, Logger logger)
    {
        var result = TryUpdateDependencyVersion(buildFiles, dependencyName, previousDependencyVersion, newDependencyVersion, logger);
        if (result == UpdateResult.NotFound)
        {
            logger.Log($"    Root package [{dependencyName}/{previousDependencyVersion}] was not updated; skipping dependencies.");
            return;
        }

        foreach (var (packageName, packageVersion) in packagesAndVersions.Where(kvp => string.Compare(kvp.Key, dependencyName, StringComparison.OrdinalIgnoreCase) != 0))
        {
            TryUpdateDependencyVersion(buildFiles, packageName, previousDependencyVersion: null, newDependencyVersion: packageVersion, logger);
        }
    }

    private static ImmutableArray<BuildFile> LoadBuildFiles(string repoRootPath, string projectPath)
    {
        var options = new EnumerationOptions()
        {
            RecurseSubdirectories = true,
            MatchType = MatchType.Win32,
            AttributesToSkip = 0,
            IgnoreInaccessible = false,
            MatchCasing = MatchCasing.CaseInsensitive,
        };
        return new string[] { projectPath }
            .Concat(Directory.EnumerateFiles(repoRootPath, "*.props", options))
            .Concat(Directory.EnumerateFiles(repoRootPath, "*.targets", options))
            .Select(path => new BuildFile(repoRootPath, path, Parser.ParseText(File.ReadAllText(path))))
            .ToImmutableArray();
    }

    private static UpdateResult TryUpdateDependencyVersion(ImmutableArray<BuildFile> buildFiles, string dependencyName, string? previousDependencyVersion, string newDependencyVersion, Logger logger)
    {
        var foundCorrect = false;
        var foundUnsupported = false;
        var updateWasPerformed = false;
        var propertyNames = new List<string>();

        // First we locate all the PackageReference, GlobalPackageReference, or PackageVersion which set the Version
        // or VersionOverride attribute. In the simplest case we can update the version attribute directly then move
        // on. When property substitution is used we have to additionally search for the property containing the version.

        foreach (var buildFile in buildFiles)
        {
            var updateAttributes = new List<XmlAttributeSyntax>();
            var packageNodes = FindPackageNode(buildFile.Xml, dependencyName);

            var previousPackageVersion = previousDependencyVersion;

            foreach (var packageNode in packageNodes)
            {
                var versionAttribute = packageNode.GetAttributeCaseInsensitive("Version") ?? packageNode.GetAttributeCaseInsensitive("VersionOverride");
                if (versionAttribute is null)
                {
                    continue;
                }

                // Is this the case where version is specified with property substitution?
                if (versionAttribute.Value.StartsWith("$(") && versionAttribute.Value.EndsWith(")"))
                {
                    propertyNames.Add(versionAttribute.Value.Substring(2, versionAttribute.Value.Length - 3));
                }
                // Is this the case that the version is specified directly in the package node?
                else
                {
                    var currentVersion = versionAttribute.Value.TrimStart('[', '(').TrimEnd(']', ')');
                    if (currentVersion.Contains(',') || currentVersion.Contains('*'))
                    {
                        logger.Log($"    Found unsupported [{packageNode.Name}] version attribute value [{versionAttribute.Value}] in [{buildFile.RepoRelativePath}].");
                        foundUnsupported = true;
                    }
                    else if (currentVersion == previousDependencyVersion)
                    {
                        logger.Log($"    Found incorrect [{packageNode.Name}] version attribute in [{buildFile.RepoRelativePath}].");
                        updateAttributes.Add(versionAttribute);
                    }
                    else if (previousDependencyVersion == null && SemanticVersion.TryParse(currentVersion, out var previousVersion))
                    {
                        var newVersion = SemanticVersion.Parse(newDependencyVersion);
                        if (previousVersion < newVersion)
                        {
                            previousPackageVersion = currentVersion;

                            logger.Log($"    Found incorrect peer [{packageNode.Name}] version attribute in [{buildFile.RepoRelativePath}].");
                            updateAttributes.Add(versionAttribute);
                        }
                    }
                    else if (currentVersion == newDependencyVersion)
                    {
                        logger.Log($"    Found correct [{packageNode.Name}] version attribute in [{buildFile.RepoRelativePath}].");
                        foundCorrect = true;
                    }
                }
            }

            if (updateAttributes.Count > 0)
            {
                var updatedXml = buildFile.Xml
                    .ReplaceNodes(updateAttributes, (o, n) => n.WithValue(o.Value.Replace(previousPackageVersion!, newDependencyVersion)));
                buildFile.Update(updatedXml);
                updateWasPerformed = true;
            }
        }

        // If property substitution was used to set the Version, we must search for the property containing
        // the version string. Since it could also be populated by property substitution this search repeats
        // with the each new property name until the version string is located.

        var processedPropertyNames = new HashSet<string>();

        for (int propertyNameIndex = 0; propertyNameIndex < propertyNames.Count; propertyNameIndex++)
        {
            var propertyName = propertyNames[propertyNameIndex];
            if (processedPropertyNames.Contains(propertyName))
            {
                continue;
            }

            processedPropertyNames.Add(propertyName);

            foreach (var buildFile in buildFiles)
            {
                var updateProperties = new List<XmlElementSyntax>();
                var propertyElements = buildFile.Xml
                    .Descendants()
                    .Where(e => e.Name.Equals(propertyName, StringComparison.OrdinalIgnoreCase));

                var previousPackageVersion = previousDependencyVersion;

                foreach (var propertyElement in propertyElements)
                {
                    var propertyContents = propertyElement.GetContentValue();

                    // Is this the case where this property contains another property substitution?
                    if (propertyContents.StartsWith("$(") && propertyContents.EndsWith(")"))
                    {
                        propertyNames.Add(propertyContents.Substring(2, propertyContents.Length - 3));
                    }
                    // Is this the case that the property contains the version?
                    else
                    {
                        var currentVersion = propertyContents.TrimStart('[', '(').TrimEnd(']', ')');
                        if (currentVersion.Contains(',') || currentVersion.Contains('*'))
                        {
                            logger.Log($"    Found unsupported version property [{propertyElement.Name}] value [{propertyContents}] in [{buildFile.RepoRelativePath}].");
                            foundUnsupported = true;
                        }
                        else if (currentVersion == previousDependencyVersion)
                        {
                            logger.Log($"    Found incorrect version property [{propertyElement.Name}] in [{buildFile.RepoRelativePath}].");
                            updateProperties.Add((XmlElementSyntax)propertyElement.AsNode);
                        }
                        else if (previousDependencyVersion is null && SemanticVersion.TryParse(currentVersion, out var previousVersion))
                        {
                            var newVersion = SemanticVersion.Parse(newDependencyVersion);
                            if (previousVersion < newVersion)
                            {
                                previousPackageVersion = currentVersion;

                                logger.Log($"    Found incorrect peer version property [{propertyElement.Name}] in [{buildFile.RepoRelativePath}].");
                                updateProperties.Add((XmlElementSyntax)propertyElement.AsNode);
                            }
                        }
                        else if (currentVersion == newDependencyVersion)
                        {
                            logger.Log($"    Found correct version property [{propertyElement.Name}] in [{buildFile.RepoRelativePath}].");
                            foundCorrect = true;
                        }
                    }
                }

                if (updateProperties.Count > 0)
                {
                    var updatedXml = buildFile.Xml
                        .ReplaceNodes(updateProperties, (o, n) => n.WithContent(o.GetContentValue().Replace(previousPackageVersion!, newDependencyVersion)));
                    buildFile.Update(updatedXml);
                    updateWasPerformed = true;
                }
            }
        }

        return updateWasPerformed
            ? UpdateResult.Updated
            : foundCorrect
                ? UpdateResult.Correct
                : foundUnsupported
                    ? UpdateResult.NotSupported
                    : UpdateResult.NotFound;
    }

    private static IEnumerable<IXmlElementSyntax> FindPackageNode(XmlDocumentSyntax xml, string packageName)
    {
        return xml.Descendants().Where(e =>
            (string.Equals(e.Name, "PackageReference", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(e.Name, "GlobalPackageReference", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(e.Name, "PackageVersion", StringComparison.OrdinalIgnoreCase)) &&
            string.Equals(e.GetAttributeValueCaseInsensitive("Include") ?? e.GetAttributeValueCaseInsensitive("Update"), packageName, StringComparison.OrdinalIgnoreCase) &&
            (e.GetAttributeCaseInsensitive("Version") ?? e.GetAttributeCaseInsensitive("VersionOverride")) is not null);
    }
}
