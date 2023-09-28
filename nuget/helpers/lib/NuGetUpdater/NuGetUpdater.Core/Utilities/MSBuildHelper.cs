using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml.Linq;
using System.Xml.XPath;

using Microsoft.Build.Construction;
using Microsoft.Build.Locator;

namespace NuGetUpdater.Core;

internal static partial class MSBuildHelper
{
    public static string MSBuildPath { get; private set; } = string.Empty;

    public static bool IsMSBuildRegistered => MSBuildPath.Length > 0;

    public static void RegisterMSBuild()
    {
        // Ensure MSBuild types are registered before calling a method that loads the types
        if (!IsMSBuildRegistered)
        {
            var defaultInstance = MSBuildLocator.QueryVisualStudioInstances().First();
            MSBuildPath = defaultInstance.MSBuildPath;
            MSBuildLocator.RegisterInstance(defaultInstance);
        }
    }

    public static string[] GetTargetFrameworkMonikers(ImmutableArray<BuildFile> buildFiles)
    {
        HashSet<string> targetFrameworkValues = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, string> propertyInfo = new(StringComparer.OrdinalIgnoreCase);

        foreach (var buildFile in buildFiles)
        {
            var document = XmlExtensions.LoadXDocumentWithoutNamespaces(buildFile.Path);
            foreach (var property in document.XPathSelectElements("//PropertyGroup/*"))
            {
                if (property.Name.LocalName.Equals("TargetFramework", StringComparison.OrdinalIgnoreCase) ||
                    property.Name.LocalName.Equals("TargetFrameworks", StringComparison.OrdinalIgnoreCase))
                {
                    targetFrameworkValues.Add(property.Value.Trim());
                }
                else if (property.Name.LocalName.Equals("TargetFrameworkVersion", StringComparison.OrdinalIgnoreCase))
                {
                    targetFrameworkValues.Add($"net{property.Value.Trim().TrimStart('v').Replace(".", "")}");
                }
                else
                {
                    propertyInfo[property.Name.LocalName] = property.Value.Trim();
                }
            }
        }

        HashSet<string> targetFrameworks = new(StringComparer.OrdinalIgnoreCase);

        foreach (var targetFrameworkValue in targetFrameworkValues)
        {
            var tfms = targetFrameworkValue;
            if (tfms.StartsWith("$(") && tfms.EndsWith(")"))
            {
                var propertyName = tfms.Substring(2, tfms.Length - 3);
                while (propertyName is not null)
                {
                    propertyName = propertyInfo.TryGetValue(propertyName, out tfms) && tfms.StartsWith("$(") && tfms.EndsWith(")")
                        ? tfms.Substring(2, tfms.Length - 3)
                        : null;
                }
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
        var projectRootElement = ProjectRootElement.Open(projFilePath);

        projectStack.Push((Path.GetFullPath(Path.GetDirectoryName(projFilePath)!), projectRootElement));

        while (projectStack.Count > 0)
        {
            var (folderPath, tmpProject) = projectStack.Pop();
            foreach (var projectReference in tmpProject.Items.Where(static x => x.ItemType == "ProjectReference" || x.ItemType == "ProjectFile"))
            {
                if (projectReference.Include is not { } projectPath)
                {
                    continue;
                }

                projectPath = PathHelper.GetFullPathFromRelative(folderPath, projectPath);

                var projectExtension = Path.GetExtension(projectPath).ToLowerInvariant();
                if (projectExtension == ".proj")
                {
                    var additionalProjectRootElement = ProjectRootElement.Open(projectPath);
                    projectStack.Push((Path.GetFullPath(Path.GetDirectoryName(projectPath)!), additionalProjectRootElement));
                }
                else if (projectExtension == ".csproj" || projectExtension == ".vbproj" || projectExtension == ".fsproj")
                {
                    yield return projectPath;
                }
            }
        }
    }

    public static IEnumerable<(string PackageName, string Version)> GetTopLevelPackageDependenyInfos(ImmutableArray<BuildFile> buildFiles)
    {
        Dictionary<string, string> packageInfo = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, string> packageVersionInfo = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, string> propertyInfo = new(StringComparer.OrdinalIgnoreCase);

        foreach (var buildFile in buildFiles)
        {
            var document = XmlExtensions.LoadXDocumentWithoutNamespaces(buildFile.Path);
            var packageReferences = document.XPathSelectElements("//ItemGroup/PackageReference | //ItemGroup/GlobalPackageReference");
            foreach (var packageReference in packageReferences)
            {
                var packageName = packageReference.GetMetadataCaseInsensitive("Include") ?? packageReference.GetMetadataCaseInsensitive("Update");
                var versionSpecification = packageReference.GetMetadataCaseInsensitive("Version") ?? packageReference.GetMetadataCaseInsensitive("VersionOverride") ?? string.Empty;
                if (!string.IsNullOrEmpty(packageName))
                {
                    packageInfo[packageName] = versionSpecification;
                }
            }

            foreach (var versionPackage in document.XPathSelectElements("//ItemGroup/PackageVersion"))
            {
                var packageName = versionPackage.GetMetadataCaseInsensitive("Include");
                var versionSpecification = versionPackage.GetMetadataCaseInsensitive("Version") ?? string.Empty;
                if (!string.IsNullOrEmpty(packageName))
                {
                    packageVersionInfo[packageName] = versionSpecification;
                }
            }

            foreach (var property in document.XPathSelectElements("//PropertyGroup/*"))
            {
                propertyInfo[property.Name.LocalName] = property.Value;
            }
        }

        foreach (var (name, version) in packageInfo)
        {
            if (version.Length != 0 || !packageVersionInfo.TryGetValue(name, out var packageVersion))
            {
                packageVersion = version;
            }

            if (packageVersion.StartsWith("$(") && packageVersion.EndsWith(")"))
            {
                var propertyName = packageVersion.Substring(2, packageVersion.Length - 3);
                var propertyValue = "";
                while (propertyName is not null)
                {
                    propertyName = propertyInfo.TryGetValue(propertyName, out propertyValue) && propertyValue.StartsWith("$(") && propertyValue.EndsWith(")")
                        ? propertyValue.Substring(2, propertyValue.Length - 3)
                        : null;
                }
                packageVersion = propertyValue ?? string.Empty;
            }

            packageVersion = packageVersion.TrimStart('[', '(').TrimEnd(']', ')');

            // We don't know the version for range requirements or wildcard
            // requirements, so return "" for these.
            yield return packageVersion.Contains(',') || packageVersion.Contains('*')
                ? (name, string.Empty)
                : (name, packageVersion);
        }
    }

    internal static async Task<(string PackageName, string Version)[]> GetAllPackageDependenciesAsync(string repoRoot, string targetFramework, (string PackageName, string Version)[] packages)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-resolution_");
        try
        {
            var topLevelFiles = Directory.GetFiles(repoRoot);
            var nugetConfigPath = topLevelFiles.FirstOrDefault(n => string.Compare(Path.GetFileName(n), "NuGet.Config", StringComparison.OrdinalIgnoreCase) == 0);
            if (nugetConfigPath is not null)
            {
                File.Copy(nugetConfigPath, Path.Combine(tempDirectory.FullName, "NuGet.Config"));
            }

            var packageReferences = string.Join(
                Environment.NewLine,
                packages
                    .Where(p => !string.IsNullOrWhiteSpace(p.Version)) // empty `Version` attributes will cause the temporary project to not build
                    .Select(static p => $"<PackageReference Include=\"{p.PackageName}\" Version=\"{p.Version}\" />"));

            var projectContents = $"""
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>{targetFramework}</TargetFramework>
                    <GenerateDependencyFile>true</GenerateDependencyFile>
                  </PropertyGroup>
                  <ItemGroup>
                    {packageReferences}
                  </ItemGroup>
                  <Target Name="_CollectDependencies" DependsOnTargets="GenerateBuildDependencyFile">
                    <ItemGroup>
                      <_NuGetPacakgeData Include="@(NativeCopyLocalItems)" />
                      <_NuGetPacakgeData Include="@(ResourceCopyLocalItems)" />
                      <_NuGetPacakgeData Include="@(RuntimeCopyLocalItems)" />
                      <_NuGetPacakgeData Include="@(ResolvedAnalyzers)" />
                    </ItemGroup>
                  </Target>
                  <Target Name="_ReportDependencies" DependsOnTargets="_CollectDependencies">
                    <Message Text="NuGetData::Package=%(_NuGetPacakgeData.NuGetPackageId), Version=%(_NuGetPacakgeData.NuGetPackageVersion)"
                             Condition="'%(_NuGetPacakgeData.NuGetPackageId)' != '' AND '%(_NuGetPacakgeData.NuGetPackageVersion)' != ''"
                             Importance="High" />
                  </Target>
                </Project>
                """;
            var projectPath = Path.Combine(tempDirectory.FullName, "Project.csproj");
            await File.WriteAllTextAsync(projectPath, projectContents);

            // prevent directory crawling
            await File.WriteAllTextAsync(Path.Combine(tempDirectory.FullName, "Directory.Build.props"), "<Project />");
            await File.WriteAllTextAsync(Path.Combine(tempDirectory.FullName, "Directory.Build.targets"), "<Project />");
            await File.WriteAllTextAsync(Path.Combine(tempDirectory.FullName, "Directory.Packages.props"), "<Project />");

            var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("dotnet", $"build \"{projectPath}\" /t:_ReportDependencies");
            var lines = stdout.Split('\n').Select(line => line.Trim());
            var pattern = PackagePattern();
            var allPackages = lines
                .Select(line => pattern.Match(line))
                .Where(match => match.Success)
                .Select(match => (match.Groups["PackageName"].Value, match.Groups["PackageVersion"].Value))
                .ToArray();
            return allPackages;
        }
        finally
        {
            try
            {
                Directory.Delete(tempDirectory.FullName, true);
            }
            catch
            {
            }
        }
    }

    [GeneratedRegex("^\\s*NuGetData::Package=(?<PackageName>[^,]+), Version=(?<PackageVersion>.+)$")]
    private static partial Regex PackagePattern();
}