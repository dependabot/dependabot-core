using System.Collections.Immutable;
using System.Diagnostics.CodeAnalysis;
using System.Reflection;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml.Linq;

using Microsoft.Build.Locator;

using NuGet.Configuration;
using NuGet.Frameworks;
using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

internal static partial class MSBuildHelper
{
    public static string MSBuildPath { get; private set; } = string.Empty;

    public static bool IsMSBuildRegistered => MSBuildPath.Length > 0;

    public static string GetFileFromRuntimeDirectory(string fileName) => Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!, fileName);

    public static void RegisterMSBuild(string currentDirectory, string rootDirectory, ILogger logger)
    {
        // Ensure MSBuild types are registered before calling a method that loads the types
        if (!IsMSBuildRegistered)
        {
            var experimentsManager = new ExperimentsManager() { InstallDotnetSdks = false }; // `global.json` definitely needs to be moved for this operation
            HandleGlobalJsonAsync(currentDirectory, rootDirectory, experimentsManager, () =>
            {
                var defaultInstance = MSBuildLocator.QueryVisualStudioInstances().First();
                MSBuildPath = defaultInstance.MSBuildPath;
                MSBuildLocator.RegisterInstance(defaultInstance);
                return Task.FromResult(0);
            }, logger).Wait();
        }
    }

    public static async Task<T> HandleGlobalJsonAsync<T>(
        string currentDirectory,
        string rootDirectory,
        ExperimentsManager experimentsManager,
        Func<Task<T>> action,
        ILogger logger,
        bool retainMSBuildSdks = false
    )
    {
        if (experimentsManager.InstallDotnetSdks)
        {
            logger.Info($"{nameof(ExperimentsManager.InstallDotnetSdks)} == true; retaining `global.json` contents.");
            var result = await action();
            return result;
        }

        var candidateDirectories = PathHelper.GetAllDirectoriesToRoot(currentDirectory, rootDirectory);
        var globalJsonPaths = candidateDirectories.Select(d => Path.Combine(d, "global.json")).Where(File.Exists).Select(p => (p, p + Guid.NewGuid().ToString())).ToArray();
        foreach (var (globalJsonPath, tempGlobalJsonPath) in globalJsonPaths)
        {
            logger.Info($"Temporarily removing `global.json` from `{Path.GetDirectoryName(globalJsonPath)}`{(retainMSBuildSdks ? " and retaining MSBuild SDK declarations" : string.Empty)}.");
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
            var result = await action();
            return result;
        }
        finally
        {
            foreach (var (globalJsonpath, tempGlobalJsonPath) in globalJsonPaths)
            {
                logger.Info($"Restoring `global.json` to `{Path.GetDirectoryName(globalJsonpath)}`.");
                File.Move(tempGlobalJsonPath, globalJsonpath, overwrite: retainMSBuildSdks);
            }
        }
    }

    internal static async Task<ImmutableArray<Dependency>?> ResolveDependencyConflicts(string repoRoot, string projectPath, string targetFramework, ImmutableArray<Dependency> packages, ImmutableArray<Dependency> update, ExperimentsManager experimentsManager, ILogger logger)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-coherence_");
        PackageManager packageManager = new PackageManager(repoRoot, projectPath);

        try
        {
            string tempProjectPath = await CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, targetFramework, packages, experimentsManager, logger);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(["restore", tempProjectPath], tempDirectory.FullName, experimentsManager);

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
                packageManager.UpdateExistingPackagesWithNewVersions(existingDuplicate, packagesToUpdate, logger);

                // Make relationships
                await packageManager.PopulatePackageDependenciesAsync(existingDuplicate, targetFramework, Path.GetDirectoryName(projectPath), logger);

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
                packageManager.UpdateExistingPackagesWithNewVersions(existingPackages, packagesToUpdate, logger);

                // Make relationships
                await packageManager.PopulatePackageDependenciesAsync(existingPackages, targetFramework, Path.GetDirectoryName(projectPath), logger);

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
            var candidatePackagesArray = candidatePackages.ToImmutableArray();

            var targetFrameworks = ImmutableArray.Create<NuGetFramework>(NuGetFramework.Parse(targetFramework));

            var resolveProjectPath = projectPath;

            if (!Path.IsPathRooted(resolveProjectPath) || !File.Exists(resolveProjectPath))
            {
                resolveProjectPath = Path.GetFullPath(Path.Join(repoRoot, resolveProjectPath));
            }

            NuGetContext nugetContext = new NuGetContext(Path.GetDirectoryName(resolveProjectPath));

            // Target framework compatibility check
            foreach (var package in candidatePackages)
            {
                if (package.Version is null ||
                    !VersionRange.TryParse(package.Version, out var nuGetVersionRange))
                {
                    // If version is not valid, return original packages and revert
                    return packages;
                }

                if (nuGetVersionRange.IsFloating)
                {
                    // If a wildcard version, the original project specified it this way and we can count on restore to do the appropriate thing
                    continue;
                }

                var nuGetVersion = nuGetVersionRange.MinVersion; // not a wildcard, so `MinVersion` is just the version itself
                var packageIdentity = new NuGet.Packaging.Core.PackageIdentity(package.Name, nuGetVersion);

                bool isNewPackageCompatible = await CompatibilityChecker.CheckAsync(packageIdentity, targetFrameworks, nugetContext, logger, CancellationToken.None);
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

    private static IEnumerable<PackageSource>? LoadPackageSources(string nugetConfigPath, ILogger logger)
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
            logger.Warn("Error while parsing NuGet.config");
            logger.Warn(ex.Message);

            // Nuget.config is invalid. Won't be able to do anything with specific sources.
            return null;
        }
    }

    internal static Task<string> CreateTempProjectAsync(
        DirectoryInfo tempDir,
        string repoRoot,
        string projectPath,
        string targetFramework,
        IReadOnlyCollection<Dependency> packages,
        ExperimentsManager experimentsManager,
        ILogger logger,
        bool usePackageDownload = false,
        bool importDependencyTargets = true
    ) => CreateTempProjectAsync(tempDir, repoRoot, projectPath, new XElement("TargetFramework", targetFramework), packages, experimentsManager, logger, usePackageDownload, importDependencyTargets);

    internal static Task<string> CreateTempProjectAsync(
        DirectoryInfo tempDir,
        string repoRoot,
        string projectPath,
        ImmutableArray<string> targetFrameworks,
        IReadOnlyCollection<Dependency> packages,
        ExperimentsManager experimentsManager,
        ILogger logger,
        bool usePackageDownload = false,
        bool importDependencyTargets = true
    ) => CreateTempProjectAsync(tempDir, repoRoot, projectPath, new XElement("TargetFrameworks", string.Join(";", targetFrameworks)), packages, experimentsManager, logger, usePackageDownload, importDependencyTargets);

    private static async Task<string> CreateTempProjectAsync(
        DirectoryInfo tempDir,
        string repoRoot,
        string projectPath,
        XElement targetFrameworkElement,
        IReadOnlyCollection<Dependency> packages,
        ExperimentsManager experimentsManager,
        ILogger logger,
        bool usePackageDownload,
        bool importDependencyTargets)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath);
        projectDirectory ??= repoRoot;

        if (experimentsManager.InstallDotnetSdks)
        {
            var globalJsonPath = PathHelper.GetFileInDirectoryOrParent(projectPath, repoRoot, "global.json", caseSensitive: true);
            if (globalJsonPath is not null)
            {
                File.Copy(globalJsonPath, Path.Combine(tempDir.FullName, "global.json"));
            }
        }

        var nugetConfigPath = PathHelper.GetFileInDirectoryOrParent(projectPath, repoRoot, "NuGet.Config", caseSensitive: false);
        if (nugetConfigPath is not null)
        {
            // Copy nuget.config to temp project directory
            File.Copy(nugetConfigPath, Path.Combine(tempDir.FullName, "NuGet.Config"));
            var nugetConfigDir = Path.GetDirectoryName(nugetConfigPath);

            var packageSources = LoadPackageSources(nugetConfigPath, logger);
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
                .Select(p => $"<{(usePackageDownload ? "PackageDownload" : "PackageReference")} {(p.IsUpdate ? "Update" : "Include")}=\"{p.Name}\" Version=\"{(p.Version!.Contains("*") ? p.Version : $"[{p.Version}]")}\" />"));

        var dependencyTargetsImport = importDependencyTargets
            ? $"""<Import Project="{GetFileFromRuntimeDirectory("DependencyDiscovery.targets")}" />"""
            : string.Empty;

        var projectContents = $"""
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                {targetFrameworkElement}
              </PropertyGroup>
              {dependencyTargetsImport}
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
                <!-- Really ensure CPM is disabled -->
                <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
              </PropertyGroup>
            </Project>
            """);

        await File.WriteAllTextAsync(Path.Combine(tempDir.FullName, "Directory.Build.targets"), "<Project />");

        return tempProjectPath;
    }

    internal static async Task<ImmutableArray<string>> GetTargetFrameworkValuesFromProject(string repoRoot, string projectPath, ExperimentsManager experimentsManager, ILogger logger)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath)!;
        var (exitCode, stdOut, stdErr) = await HandleGlobalJsonAsync(projectDirectory, repoRoot, experimentsManager, async () =>
        {
            var targetsHelperPath = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!, "TargetFrameworkReporter.targets");
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(
                [
                    "msbuild",
                    projectPath,
                    "/t:ReportTargetFramework",
                    $"/p:CustomAfterMicrosoftCommonCrossTargetingTargets={targetsHelperPath}",
                    $"/p:CustomAfterMicrosoftCommonTargets={targetsHelperPath}",
                ],
                projectDirectory,
                experimentsManager
            );
            return (exitCode, stdOut, stdErr);
        }, logger);
        ThrowOnError(stdOut);
        if (exitCode != 0)
        {
            logger.Warn($"Error determining target frameworks.\nSTDOUT:\n{stdOut}\nSTDERR:\n{stdErr}");
        }

        // There are 2 possible return values:
        //   1. For SDK-style projects with a single TFM and legacy projects the output will look like:
        //      ProjectData::TargetFrameworkMoniker=.NETCoreApp,Version=8.0;ProjectData::TargetPlatformMoniker=Windows,Version=7.0
        //   2. For SDK-style projects with multiple TFMs the output will look like:
        //      ProjectData::TargetFrameworks=net8.0;net9.0
        var listedTargetFrameworks = new List<ValueTuple<string, string>>();
        var listedTfmMatch = Regex.Match(stdOut, "ProjectData::TargetFrameworks=(?<TargetFrameworks>.*)$", RegexOptions.Multiline);
        if (listedTfmMatch.Success)
        {
            var value = listedTfmMatch.Groups["TargetFrameworks"].Value;
            var foundTfms = value.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(tfm => ValueTuple.Create(tfm, string.Empty))
                .ToArray();
            listedTargetFrameworks.AddRange(foundTfms);
        }

        var individualTfmMatch = Regex.Match(stdOut, "ProjectData::TargetFrameworkMoniker=(?<TargetFrameworkMoniker>[^;]*);ProjectData::TargetPlatformMoniker=(?<TargetPlatformMoniker>.*)$", RegexOptions.Multiline);
        if (individualTfmMatch.Success)
        {
            var tfm = individualTfmMatch.Groups["TargetFrameworkMoniker"].Value;
            var tpm = individualTfmMatch.Groups["TargetPlatformMoniker"].Value;
            listedTargetFrameworks.Add(ValueTuple.Create(tfm, tpm));
        }

        var tfms = listedTargetFrameworks.Select(tfpm =>
            {
                try
                {
                    // Item2 is an optional component that looks like: "Windows,Version=7.0"
                    var framework = string.IsNullOrWhiteSpace(tfpm.Item2)
                        ? NuGetFramework.Parse(tfpm.Item1)
                        : NuGetFramework.ParseComponents(tfpm.Item1, tfpm.Item2);
                    if (framework.Framework == "_")
                    {
                        // error/default value
                        return null;
                    }

                    return framework;
                }
                catch
                {
                    return null;
                }
            })
            .Where(tfm => tfm is not null)
            .Select(tfm => tfm!.GetShortFolderName())
            .OrderBy(tfm => tfm)
            .ToImmutableArray();

        return tfms;
    }

    internal static async Task<ImmutableArray<Dependency>> GetAllPackageDependenciesAsync(
        string repoRoot,
        string projectPath,
        string targetFramework,
        IReadOnlyCollection<Dependency> packages,
        ExperimentsManager experimentsManager,
        ILogger logger
    )
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-resolution_");
        try
        {
            var topLevelPackagesNames = packages.Select(p => p.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var tempProjectPath = await CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, targetFramework, packages, experimentsManager, logger, importDependencyTargets: false);

            var projectDiscovery = await SdkProjectDiscovery.DiscoverAsync(repoRoot, tempDirectory.FullName, tempProjectPath, experimentsManager, logger);
            var allDependencies = projectDiscovery
                .Where(p => p.FilePath == Path.GetFileName(tempProjectPath))
                .FirstOrDefault()
                ?.Dependencies.ToImmutableArray() ?? [];

            return allDependencies;
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

    internal static string? GetMissingFile(string output)
    {
        var missingFilePatterns = new[]
        {
            new Regex(@"The imported project \""(?<FilePath>.*)\"" was not found"),
            new Regex(@"The imported file \""(?<FilePath>.*)\"" does not exist"),
        };
        var match = missingFilePatterns.Select(p => p.Match(output)).Where(m => m.Success).FirstOrDefault();
        if (match is not null)
        {
            return match.Groups["FilePath"].Value;
        }

        return null;
    }

    internal static void ThrowOnError(string output)
    {
        ThrowOnUnauthenticatedFeed(output);
        ThrowOnMissingFile(output);
        ThrowOnMissingPackages(output);
        ThrowOnUpdateNotPossible(output);
        ThrowOnRateLimitExceeded(output);
        ThrowOnTimeout(output);
        ThrowOnBadResponse(output);
        ThrowOnUnparseableFile(output);
    }

    private static void ThrowOnUnauthenticatedFeed(string stdout)
    {
        var unauthorizedMessageSnippets = new string[]
        {
            "The plugin credential provider could not acquire credentials",
            "401 (Unauthorized)",
            "error NU1301: Unable to load the service index for source",
            "Response status code does not indicate success: 401",
            "Response status code does not indicate success: 403",
        };
        if (unauthorizedMessageSnippets.Any(stdout.Contains))
        {
            throw new HttpRequestException(message: stdout, inner: null, statusCode: System.Net.HttpStatusCode.Unauthorized);
        }
    }

    private static void ThrowOnRateLimitExceeded(string stdout)
    {
        var rateLimitMessageSnippets = new string[]
        {
            "Response status code does not indicate success: 429",
            "429 (Too Many Requests)",
        };
        if (rateLimitMessageSnippets.Any(stdout.Contains))
        {
            throw new HttpRequestException(message: stdout, inner: null, statusCode: System.Net.HttpStatusCode.TooManyRequests);
        }
    }

    private static void ThrowOnTimeout(string stdout)
    {
        var patterns = new[]
        {
            new Regex(@"The HTTP request to 'GET (?<Source>[^']+)' has timed out after \d+ms"),
        };
        var match = patterns.Select(p => p.Match(stdout)).Where(m => m.Success).FirstOrDefault();
        if (match is not null)
        {
            throw new PrivateSourceTimedOutException(match.Groups["Source"].Value);
        }
    }

    private static void ThrowOnBadResponse(string stdout)
    {
        var patterns = new[]
        {
            new Regex(@"500 \(Internal Server Error\)"),
            new Regex(@"503 \(Service Unavailable\)"),
            new Regex(@"Response status code does not indicate success: 50\d"),
            new Regex(@"The file is not a valid nupkg"),
            new Regex(@"The response ended prematurely\. \(ResponseEnded\)"),
            new Regex(@"The content at '.*' is not valid XML\."),
        };
        if (patterns.Any(p => p.IsMatch(stdout)))
        {
            throw new HttpRequestException(message: stdout, inner: null, statusCode: System.Net.HttpStatusCode.InternalServerError);
        }
    }

    private static void ThrowOnMissingFile(string output)
    {
        var missingFile = GetMissingFile(output);
        if (missingFile is not null)
        {
            throw new MissingFileException(missingFile);
        }
    }

    private static void ThrowOnMissingPackages(string output)
    {
        var patterns = new[]
        {
            new Regex(@"Package '(?<PackageName>[^']*)' is not found on source '(?<PackageSource>[^$\r\n]*)'\."),
            new Regex(@"Unable to find package (?<PackageName>[^ ]+)\. No packages exist with this id in source\(s\): (?<PackageSource>.*)$", RegexOptions.Multiline),
            new Regex(@"Unable to find package (?<PackageName>[^ ]+) with version \((?<PackageVersion>[^)]+)\)"),
            new Regex(@"Unable to find package '(?<PackageName>[^ ]+)'\."),
            new Regex(@"Unable to resolve dependency '(?<PackageName>[^']+)'\. Source\(s\) used"),
            new Regex(@"Could not resolve SDK ""(?<PackageName>[^ ]+)""\."),
            new Regex(@"Failed to fetch results from V2 feed at '.*FindPackagesById\(\)\?id='(?<PackageName>[^']+)'&semVerLevel=2\.0\.0' with following message : Response status code does not indicate success: 404\."),
        };
        var matches = patterns.Select(p => p.Match(output)).Where(m => m.Success).ToArray();
        if (matches.Length > 0)
        {
            var packages = matches.Select(m =>
                {
                    var packageName = m.Groups["PackageName"].Value;
                    if (m.Groups.TryGetValue("PackageVersion", out var versionGroup))
                    {
                        packageName = $"{packageName}/{versionGroup.Value}";
                    }

                    return packageName;
                })
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            throw new DependencyNotFoundException(packages);
        }
    }

    private static void ThrowOnUpdateNotPossible(string output)
    {
        var patterns = new[]
        {
            new Regex(@"Unable to resolve dependencies\. '(?<PackageName>[^ ]+) (?<PackageVersion>[^']+)'"),
            new Regex(@"Could not install package '(?<PackageName>[^ ]+) (?<PackageVersion>[^']+)'. You are trying to install this package"),
            new Regex(@"Unable to find a version of '[^']+' that is compatible with '[^ ]+ [^ ]+ constraint: (?<PackageName>[^ ]+) \([^ ]+ (?<PackageVersion>[^)]+)\)'"),
            new Regex(@"the following error\(s\) may be blocking the current package operation: '(?<PackageName>[^ ]+) (?<PackageVersion>[^ ]+) constraint:"),
            new Regex(@"Unable to resolve '(?<PackageName>[^']+)'. An additional constraint '\((?<PackageVersion>[^)]+)\)' defined in packages.config prevents this operation."),
        };
        var matches = patterns.Select(p => p.Match(output)).Where(m => m.Success);
        if (matches.Any())
        {
            var packages = matches.Select(m => $"{m.Groups["PackageName"].Value}.{m.Groups["PackageVersion"].Value}").Distinct().ToArray();
            throw new UpdateNotPossibleException(packages);
        }
    }

    private static void ThrowOnUnparseableFile(string output)
    {
        var patterns = new[]
        {
            new Regex(@"\nAn error occurred while reading file '(?<FilePath>[^']+)': (?<Message>[^\n]*)\n"),
            new Regex(@"NuGet\.Config is not valid XML\. Path: '(?<FilePath>[^']+)'\.\n\s*(?<Message>[^\n]*)(\n|$)"),
        };
        var match = patterns.Select(p => p.Match(output)).Where(m => m.Success).FirstOrDefault();
        if (match is not null)
        {
            throw new UnparseableFileException(match.Groups["Message"].Value, match.Groups["FilePath"].Value);
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
}
