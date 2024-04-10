using System.Collections.Immutable;
using System.Diagnostics.CodeAnalysis;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;

using Microsoft.Build.Construction;
using Microsoft.Build.Definition;
using Microsoft.Build.Evaluation;
using Microsoft.Build.Exceptions;
using Microsoft.Build.Locator;
using Microsoft.Extensions.FileSystemGlobbing;

using NuGet.Configuration;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

internal static partial class MSBuildHelper
{
    public static string MSBuildPath { get; private set; } = string.Empty;

    public static bool IsMSBuildRegistered => MSBuildPath.Length > 0;

    static MSBuildHelper()
    {
        RegisterMSBuild();
    }

    public static void RegisterMSBuild()
    {
        // Ensure MSBuild types are registered before calling a method that loads the types
        if (!IsMSBuildRegistered)
        {
            var globalJsonPath = "global.json";
            var tempGlobalJsonPath = globalJsonPath + Guid.NewGuid().ToString();
            var globalJsonExists = File.Exists(globalJsonPath);
            try
            {
                if (globalJsonExists)
                {
                    Console.WriteLine("Temporarily removing `global.json` for MSBuild detection.");
                    File.Move(globalJsonPath, tempGlobalJsonPath);
                }

                var defaultInstance = MSBuildLocator.QueryVisualStudioInstances().First();
                MSBuildPath = defaultInstance.MSBuildPath;
                MSBuildLocator.RegisterInstance(defaultInstance);
            }
            finally
            {
                if (globalJsonExists)
                {
                    Console.WriteLine("Restoring `global.json` after MSBuild detection.");
                    File.Move(tempGlobalJsonPath, globalJsonPath);
                }
            }
        }
    }

    public static string[] GetTargetFrameworkMonikers(ImmutableArray<ProjectBuildFile> buildFiles)
    {
        HashSet<string> targetFrameworkValues = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, Property> propertyInfo = new(StringComparer.OrdinalIgnoreCase);

        foreach (var buildFile in buildFiles)
        {
            var projectRoot = CreateProjectRootElement(buildFile);

            foreach (var property in projectRoot.Properties)
            {
                if (property.Name.Equals("TargetFramework", StringComparison.OrdinalIgnoreCase) ||
                    property.Name.Equals("TargetFrameworks", StringComparison.OrdinalIgnoreCase))
                {
                    if (buildFile.IsOutsideBasePath)
                    {
                        continue;
                    }

                    foreach (var tfm in property.Value.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                    {
                        targetFrameworkValues.Add(tfm);
                    }
                }
                else if (property.Name.Equals("TargetFrameworkVersion", StringComparison.OrdinalIgnoreCase))
                {
                    if (buildFile.IsOutsideBasePath)
                    {
                        continue;
                    }

                    // For packages.config projects that use TargetFrameworkVersion, we need to convert it to TargetFramework
                    targetFrameworkValues.Add($"net{property.Value.TrimStart('v').Replace(".", "")}");
                }
                else
                {
                    propertyInfo[property.Name] = new(property.Name, property.Value, buildFile.RelativePath);
                }
            }
        }

        HashSet<string> targetFrameworks = new(StringComparer.OrdinalIgnoreCase);

        foreach (var targetFrameworkValue in targetFrameworkValues)
        {
            var (resultType, _, tfms, _, errorMessage) =
                GetEvaluatedValue(targetFrameworkValue, propertyInfo, propertiesToIgnore: ["TargetFramework", "TargetFrameworks"]);
            if (resultType != EvaluationResultType.Success)
            {
                continue;
            }

            if (string.IsNullOrEmpty(tfms))
            {
                continue;
            }

            foreach (var tfm in tfms.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                targetFrameworks.Add(tfm);
            }
        }

        return targetFrameworks.ToArray();
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
                    properties[property.Name] = new(property.Name, property.Value, buildFile.RelativePath);
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
                foreach (var attributeValue in new[] { packageItem.Include, packageItem.Update })
                {
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

            // We don't know the version for range requirements or wildcard
            // requirements, so return "" for these.
            yield return packageVersion.Contains(',') || packageVersion.Contains('*')
                ? new Dependency(name, string.Empty, dependencyType, EvaluationResult: evaluationResult, IsUpdate: isUpdate)
                : new Dependency(name, packageVersion, dependencyType, EvaluationResult: evaluationResult, IsUpdate: isUpdate);
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

    internal static async Task<bool> DependenciesAreCoherentAsync(string repoRoot, string projectPath, string targetFramework, Dependency[] packages, Logger logger)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-coherence_");
        try
        {
            var tempProjectPath = await CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, targetFramework, packages);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunAsync("dotnet", $"restore \"{tempProjectPath}\"", workingDirectory: tempDirectory.FullName);

            // NU1608: Detected package version outside of dependency constraint

            return exitCode == 0 && !stdOut.Contains("NU1608");
        }
        finally
        {
            tempDirectory.Delete(recursive: true);
        }
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
                    var subDir = localSource.Source.Split(nugetConfigDir)[1];
                    var destPath = Path.Join(tempDir.FullName, subDir);
                    if (Directory.Exists(localSource.Source))
                    {
                        PathHelper.CopyDirectory(localSource.Source, destPath);
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
              </PropertyGroup>
            </Project>
            """);

        await File.WriteAllTextAsync(Path.Combine(tempDir.FullName, "Directory.Build.targets"), "<Project />");
        await File.WriteAllTextAsync(Path.Combine(tempDir.FullName, "Directory.Packages.props"), "<Project />");

        return tempProjectPath;
    }

    internal static async Task<Dependency[]> GetAllPackageDependenciesAsync(
        string repoRoot,
        string projectPath,
        string targetFramework,
        IReadOnlyCollection<Dependency> packages,
        Logger? logger = null)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-resolution_");
        try
        {
            var topLevelPackagesNames = packages.Select(p => p.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var tempProjectPath = await CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, targetFramework, packages);

            var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("dotnet", $"build \"{tempProjectPath}\" /t:_ReportDependencies", workingDirectory: tempDirectory.FullName);

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
                        var packageName = match.Groups["PackageName"].Value;
                        var isTransitive = !topLevelPackagesNames.Contains(packageName);
                        return new Dependency(packageName, match.Groups["PackageVersion"].Value, DependencyType.Unknown, TargetFrameworks: tfms, IsTransitive: isTransitive);
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

    internal static async Task<ImmutableArray<ProjectBuildFile>> LoadBuildFilesAsync(string repoRootPath, string projectPath, bool includeSdkPropsAndTargets = false)
    {
        var buildFileList = new List<string>
        {
            projectPath.NormalizePathToUnix() // always include the starting project
        };

        // a global.json file might cause problems with the dotnet msbuild command; create a safe version temporarily
        TryGetGlobalJsonPath(repoRootPath, projectPath, out var globalJsonPath);
        var safeGlobalJsonName = $"{globalJsonPath}{Guid.NewGuid()}";

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
            var project = Project.FromFile(projectPath, new ProjectOptions
            {
                LoadSettings = ProjectLoadSettings.IgnoreMissingImports,
                ProjectCollection = projectCollection,
            });
            buildFileList.AddRange(project.Imports.Select(i => i.ImportedProject.FullPath.NormalizePathToUnix()));
        }
        catch (InvalidProjectFileException)
        {
            return [];
        }
        finally
        {
            if (globalJsonPath is not null)
            {
                File.Move(safeGlobalJsonName, globalJsonPath, overwrite: true);
            }
        }

        var repoRootPathPrefix = repoRootPath.NormalizePathToUnix() + "/";
        var buildFiles = includeSdkPropsAndTargets
            ? buildFileList.Distinct()
            : buildFileList
                .Where(f => f.StartsWith(repoRootPathPrefix, StringComparison.OrdinalIgnoreCase))
                .Distinct();
        var result = buildFiles
            .Where(File.Exists)
            .Select(path => ProjectBuildFile.Open(repoRootPath, path))
            .ToImmutableArray();
        return result;
    }

    [GeneratedRegex("^\\s*NuGetData::Package=(?<PackageName>[^,]+), Version=(?<PackageVersion>.+)$")]
    private static partial Regex PackagePattern();
}
