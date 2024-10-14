using System.Collections.Immutable;
using System.Diagnostics.CodeAnalysis;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml;

using Microsoft.Build.Construction;
using Microsoft.Build.Definition;
using Microsoft.Build.Evaluation;
using Microsoft.Build.Exceptions;
using Microsoft.Build.Locator;
using Microsoft.Extensions.FileSystemGlobbing;

using NuGet;
using NuGet.Configuration;
using NuGet.Frameworks;
using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

internal static partial class MSBuildHelper
{
    public static string MSBuildPath { get; private set; } = string.Empty;

    public static bool IsMSBuildRegistered => MSBuildPath.Length > 0;

    public static void RegisterMSBuild(string currentDirectory, string rootDirectory)
    {
        // Ensure MSBuild types are registered before calling a method that loads the types
        if (!IsMSBuildRegistered)
        {
            SidelineGlobalJsonAsync(currentDirectory, rootDirectory, () =>
            {
                var defaultInstance = MSBuildLocator.QueryVisualStudioInstances().First();
                MSBuildPath = defaultInstance.MSBuildPath;
                MSBuildLocator.RegisterInstance(defaultInstance);
                return Task.CompletedTask;
            }).Wait();
        }
    }

    public static async Task SidelineGlobalJsonAsync(string currentDirectory, string rootDirectory, Func<Task> action, ILogger? logger = null, bool retainMSBuildSdks = false)
    {
        logger ??= new ConsoleLogger();
        var candidateDirectories = PathHelper.GetAllDirectoriesToRoot(currentDirectory, rootDirectory);
        var globalJsonPaths = candidateDirectories.Select(d => Path.Combine(d, "global.json")).Where(File.Exists).Select(p => (p, p + Guid.NewGuid().ToString())).ToArray();
        foreach (var (globalJsonPath, tempGlobalJsonPath) in globalJsonPaths)
        {
            logger.Log($"Temporarily removing `global.json` from `{Path.GetDirectoryName(globalJsonPath)}`{(retainMSBuildSdks ? " and retaining MSBuild SDK declarations" : string.Empty)}.");
            File.Move(globalJsonPath, tempGlobalJsonPath);
            if (retainMSBuildSdks)
            {
                // custom SDKs might need to be retained for other operations; rebuild `global.json` with only the relevant key
                var originalContent = await File.ReadAllTextAsync(tempGlobalJsonPath);
                var jsonNode = JsonHelper.ParseNode(originalContent);
                if (jsonNode is JsonObject obj &&
                    obj.TryGetPropertyValue("msbuild-sdks", out var sdks) &&
                    sdks is not null)
                {
                    var newObj = new JsonObject()
                    {
                        ["msbuild-sdks"] = sdks.DeepClone(),
                    };
                    await File.WriteAllTextAsync(globalJsonPath, newObj.ToJsonString());
                }
            }
        }

        try
        {
            await action();
        }
        finally
        {
            foreach (var (globalJsonpath, tempGlobalJsonPath) in globalJsonPaths)
            {
                logger.Log($"Restoring `global.json` to `{Path.GetDirectoryName(globalJsonpath)}`.");
                File.Move(tempGlobalJsonPath, globalJsonpath, overwrite: retainMSBuildSdks);
            }
        }
    }

    public static IEnumerable<string> GetProjectPathsFromSolution(string solutionPath)
    {
        var solution = SolutionFile.Parse(solutionPath);
        return solution.ProjectsInOrder.Select(p => p.AbsolutePath);
    }

    public static IEnumerable<string> GetProjectPathsFromProject(string projFilePath)
    {
        var projectStack = new Stack<(string folderPath, ProjectRootElement)>();
        var processedProjectFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using var projectCollection = new ProjectCollection();

        try
        {
            var projectRootElement = ProjectRootElement.Open(projFilePath, projectCollection);
            projectStack.Push((Path.GetFullPath(Path.GetDirectoryName(projFilePath)!), projectRootElement));
        }
        catch (InvalidProjectFileException)
        {
            yield break; // Skip invalid project files
        }

        while (projectStack.Count > 0)
        {
            var (folderPath, tmpProject) = projectStack.Pop();
            foreach (var projectReference in tmpProject.Items.Where(static x => x.ItemType == "ProjectReference" || x.ItemType == "ProjectFile"))
            {
                if (projectReference.Include is not { } projectPath)
                {
                    continue;
                }

                Matcher matcher = new Matcher();
                matcher.AddInclude(PathHelper.NormalizePathToUnix(projectReference.Include));

                string searchDirectory = PathHelper.NormalizePathToUnix(folderPath);

                IEnumerable<string> files = matcher.GetResultsInFullPath(searchDirectory);

                foreach (var file in files)
                {
                    // Check that we haven't already processed this file
                    if (processedProjectFiles.Contains(file))
                    {
                        continue;
                    }

                    var projectExtension = Path.GetExtension(file).ToLowerInvariant();
                    if (projectExtension == ".proj")
                    {
                        // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
                        if (File.Exists(file))
                        {
                            var additionalProjectRootElement = ProjectRootElement.Open(file, projectCollection);
                            projectStack.Push((Path.GetFullPath(Path.GetDirectoryName(file)!), additionalProjectRootElement));
                            processedProjectFiles.Add(file);
                        }
                    }
                    else if (projectExtension == ".csproj" || projectExtension == ".vbproj" || projectExtension == ".fsproj")
                    {
                        yield return file;
                    }
                }
            }
        }
    }

    public static IReadOnlyDictionary<string, Property> GetProperties(ImmutableArray<ProjectBuildFile> buildFiles)
    {
        Dictionary<string, Property> properties = new(StringComparer.OrdinalIgnoreCase);

        foreach (var buildFile in buildFiles)
        {
            var projectRoot = CreateProjectRootElement(buildFile);

            foreach (var property in projectRoot.Properties)
            {
                // Short of evaluating the entire project, there's no way to _really_ know what package version is
                // going to be used, and even then we might not be able to update it.  As a best guess, we'll simply
                // skip any property that has a condition _or_ where the condition is checking for an empty string.
                var hasEmptyCondition = string.IsNullOrEmpty(property.Condition);
                var conditionIsCheckingForEmptyString = string.Equals(property.Condition, $"$({property.Name}) == ''", StringComparison.OrdinalIgnoreCase) ||
                                                        string.Equals(property.Condition, $"'$({property.Name})' == ''", StringComparison.OrdinalIgnoreCase);
                if (hasEmptyCondition || conditionIsCheckingForEmptyString)
                {
                    properties[property.Name] = new(property.Name, property.Value, PathHelper.NormalizePathToUnix(buildFile.RelativePath));
                }
            }
        }

        return properties;
    }

    public static IEnumerable<Dependency> GetTopLevelPackageDependencyInfos(ImmutableArray<ProjectBuildFile> buildFiles)
    {
        Dictionary<string, (string, bool, DependencyType)> packageInfo = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, string> packageVersionInfo = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, Property> propertyInfo = new(StringComparer.OrdinalIgnoreCase);

        foreach (var buildFile in buildFiles)
        {
            var projectRoot = CreateProjectRootElement(buildFile);

            foreach (var property in projectRoot.Properties)
            {
                // Short of evaluating the entire project, there's no way to _really_ know what package version is
                // going to be used, and even then we might not be able to update it.  As a best guess, we'll simply
                // skip any property that has a condition _or_ where the condition is checking for an empty string.
                var hasEmptyCondition = string.IsNullOrEmpty(property.Condition);
                var conditionIsCheckingForEmptyString = string.Equals(property.Condition, $"$({property.Name}) == ''", StringComparison.OrdinalIgnoreCase) ||
                                                        string.Equals(property.Condition, $"'$({property.Name})' == ''", StringComparison.OrdinalIgnoreCase);
                if (hasEmptyCondition || conditionIsCheckingForEmptyString)
                {
                    propertyInfo[property.Name] = new(property.Name, property.Value, buildFile.RelativePath);
                }
            }

            if (buildFile.IsOutsideBasePath)
            {
                continue;
            }

            foreach (var packageItem in projectRoot.Items
                         .Where(i => (i.ItemType == "PackageReference" || i.ItemType == "GlobalPackageReference")))
            {
                var dependencyType = packageItem.ItemType == "PackageReference" ? DependencyType.PackageReference : DependencyType.GlobalPackageReference;
                var versionSpecification = packageItem.Metadata.FirstOrDefault(m => m.Name.Equals("Version", StringComparison.OrdinalIgnoreCase))?.Value
                                           ?? packageItem.Metadata.FirstOrDefault(m => m.Name.Equals("VersionOverride", StringComparison.OrdinalIgnoreCase))?.Value
                                           ?? string.Empty;
                foreach (var rawAttributeValue in new[] { packageItem.Include, packageItem.Update })
                {
                    var attributeValue = rawAttributeValue?.Trim();
                    if (!string.IsNullOrWhiteSpace(attributeValue))
                    {
                        if (packageInfo.TryGetValue(attributeValue, out var existingInfo))
                        {
                            var existingVersion = existingInfo.Item1;
                            var existingUpdate = existingInfo.Item2;
                            // Retain the version from the Update reference since the intention
                            // would be to override the version of the Include reference.
                            var vSpec = string.IsNullOrEmpty(versionSpecification) || existingUpdate ? existingVersion : versionSpecification;

                            var isUpdate = existingUpdate && string.IsNullOrEmpty(packageItem.Include);
                            packageInfo[attributeValue] = (vSpec, isUpdate, dependencyType);
                        }
                        else
                        {
                            var isUpdate = !string.IsNullOrEmpty(packageItem.Update);
                            packageInfo[attributeValue] = (versionSpecification, isUpdate, dependencyType);
                        }
                    }
                }
            }

            foreach (var packageItem in projectRoot.Items
                         .Where(i => i.ItemType == "PackageVersion" && !string.IsNullOrEmpty(i.Include)))
            {
                packageVersionInfo[packageItem.Include] = packageItem.Metadata.FirstOrDefault(m => m.Name.Equals("Version", StringComparison.OrdinalIgnoreCase))?.Value
                                                          ?? string.Empty;
            }
        }

        foreach (var (name, info) in packageInfo)
        {
            var (version, isUpdate, dependencyType) = info;
            if (version.Length != 0 || !packageVersionInfo.TryGetValue(name, out var packageVersion))
            {
                packageVersion = version;
            }

            // Walk the property replacements until we don't find another one.
            var evaluationResult = GetEvaluatedValue(packageVersion, propertyInfo);
            packageVersion = evaluationResult.ResultType == EvaluationResultType.Success
                ? evaluationResult.EvaluatedValue.TrimStart('[', '(').TrimEnd(']', ')')
                : evaluationResult.EvaluatedValue;

            yield return new Dependency(name, packageVersion, dependencyType, EvaluationResult: evaluationResult, IsUpdate: isUpdate);
        }
    }

    /// <summary>
    /// Given an MSBuild string and a set of properties, returns our best guess at the final value MSBuild will evaluate to.
    /// </summary>
    public static EvaluationResult GetEvaluatedValue(string msbuildString, IReadOnlyDictionary<string, Property> propertyInfo, params string[] propertiesToIgnore)
    {
        var ignoredProperties = new HashSet<string>(propertiesToIgnore, StringComparer.OrdinalIgnoreCase);
        var seenProperties = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        string originalValue = msbuildString;
        string? rootPropertyName = null;
        while (TryGetPropertyName(msbuildString, out var propertyName))
        {
            rootPropertyName = propertyName;

            if (ignoredProperties.Contains(propertyName))
            {
                return new(EvaluationResultType.PropertyIgnored, originalValue, msbuildString, rootPropertyName, $"Property '{propertyName}' is ignored.");
            }

            if (!seenProperties.Add(propertyName))
            {
                return new(EvaluationResultType.CircularReference, originalValue, msbuildString, rootPropertyName, $"Property '{propertyName}' has a circular reference.");
            }

            if (!propertyInfo.TryGetValue(propertyName, out var property))
            {
                return new(EvaluationResultType.PropertyNotFound, originalValue, msbuildString, rootPropertyName, $"Property '{propertyName}' was not found.");
            }

            msbuildString = msbuildString.Replace($"$({propertyName})", property.Value);
        }

        return new(EvaluationResultType.Success, originalValue, msbuildString, rootPropertyName, null);
    }

    public static bool TryGetPropertyName(string versionContent, [NotNullWhen(true)] out string? propertyName)
    {
        var startIndex = versionContent.IndexOf("$(", StringComparison.Ordinal);
        if (startIndex != -1)
        {
            var endIndex = versionContent.IndexOf(')', startIndex);
            if (endIndex != -1)
            {
                propertyName = versionContent.Substring(startIndex + 2, endIndex - startIndex - 2);
                return true;
            }
        }

        propertyName = null;
        return false;
    }

    internal static async Task<bool> DependenciesAreCoherentAsync(string repoRoot, string projectPath, string targetFramework, Dependency[] packages, ILogger logger)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-coherence_");
        try
        {
            var tempProjectPath = await CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, targetFramework, packages);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunAsync("dotnet", ["restore", tempProjectPath], workingDirectory: tempDirectory.FullName);

            // NU1608: Detected package version outside of dependency constraint

            return exitCode == 0 && !stdOut.Contains("NU1608");
        }
        finally
        {
            tempDirectory.Delete(recursive: true);
        }
    }

    internal static bool UseNewDependencySolver()
    {
        return Environment.GetEnvironmentVariable("UseNewNugetPackageResolver") == "true";
    }

    internal static async Task<Dependency[]?> ResolveDependencyConflicts(string repoRoot, string projectPath, string targetFramework, Dependency[] packages, Dependency[] update, ILogger logger)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-coherence_");
        PackageManager packageManager = new PackageManager(repoRoot, projectPath);

        try
        {
            string tempProjectPath = await CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, targetFramework, packages);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunAsync("dotnet", ["restore", tempProjectPath], workingDirectory: tempDirectory.FullName);

            // Add Dependency[] packages to List<PackageToUpdate> existingPackages
            List<PackageToUpdate> existingPackages = packages
            .Select(existingPackage => new PackageToUpdate
            {
                PackageName = existingPackage.Name,
                CurrentVersion = existingPackage.Version
            })
            .ToList();

            // Add Dependency[] update to List<PackageToUpdate> packagesToUpdate
            List<PackageToUpdate> packagesToUpdate = update
            .Where(package => package.Version != null)
            .Select(package => new PackageToUpdate
            {
                PackageName = package.Name,
                NewVersion = package.Version.ToString()
            })
            .ToList();

            foreach (PackageToUpdate existing in existingPackages)
            {
                var foundPackage = packagesToUpdate.Where(p => string.Equals(p.PackageName, existing.PackageName, StringComparison.OrdinalIgnoreCase));
                if (!foundPackage.Any())
                {
                    existing.NewVersion = existing.CurrentVersion;
                }
            }

            // Create a duplicate set of existingPackages for flexible package reference addition and removal 
            List<PackageToUpdate> existingDuplicate = new List<PackageToUpdate>(existingPackages);

            // Bool to keep track of if anything was added to the existingDuplicate list
            bool added = false;

            // If package 'isnt there, add it to the existingDuplicate list
            foreach (PackageToUpdate package in packagesToUpdate)
            {
                if (!existingDuplicate.Any(p => string.Equals(p.PackageName, package.PackageName, StringComparison.OrdinalIgnoreCase)))
                {
                    existingDuplicate.Add(package);
                    added = true;
                }
            }

            // If you have to use the existingDuplicate list
            if (added == true)
            {
                // Add existing versions to existing list
                packageManager.UpdateExistingPackagesWithNewVersions(existingDuplicate, packagesToUpdate);

                // Make relationships
                await packageManager.PopulatePackageDependenciesAsync(existingDuplicate, targetFramework, Path.GetDirectoryName(projectPath));

                // Update all to new versions
                foreach (var package in existingDuplicate)
                {
                    string updateResult = await packageManager.UpdateVersion(existingDuplicate, package, targetFramework, Path.GetDirectoryName(projectPath), logger);
                }
            }

            // Editing existing list because nothing was added to existingDuplicate
            else
            {
                // Add existing versions to existing list
                packageManager.UpdateExistingPackagesWithNewVersions(existingPackages, packagesToUpdate);

                // Make relationships
                await packageManager.PopulatePackageDependenciesAsync(existingPackages, targetFramework, Path.GetDirectoryName(projectPath));

                // Update all to new versions
                foreach (var package in existingPackages)
                {
                    string updateResult = await packageManager.UpdateVersion(existingPackages, package, targetFramework, Path.GetDirectoryName(projectPath), logger);
                }
            }

            // Make new list to remove and differentiate between existingDuplicate and existingPackages lists
            List<PackageToUpdate> packagesToRemove = existingDuplicate
            .Where(existingPackageDupe => !existingPackages.Contains(existingPackageDupe) && existingPackageDupe.IsSpecific == true)
            .ToList();

            foreach (PackageToUpdate package in packagesToRemove)
            {
                existingDuplicate.Remove(package);
            }

            if (existingDuplicate != null)
            {
                existingPackages = existingDuplicate;
            }

            // Convert back to Dependency [], use NewVersion if available, otherwise use CurrentVersion
            List<Dependency> candidatePackages = existingPackages
            .Select(package => new Dependency(
                package.PackageName,
                package.NewVersion ?? package.CurrentVersion,
                DependencyType.Unknown,
                null,
                null,
                false,
                false,
                false,
                false,
                false
            ))
            .ToList();

            // Return as array
            Dependency[] candidatePackagesArray = candidatePackages.ToArray();

            var targetFrameworks = new NuGetFramework[] { NuGetFramework.Parse(targetFramework) };

            var resolveProjectPath = projectPath;

            if (!Path.IsPathRooted(resolveProjectPath) || !File.Exists(resolveProjectPath))
            {
                resolveProjectPath = Path.GetFullPath(Path.Join(repoRoot, resolveProjectPath));
            }

            NuGetContext nugetContext = new NuGetContext(Path.GetDirectoryName(resolveProjectPath));

            // Target framework compatibility check
            foreach (var package in candidatePackages)
            {
                if (!NuGetVersion.TryParse(package.Version, out var nuGetVersion))
                {
                    // If version is not valid, return original packages and revert
                    return packages;
                }

                var packageIdentity = new NuGet.Packaging.Core.PackageIdentity(package.Name, nuGetVersion);

                bool isNewPackageCompatible = await CompatibilityChecker.CheckAsync(packageIdentity, targetFrameworks.ToImmutableArray(), nugetContext, logger, CancellationToken.None);
                if (!isNewPackageCompatible)
                {
                    // If the package target framework is not compatible, return original packages and revert
                    return packages;
                }
            }

            return candidatePackagesArray;
        }
        finally
        {
            tempDirectory.Delete(recursive: true);
        }
    }

    internal static async Task<Dependency[]?> ResolveDependencyConflictsWithBruteForce(string repoRoot, string projectPath, string targetFramework, Dependency[] packages, ILogger logger)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-coherence_");
        try
        {
            var tempProjectPath = await CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, targetFramework, packages);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunAsync("dotnet", ["restore", tempProjectPath], workingDirectory: tempDirectory.FullName);
            ThrowOnUnauthenticatedFeed(stdOut);

            // simple cases first
            // if restore failed, nothing we can do
            if (exitCode != 0)
            {
                return null;
            }

            // if no problems found, just return the current set
            if (!stdOut.Contains("NU1608"))
            {
                return packages;
            }

            // now it gets complicated; look for the packages with issues
            MatchCollection matches = PackageIncompatibilityWarningPattern().Matches(stdOut);
            (string, NuGetVersion)[] badPackagesAndVersions = matches.Select(m => (m.Groups["PackageName"].Value, NuGetVersion.Parse(m.Groups["PackageVersion"].Value))).ToArray();
            Dictionary<string, HashSet<NuGetVersion>> badPackagesAndCandidateVersionsDictionary = new(StringComparer.OrdinalIgnoreCase);

            // and for each of those packages, find all versions greater than the one that's currently installed
            foreach ((string PackageName, NuGetVersion packageVersion) in badPackagesAndVersions)
            {
                // this command dumps a JSON object with all versions of the specified package from all package sources
                (exitCode, stdOut, stdErr) = await ProcessEx.RunAsync("dotnet", ["package", "search", PackageName, "--exact-match", "--format", "json"], workingDirectory: tempDirectory.FullName);
                if (exitCode != 0)
                {
                    continue;
                }

                // ensure collection exists
                if (!badPackagesAndCandidateVersionsDictionary.ContainsKey(PackageName))
                {
                    badPackagesAndCandidateVersionsDictionary.Add(PackageName, new HashSet<NuGetVersion>());
                }

                HashSet<NuGetVersion> foundVersions = badPackagesAndCandidateVersionsDictionary[PackageName];

                var json = JsonHelper.ParseNode(stdOut);
                if (json?["searchResult"] is JsonArray searchResults)
                {
                    foreach (var searchResult in searchResults)
                    {
                        if (searchResult?["packages"] is JsonArray packagesArray)
                        {
                            foreach (var package in packagesArray)
                            {
                                // in 8.0.xxx SDKs, the package version is in the `latestVersion` property, but in 9.0.xxx, it's `version`
                                var packageVersionProperty = package?["version"] ?? package?["latestVersion"];
                                if (packageVersionProperty is JsonValue latestVersion &&
                                    latestVersion.GetValueKind() == JsonValueKind.String &&
                                    NuGetVersion.TryParse(latestVersion.ToString(), out var nugetVersion) &&
                                    nugetVersion > packageVersion)
                                {
                                    foundVersions.Add(nugetVersion);
                                }
                            }
                        }
                    }
                }
            }

            // generate all possible combinations
            (string Key, NuGetVersion v)[][] expandedLists = badPackagesAndCandidateVersionsDictionary.Select(kvp => kvp.Value.Order().Select(v => (kvp.Key, v)).ToArray()).ToArray();
            IEnumerable<(string PackageName, NuGetVersion PackageVersion)>[] product = expandedLists.CartesianProduct().ToArray();

            // FUTURE WORK: pre-filter individual known package incompatibilities to reduce the number of combinations, e.g., if Package.A v1.0.0
            // is incompatible with Package.B v2.0.0, then remove _all_ combinations with that pair

            // this is the slow part
            foreach (IEnumerable<(string PackageName, NuGetVersion PackageVersion)> candidateSet in product)
            {
                // rebuild candidate dependency list with the relevant versions
                Dictionary<string, NuGetVersion> packageVersions = candidateSet.ToDictionary(candidateSet => candidateSet.PackageName, candidateSet => candidateSet.PackageVersion);
                Dependency[] candidatePackages = packages.Select(p =>
                {
                    if (packageVersions.TryGetValue(p.Name, out var version))
                    {
                        // create a new dependency with the updated version
                        return new Dependency(p.Name, version.ToString(), p.Type, IsDevDependency: p.IsDevDependency, IsOverride: p.IsOverride, IsUpdate: p.IsUpdate);
                    }

                    // not the dependency we're looking for, use whatever it already was in this set
                    return p;
                }).ToArray();

                if (await DependenciesAreCoherentAsync(repoRoot, projectPath, targetFramework, candidatePackages, logger))
                {
                    // return as soon as we find a coherent set
                    return candidatePackages;
                }
            }

            // no package resolution set found
            return null;
        }
        finally
        {
            tempDirectory.Delete(recursive: true);
        }
    }

    // fully expand all possible combinations using the algorithm from here:
    // https://ericlippert.com/2010/06/28/computing-a-cartesian-product-with-linq/
    private static IEnumerable<IEnumerable<T>> CartesianProduct<T>(this IEnumerable<IEnumerable<T>> sequences)
    {
        IEnumerable<IEnumerable<T>> emptyProduct = [[]];
        return sequences.Aggregate(emptyProduct, (accumulator, sequence) => from accseq in accumulator
                                                                            from item in sequence
                                                                            select accseq.Concat([item]));
    }

    private static ProjectRootElement CreateProjectRootElement(ProjectBuildFile buildFile)
    {
        var xmlString = buildFile.Contents.ToFullString();
        using var xmlStream = new MemoryStream(Encoding.UTF8.GetBytes(xmlString));
        using var xmlReader = XmlReader.Create(xmlStream);
        var projectRoot = ProjectRootElement.Create(xmlReader);

        return projectRoot;
    }

    private static IEnumerable<PackageSource>? LoadPackageSources(string nugetConfigPath)
    {
        try
        {
            var nugetConfigDir = Path.GetDirectoryName(nugetConfigPath);
            var settings = Settings.LoadSpecificSettings(nugetConfigDir, Path.GetFileName(nugetConfigPath));
            var packageSourceProvider = new PackageSourceProvider(settings);
            return packageSourceProvider.LoadPackageSources();
        }
        catch (NuGetConfigurationException ex)
        {
            Console.WriteLine("Error while parsing NuGet.config");
            Console.WriteLine(ex.Message);

            // Nuget.config is invalid. Won't be able to do anything with specific sources.
            return null;
        }
    }

    internal static async Task<string> CreateTempProjectAsync(
        DirectoryInfo tempDir,
        string repoRoot,
        string projectPath,
        string targetFramework,
        IReadOnlyCollection<Dependency> packages,
        bool usePackageDownload = false)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath);
        projectDirectory ??= repoRoot;
        var topLevelFiles = Directory.GetFiles(repoRoot);
        var nugetConfigPath = PathHelper.GetFileInDirectoryOrParent(projectPath, repoRoot, "NuGet.Config", caseSensitive: false);
        if (nugetConfigPath is not null)
        {
            // Copy nuget.config to temp project directory
            File.Copy(nugetConfigPath, Path.Combine(tempDir.FullName, "NuGet.Config"));
            var nugetConfigDir = Path.GetDirectoryName(nugetConfigPath);

            var packageSources = LoadPackageSources(nugetConfigPath);
            if (packageSources is not null)
            {
                // We need to copy local package sources from the NuGet.Config file to the temp directory
                foreach (var localSource in packageSources.Where(p => p.IsLocal))
                {
                    // if the source is relative to the original location, copy it to the temp directory
                    if (PathHelper.IsSubdirectoryOf(nugetConfigDir!, localSource.Source))
                    {
                        // normalize the directory separators and copy the contents
                        string localSourcePath = localSource.Source.Replace("\\", "/");
                        string sourceRelativePath = Path.GetRelativePath(nugetConfigDir!, localSourcePath);
                        string destPath = Path.Join(tempDir.FullName, sourceRelativePath);
                        if (Directory.Exists(localSourcePath))
                        {
                            PathHelper.CopyDirectory(localSourcePath, destPath);
                        }
                    }
                }
            }
        }

        var packageReferences = string.Join(
            Environment.NewLine,
            packages
                // empty `Version` attributes will cause the temporary project to not build
                .Where(p => (p.EvaluationResult is null || p.EvaluationResult.ResultType == EvaluationResultType.Success) && !string.IsNullOrWhiteSpace(p.Version))
                // If all PackageReferences for a package are update-only mark it as such, otherwise it can cause package incoherence errors which do not exist in the repo.
                .Select(p => $"<{(usePackageDownload ? "PackageDownload" : "PackageReference")} {(p.IsUpdate ? "Update" : "Include")}=\"{p.Name}\" Version=\"[{p.Version}]\" />"));

        var projectContents = $"""
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>{targetFramework}</TargetFramework>
                <GenerateDependencyFile>true</GenerateDependencyFile>
                <RunAnalyzers>false</RunAnalyzers>
                <NuGetInteractive>false</NuGetInteractive>
              </PropertyGroup>
              <ItemGroup>
                {packageReferences}
              </ItemGroup>
              <Target Name="_CollectDependencies" DependsOnTargets="GenerateBuildDependencyFile">
                <ItemGroup>
                  <_NuGetPackageData Include="@(NativeCopyLocalItems)" />
                  <_NuGetPackageData Include="@(ResourceCopyLocalItems)" />
                  <_NuGetPackageData Include="@(RuntimeCopyLocalItems)" />
                  <_NuGetPackageData Include="@(ResolvedAnalyzers)" />
                  <_NuGetPackageData Include="@(_PackageDependenciesDesignTime)">
                    <NuGetPackageId>%(_PackageDependenciesDesignTime.Name)</NuGetPackageId>
                    <NuGetPackageVersion>%(_PackageDependenciesDesignTime.Version)</NuGetPackageVersion>
                  </_NuGetPackageData>
                </ItemGroup>
              </Target>
              <Target Name="_ReportDependencies" DependsOnTargets="_CollectDependencies">
                <Message Text="NuGetData::Package=%(_NuGetPackageData.NuGetPackageId), Version=%(_NuGetPackageData.NuGetPackageVersion)"
                         Condition="'%(_NuGetPackageData.NuGetPackageId)' != '' AND '%(_NuGetPackageData.NuGetPackageVersion)' != ''"
                         Importance="High" />
              </Target>
            </Project>
            """;
        var tempProjectPath = Path.Combine(tempDir.FullName, "Project.csproj");
        await File.WriteAllTextAsync(tempProjectPath, projectContents);

        // prevent directory crawling
        await File.WriteAllTextAsync(
            Path.Combine(tempDir.FullName, "Directory.Build.props"),
            """
            <Project>
              <PropertyGroup>
                <!-- For Windows-specific apps -->
                <EnableWindowsTargeting>true</EnableWindowsTargeting>
                <!-- Really ensure CPM is disabled -->
                <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
              </PropertyGroup>
            </Project>
            """);

        await File.WriteAllTextAsync(Path.Combine(tempDir.FullName, "Directory.Build.targets"), "<Project />");

        return tempProjectPath;
    }

    internal static async Task<Dependency[]> GetAllPackageDependenciesAsync(
        string repoRoot,
        string projectPath,
        string targetFramework,
        IReadOnlyCollection<Dependency> packages,
        ILogger? logger = null)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-resolution_");
        try
        {
            var topLevelPackagesNames = packages.Select(p => p.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var tempProjectPath = await CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, targetFramework, packages);

            var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("dotnet", ["build", tempProjectPath, "/t:_ReportDependencies"], workingDirectory: tempDirectory.FullName);
            ThrowOnUnauthenticatedFeed(stdout);

            if (exitCode == 0)
            {
                ImmutableArray<string> tfms = [targetFramework];
                var lines = stdout.Split('\n').Select(line => line.Trim());
                var pattern = PackagePattern();
                var allDependencies = lines
                    .Select(line => pattern.Match(line))
                    .Where(match => match.Success)
                    .Select(match =>
                    {
                        var PackageName = match.Groups["PackageName"].Value;
                        var isTransitive = !topLevelPackagesNames.Contains(PackageName);
                        return new Dependency(PackageName, match.Groups["PackageVersion"].Value, DependencyType.Unknown, TargetFrameworks: tfms, IsTransitive: isTransitive);
                    })
                    .ToArray();

                return allDependencies;
            }
            else
            {
                logger?.Log($"dotnet build in {nameof(GetAllPackageDependenciesAsync)} failed. STDOUT: {stdout} STDERR: {stderr}");
                return [];
            }
        }
        finally
        {
            try
            {
                tempDirectory.Delete(recursive: true);
            }
            catch
            {
            }
        }
    }

    internal static void ThrowOnUnauthenticatedFeed(string stdout)
    {
        var unauthorizedMessageSnippets = new string[]
        {
            "The plugin credential provider could not acquire credentials",
            "401 (Unauthorized)",
            "error NU1301: Unable to load the service index for source",
        };
        if (unauthorizedMessageSnippets.Any(stdout.Contains))
        {
            throw new HttpRequestException(message: stdout, inner: null, statusCode: System.Net.HttpStatusCode.Unauthorized);
        }
    }

    internal static void ThrowOnMissingFile(string output)
    {
        var missingFilePattern = new Regex(@"The imported project \""(?<FilePath>.*)\"" was not found");
        var match = missingFilePattern.Match(output);
        if (match.Success)
        {
            throw new MissingFileException(match.Groups["FilePath"].Value);
        }
    }

    internal static void ThrowOnMissingPackages(string output)
    {
        var missingPackagesPattern = new Regex(@"Package '(?<PackageName>[^'].*)' is not found on source");
        var matchCollection = missingPackagesPattern.Matches(output);
        var missingPackages = matchCollection.Select(m => m.Groups["PackageName"].Value).Distinct().ToArray();
        if (missingPackages.Length > 0)
        {
            throw new UpdateNotPossibleException(missingPackages);
        }
    }

    internal static bool TryGetGlobalJsonPath(string repoRootPath, string workspacePath, [NotNullWhen(returnValue: true)] out string? globalJsonPath)
    {
        globalJsonPath = PathHelper.GetFileInDirectoryOrParent(workspacePath, repoRootPath, "global.json", caseSensitive: false);
        return globalJsonPath is not null;
    }

    internal static bool TryGetDotNetToolsJsonPath(string repoRootPath, string workspacePath, [NotNullWhen(returnValue: true)] out string? dotnetToolsJsonJsonPath)
    {
        dotnetToolsJsonJsonPath = PathHelper.GetFileInDirectoryOrParent(workspacePath, repoRootPath, "./.config/dotnet-tools.json", caseSensitive: false);
        return dotnetToolsJsonJsonPath is not null;
    }

    internal static bool TryGetDirectoryPackagesPropsPath(string repoRootPath, string workspacePath, [NotNullWhen(returnValue: true)] out string? directoryPackagesPropsPath)
    {
        directoryPackagesPropsPath = PathHelper.GetFileInDirectoryOrParent(workspacePath, repoRootPath, "./Directory.Packages.props", caseSensitive: false);
        return directoryPackagesPropsPath is not null;
    }

    internal static async Task<(ImmutableArray<ProjectBuildFile> ProjectBuildFiles, string[] TargetFrameworks)> LoadBuildFilesAndTargetFrameworksAsync(string repoRootPath, string projectPath)
    {
        var buildFileList = new List<string>
        {
            projectPath.NormalizePathToUnix() // always include the starting project
        };

        // a global.json file might cause problems with the dotnet msbuild command; create a safe version temporarily
        TryGetGlobalJsonPath(repoRootPath, projectPath, out var globalJsonPath);
        var safeGlobalJsonName = $"{globalJsonPath}{Guid.NewGuid()}";
        HashSet<string> targetFrameworks = new(StringComparer.OrdinalIgnoreCase);

        try
        {
            // move the original
            if (globalJsonPath is not null)
            {
                File.Move(globalJsonPath, safeGlobalJsonName);

                // create a safe version with only certain top-level keys
                var globalJsonContent = await File.ReadAllTextAsync(safeGlobalJsonName);
                var json = JsonHelper.ParseNode(globalJsonContent);
                var sdks = json?["msbuild-sdks"];
                if (sdks is not null)
                {
                    var newObject = new Dictionary<string, object>()
                    {
                        ["msbuild-sdks"] = sdks,
                    };
                    var newContent = JsonSerializer.Serialize(newObject);
                    await File.WriteAllTextAsync(globalJsonPath, newContent);
                }
            }

            // This is equivalent to running the command `dotnet msbuild <projectPath> /pp` to preprocess the file.
            // The only difference is that we're specifying the `IgnoreMissingImports` flag which will allow us to
            // load the project even if it imports a file that doesn't exist (e.g. a file that's generated at restore
            // or build time).
            using var projectCollection = new ProjectCollection(); // do this in a one-off instance and don't pollute the global collection
            Project project = Project.FromFile(projectPath, new ProjectOptions
            {
                LoadSettings = ProjectLoadSettings.IgnoreMissingImports,
                ProjectCollection = projectCollection,
            });
            buildFileList.AddRange(project.Imports.Select(i => i.ImportedProject.FullPath.NormalizePathToUnix()));

            // use the MSBuild-evaluated value so we don't have to try to manually parse XML
            IEnumerable<ProjectProperty> targetFrameworkProperties = project.Properties.Where(p => p.Name.Equals("TargetFramework", StringComparison.OrdinalIgnoreCase)).ToList();
            IEnumerable<ProjectProperty> targetFrameworksProperties = project.Properties.Where(p => p.Name.Equals("TargetFrameworks", StringComparison.OrdinalIgnoreCase)).ToList();
            IEnumerable<ProjectProperty> targetFrameworkVersionProperties = project.Properties.Where(p => p.Name.Equals("TargetFrameworkVersion", StringComparison.OrdinalIgnoreCase)).ToList();
            foreach (ProjectProperty tfm in targetFrameworkProperties)
            {
                if (!string.IsNullOrWhiteSpace(tfm.EvaluatedValue))
                {
                    targetFrameworks.Add(tfm.EvaluatedValue);
                }
            }

            foreach (ProjectProperty tfms in targetFrameworksProperties)
            {
                foreach (string tfmValue in tfms.EvaluatedValue.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    targetFrameworks.Add(tfmValue);
                }
            }

            if (targetFrameworks.Count == 0)
            {
                // Only try this if we haven't been able to resolve anything yet.  This is because deep in the SDK, a
                // `TargetFramework` of `netstandard2.0` (eventually) gets turned into `v2.0` and we don't want to
                // interpret that as a .NET Framework 2.0 project.
                foreach (ProjectProperty tfvm in targetFrameworkVersionProperties)
                {
                    // `v0.0` is an error case where no TFM could be evaluated
                    if (tfvm.EvaluatedValue != "v0.0")
                    {
                        targetFrameworks.Add($"net{tfvm.EvaluatedValue.TrimStart('v').Replace(".", "")}");
                    }
                }
            }
        }
        catch (InvalidProjectFileException)
        {
            return ([], []);
        }
        finally
        {
            if (globalJsonPath is not null)
            {
                File.Move(safeGlobalJsonName, globalJsonPath, overwrite: true);
            }
        }

        var repoRootPathPrefix = repoRootPath.NormalizePathToUnix() + "/";
        var buildFiles = buildFileList
            .Where(f => f.StartsWith(repoRootPathPrefix, StringComparison.OrdinalIgnoreCase))
            .Distinct();
        var result = buildFiles
            .Where(File.Exists)
            .Select(path => ProjectBuildFile.Open(repoRootPath, path))
            .ToImmutableArray();
        return (result, targetFrameworks.ToArray());
    }

    [GeneratedRegex("^\\s*NuGetData::Package=(?<PackageName>[^,]+), Version=(?<PackageVersion>.+)$")]
    private static partial Regex PackagePattern();

    // Example output:
    //   NU1608: Detected package version outside of dependency constraint: SpecFlow.Tools.MsBuild.Generation 3.3.30 requires SpecFlow(= 3.3.30) but version SpecFlow 3.9.74 was resolved.
    //                                                          PackageName-|+++++++++++++++++++++++++++++++| |++++|-PackageVersion
    [GeneratedRegex("NU1608: [^:]+: (?<PackageName>[^ ]+) (?<PackageVersion>[^ ]+)")]
    private static partial Regex PackageIncompatibilityWarningPattern();
}
