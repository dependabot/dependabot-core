using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml.Linq;

using DiffPlex;
using DiffPlex.DiffBuilder;
using DiffPlex.DiffBuilder.Model;

using Microsoft.Build.Locator;
using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

public partial class NuGetUpdaterWorker
{
    private const string PackagesConfigFileName = "packages.config";

    public bool Verbose { get; set; }
    private readonly TextWriter _logOutput;

    public NuGetUpdaterWorker(bool verbose)
    {
        Verbose = verbose;
        _logOutput = Console.Out;
    }

    private void Log(string message)
    {
        if (Verbose)
        {
            _logOutput.WriteLine(message);
        }
    }

    public async Task RunAsync(string repoRootPath, string filePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion)
    {
        if (!Path.IsPathRooted(filePath) || !File.Exists(filePath))
        {
            filePath = Path.GetFullPath(Path.Join(repoRootPath, filePath));
        }

        var extension = Path.GetExtension(filePath).ToLowerInvariant();
        switch (extension)
        {
            case ".sln":
                await RunForSolutionAsync(repoRootPath, filePath, dependencyName, previousDependencyVersion, newDependencyVersion);
                break;
            case ".proj":
                await RunForProjFileAsync(repoRootPath, filePath, dependencyName, previousDependencyVersion, newDependencyVersion);
                break;
            case ".csproj":
            case ".fsproj":
            case ".vbproj":
                await RunForProjectAsync(repoRootPath, filePath, dependencyName, previousDependencyVersion, newDependencyVersion);
                break;
        }
    }

    private async Task RunForSolutionAsync(string repoRootPath, string solutionPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion)
    {
        Log($"Running for solution [{solutionPath}]");
        var solutionDirectory = Path.GetDirectoryName(solutionPath);
        var solutionContent = await File.ReadAllTextAsync(solutionPath);
        var projectSubPaths = GetProjectSubPathsFromSolution(solutionContent);
        foreach (var projectSubPath in projectSubPaths)
        {
            var projectFullPath = JoinPath(solutionDirectory, projectSubPath);
            await RunForProjectAsync(repoRootPath, projectFullPath, dependencyName, previousDependencyVersion, newDependencyVersion);
        }
    }

    private async Task RunForProjFileAsync(string repoRootPath, string projFilePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion)
    {
        Log($"Running for proj file [{projFilePath}]");
        var projectFilePaths = MSBuildHelper.GetAllProjectPaths(projFilePath);
        foreach (var projectFullPath in projectFilePaths)
        {
            // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
            if (File.Exists(projectFullPath))
            {
                await RunForProjectAsync(repoRootPath, projectFullPath, dependencyName, previousDependencyVersion, newDependencyVersion);
            }
        }
    }

    private async Task RunForProjectAsync(string repoRootPath, string projectPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion)
    {
        Log($"Running for project [{projectPath}]");
        var projectFileContents = await File.ReadAllTextAsync(projectPath);
        var projectDirectory = Path.GetDirectoryName(projectPath);
        var packagesConfigPath = JoinPath(projectDirectory, PackagesConfigFileName);
        if (File.Exists(packagesConfigPath))
        {
            Log($"  Found {PackagesConfigFileName}; running with NuGet.exe");

            // use NuGet.exe to perform update

            // ensure local packages directory exists
            var packagesSubDirectory = GetPathToPackagesDirectory(projectFileContents, dependencyName, previousDependencyVersion);
            if (packagesSubDirectory is null)
            {
                Log($"    Unable to find packages directory for project [{projectPath}].");
                return;
            }

            Log($"    Using packages directory [{packagesSubDirectory}] for project [{projectPath}].");

            var packagesDirectory = JoinPath(projectDirectory, packagesSubDirectory);
            Directory.CreateDirectory(packagesDirectory);

            var args = new List<string>()
            {
                "update",
                packagesConfigPath,
                "-Id",
                dependencyName,
                "-Version",
                newDependencyVersion,
                "-RepositoryPath",
                packagesDirectory,
                "-NonInteractive",
            };

            Log("    Finding MSBuild...");
            var msbuildDirectory = GetPathToMSBuild();
            if (msbuildDirectory is not null)
            {
                args.Add("-MSBuildPath");
                args.Add(msbuildDirectory); // e.g., /usr/share/dotnet/sdk/7.0.203
            }

            var outputBuilder = new StringBuilder();
            var writer = new StringWriter(outputBuilder);

            var originalOut = Console.Out;
            var originalError = Console.Error;
            Console.SetOut(writer);
            Console.SetError(writer);

            var currentDir = Environment.CurrentDirectory;
            try
            {
                Log($"    Running NuGet.exe with args: {string.Join(" ", args)}");

                Environment.CurrentDirectory = packagesDirectory;
                var result = NuGet.CommandLine.Program.Main(args.ToArray());
                var fullOutput = outputBuilder.ToString();
                Log($"    Result: {result}");
                Log($"    Output:\n{fullOutput}");
                if (result != 0)
                {
                    throw new Exception(fullOutput);
                }
            }
            catch (Exception e)
            {
                Log($"Error: {e}");
                throw;
            }
            finally
            {
                Environment.CurrentDirectory = currentDir;
                Console.SetOut(originalOut);
                Console.SetError(originalError);
            }

            var newProjectFileContents = await File.ReadAllTextAsync(projectPath);
            var normalizedProjectFileContents = NormalizeDirectorySeparatorsInProject(newProjectFileContents);

            // Update binding redirects
            normalizedProjectFileContents = await BindingRedirectManager.UpdateBindingRedirectsAsync(normalizedProjectFileContents, projectPath);

            Log("    Writing project file back to disk");
            await File.WriteAllTextAsync(projectPath, normalizedProjectFileContents);
        }
        else
        {
            // SDK-style project, modify the XML directly
            Log("  Running for SDK-style project");
            var buildFiles = LoadBuildFiles(repoRootPath, projectPath);

            // update all dependencies, including transitive
            var tfms = GetTargetFrameworkMonikersFromProjectContents(projectFileContents);
            var tfmsAndDependencies = new Dictionary<string, (string PackageName, string Version)[]>();
            foreach (var tfm in tfms)
            {
                var dependencies = await GetAllPackageDependencies(repoRootPath, tfm, dependencyName, newDependencyVersion);
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
                        Log($"Package [{packageName}] tried to update to version [{packageVersion}], but found conflicting package version of [{existingVersion}].");
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
                Log($"The following target frameworks could not find packages to upgrade: {string.Join(", ", unupgradableTfms)}");
                return;
            }

            var result = TryUpdateDependencyVersion(buildFiles, dependencyName, previousDependencyVersion, newDependencyVersion);
            if (result == UpdateResult.NotFound)
            {
                Log($"Root package [{dependencyName}/{previousDependencyVersion}] was not updated; skipping dependencies.");
                return;
            }

            foreach (var (packageName, packageVersion) in packagesAndVersions.Where(kvp => string.Compare(kvp.Key, dependencyName, StringComparison.OrdinalIgnoreCase) != 0))
            {
                TryUpdateDependencyVersion(buildFiles, packageName, previousDependencyVersion: null, newDependencyVersion: packageVersion);
            }

            foreach (var buildFile in buildFiles)
            {
                buildFile.Save();
            }
        }
        Log("Update complete.");
    }

    private static string JoinPath(string? path1, string path2)
    {
        // don't root out the second path
        if (path2.StartsWith('/'))
        {
            path2 = path2[1..];
        }

        if (path1 is null)
        {
            return path2;
        }

        return Path.Combine(path1, path2);
    }

    private static string? GetPathToMSBuild()
        => MSBuildLocator.QueryVisualStudioInstances().FirstOrDefault()?.MSBuildPath;

    internal static string NormalizeDirectorySeparatorsInProject(string xml)
    {
        var originalXml = Parser.ParseText(xml);
        var hintPathReplacements = new Dictionary<SyntaxNode, SyntaxNode>();
        var hintPaths = originalXml.Descendants().Where(d => d.Name == "HintPath" && d.Parent.Name == "Reference");
        foreach (var hintPath in hintPaths)
        {
            var hintPathValue = hintPath.GetContentValue();
            var updatedHintPathValue = hintPathValue.Replace("/", "\\");
            var updatedHintPathContent = SyntaxFactory.XmlTextLiteralToken(updatedHintPathValue, null, null);
            var updatedHintPath = hintPath.WithContent(SyntaxFactory.List(updatedHintPathContent));
            hintPathReplacements.Add(hintPath.AsNode, updatedHintPath.AsNode);
        }

        var updatedXml = originalXml.ReplaceNodes(hintPathReplacements.Keys, (n, _) => hintPathReplacements[n]);
        var result = updatedXml.ToFullString();
        return result;
    }

    internal static string? GetPathToPackagesDirectory(string projectContents, string dependencyName, string dependencyVersion)
    {
        // the packages directory can be found from the hint path of the matching dependency, e.g., when given "Newtonsoft.Json", "7.0.1", and a project like this:
        // <Project>
        //   <ItemGroup>
        //     <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
        //       <HintPath>..\packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
        //     </Reference>
        //   <ItemGroup>
        // </Project>
        //
        // the result should be "..\packages"
        var hintPathSubString = $"{dependencyName}.{dependencyVersion}";

        var document = XDocument.Parse(projectContents);
        var referenceElements = document.Descendants().Where(d => d.Name.LocalName == "Reference");
        var matchingReferenceElements = referenceElements.Where(r => (r.Attribute("Include")?.Value ?? string.Empty).StartsWith($"{dependencyName},", StringComparison.OrdinalIgnoreCase));
        foreach (var matchingReferenceElement in matchingReferenceElements)
        {
            var hintPathElement = matchingReferenceElement.Elements().FirstOrDefault(e => e.Name.LocalName == "HintPath");
            if (hintPathElement is not null)
            {
                var hintPathSubStringLocation = hintPathElement.Value.IndexOf(hintPathSubString);
                if (hintPathSubStringLocation >= 0)
                {
                    var subpath = hintPathElement.Value[..hintPathSubStringLocation];
                    if (subpath.EndsWith("/") || subpath.EndsWith("\\"))
                    {
                        subpath = subpath[..^1];
                    }

                    return subpath;
                }
            }
        }

        return null;
    }

    internal static string[] GetProjectSubPathsFromSolution(string solutionContent)
    {
        var slnLines = solutionContent.Split('\n').Select(l => l.TrimEnd('\r'));
        var projectPattern = new Regex(@"^Project\(""\{(?<projectTypeGuid>[^}]+)\}""\) = ""(?<projectDisplayName>[^""]+)"", ""(?<projectSubPath>[^""]+)"", ""\{(?<projectGuid>[^""]+)\}""$");
        var projectFilePaths = new List<string>();
        foreach (var line in slnLines)
        {
            var match = projectPattern.Match(line);
            if (match.Success)
            {
                var projectSubPath = match.Groups["projectSubPath"].Value.Replace('\\', '/');
                projectFilePaths.Add(projectSubPath);
            }
        }

        return projectFilePaths.ToArray();
    }

    private static ImmutableArray<BuildFile> LoadBuildFiles(string repoRootPath, string projectPath)
    {
        return new string[] { projectPath }
            .Concat(Directory.EnumerateFiles(repoRootPath, "*.props", SearchOption.AllDirectories))
            .Concat(Directory.EnumerateFiles(repoRootPath, "*.targets", SearchOption.AllDirectories))
            .Select(path => new BuildFile(path, Parser.ParseText(File.ReadAllText(path))))
            .ToImmutableArray();
    }

    private UpdateResult TryUpdateDependencyVersion(ImmutableArray<BuildFile> buildFiles, string dependencyName, string? previousDependencyVersion, string newDependencyVersion)
    {
        var foundCorrect = false;
        var updateWasPerformed = false;
        var propertyNames = new List<string>();

        // First we locate all the PackageReference, GlobalPackageReference, or PackageVersion which set the Version
        // or VersionOverride attribute. In the simplest case we can update the version attribute directly then move
        // on. When property substitution is used we have to additionally search for the property containing the version.

        foreach (var buildFile in buildFiles)
        {
            var updateAttributes = new List<XmlAttributeSyntax>();
            var packageNodes = FindPackageNode(buildFile.Xml, dependencyName);

            foreach (var packageNode in packageNodes)
            {
                var versionAttribute = packageNode.GetAttribute("Version") ?? packageNode.GetAttribute("VersionOverride");

                // Is this the case where version is specified with property substitution?
                if (versionAttribute.Value.StartsWith("$(") && versionAttribute.Value.EndsWith(")"))
                {
                    propertyNames.Add(versionAttribute.Value.Substring(2, versionAttribute.Value.Length - 3));
                }
                // Is this the case that the version is specified directly in the package node?
                else if (previousDependencyVersion is null || versionAttribute.Value == previousDependencyVersion)
                {
                    Log($"Found incorrect [{packageNode.Name}] version attribute in [{buildFile.Path}].");
                    updateAttributes.Add(versionAttribute);
                }
                else if (versionAttribute.Value == newDependencyVersion)
                {
                    Log($"Found correct [{packageNode.Name}] version attribute in [{buildFile.Path}].");
                    foundCorrect = true;
                }
            }

            if (updateAttributes.Count > 0)
            {
                var updatedXml = buildFile.Xml
                    .ReplaceNodes(updateAttributes, (o, n) => n.WithValue(newDependencyVersion));
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

                foreach (var propertyElement in propertyElements)
                {
                    var propertyContents = propertyElement.GetContentValue();

                    // Is this the case where this property contains another property substitution?
                    if (propertyContents.StartsWith("$(") && propertyContents.EndsWith(")"))
                    {
                        propertyNames.Add(propertyContents.Substring(2, propertyContents.Length - 3));
                    }
                    // Is this the case that the property contains the version?
                    else if (previousDependencyVersion is null || propertyContents == previousDependencyVersion)
                    {
                        Log($"Found incorrect version property [{propertyElement.Name}] in [{buildFile.Path}].");
                        updateProperties.Add((XmlElementSyntax)propertyElement.AsNode);
                    }
                    else if (propertyContents == newDependencyVersion)
                    {
                        Log($"Found correct version property [{propertyElement.Name}] in [{buildFile.Path}].");
                        foundCorrect = true;
                    }
                }

                if (updateProperties.Count > 0)
                {
                    var updatedXml = buildFile.Xml
                        .ReplaceNodes(updateProperties, (o, n) => n.WithContent(newDependencyVersion));
                    buildFile.Update(updatedXml);
                    updateWasPerformed = true;
                }
            }
        }

        return updateWasPerformed
            ? UpdateResult.Updated
            : foundCorrect
                ? UpdateResult.Correct
                : UpdateResult.NotFound;
    }

    private static IEnumerable<IXmlElementSyntax> FindPackageNode(XmlDocumentSyntax xml, string packageName)
    {
        return xml.Descendants().Where(e =>
                    (e.Name == "PackageReference" || e.Name == "GlobalPackageReference" || e.Name == "PackageVersion") &&
                    (e.GetAttributeValue("Include")?.Equals(packageName, StringComparison.OrdinalIgnoreCase) ?? e.GetAttributeValue("Update")?.Equals(packageName, StringComparison.OrdinalIgnoreCase) == true) &&
                    (e.GetAttribute("Version") is not null) || e.GetAttribute("VersionOverride") is not null);
    }

    internal static string[] GetTargetFrameworkMonikersFromProjectContents(string projectContents)
    {
        var root = XDocument.Parse(projectContents).Root;
        if (root is null)
        {
            return Array.Empty<string>();
        }

        var singularTfm = root.Descendants().FirstOrDefault(element => string.Compare(element.Name.LocalName, "TargetFramework", StringComparison.OrdinalIgnoreCase) == 0);
        if (singularTfm is not null)
        {
            return new[] { singularTfm.Value.Trim() };
        }

        var multipleTfms = root.Descendants().FirstOrDefault(element => string.Compare(element.Name.LocalName, "TargetFrameworks", StringComparison.OrdinalIgnoreCase) == 0);
        if (multipleTfms is null)
        {
            return Array.Empty<string>();
        }

        var tfms = multipleTfms.Value.Split(';').Select(tfm => tfm.Trim()).Where(tfm => tfm.Length > 0).ToArray();
        return tfms;
    }

    internal static async Task<(string PackageName, string Version)[]> GetAllPackageDependencies(string repoRoot, string targetFramework, string packageName, string version)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("package-dependency-resolution_");
        try
        {
            var topLevelFiles = Directory.GetFiles(repoRoot);
            var nugetConfigPath = topLevelFiles.FirstOrDefault(n => string.Compare(n, "NuGet.Config", StringComparison.OrdinalIgnoreCase) == 0);
            if (nugetConfigPath is not null)
            {
                File.Copy(nugetConfigPath, Path.Combine(repoRoot, "NuGet.Config"));
            }

            var projectContents = $"""
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>{targetFramework}</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="{packageName}" Version="{version}" />
                  </ItemGroup>
                  <Target Name="_CollectDependencies" DependsOnTargets="GenerateBuildDependencyFile">
                    <ItemGroup>
                      <_NuGetPacakgeData Include="@(NativeCopyLocalItems)" />
                      <_NuGetPacakgeData Include="@(ResourceCopyLocalItems)" />
                      <_NuGetPacakgeData Include="@(RuntimeCopyLocalItems)" />
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

            var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("dotnet", $"build \"{projectPath}\" /t:_ReportDependencies");
            var lines = stdout.Split('\n').Select(line => line.Trim());
            var pattern = new Regex(@"^\s*NuGetData::Package=(?<PackageName>[^,]+), Version=(?<PackageVersion>.+)$");
            var packages = lines
                .Select(line => pattern.Match(line))
                .Where(match => match.Success)
                .Select(match => (match.Groups["PackageName"].Value, match.Groups["PackageVersion"].Value))
                .ToArray();
            return packages;
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

    private class BuildFile
    {
        public string Path { get; }
        public XmlDocumentSyntax Xml { get; private set; }

        public XmlDocumentSyntax OriginalXml { get; private set; }

        public BuildFile(string path, XmlDocumentSyntax xml)
        {
            Path = path;
            Xml = xml;
            OriginalXml = xml;
        }

        public void Update(XmlDocumentSyntax xml)
        {
            Xml = xml;
        }

        public void Save()
        {
            if (OriginalXml == Xml)
            {
                return;
            }

            var originalXmlText = OriginalXml.ToFullString();
            var xmlText = Xml.ToFullString();

            if (HasAnyNonWhitespaceChanges(originalXmlText, xmlText))
            {
                File.WriteAllText(Path, xmlText);
                OriginalXml = Xml;
            }
        }

        private static bool HasAnyNonWhitespaceChanges(string oldText, string newText)
        {
            // Ignore white space
            oldText = Regex.Replace(oldText, @"\s+", string.Empty);
            newText = Regex.Replace(newText, @"\s+", string.Empty);

            var diffBuilder = new InlineDiffBuilder(new Differ());
            var diff = diffBuilder.BuildDiffModel(oldText, newText);
            foreach (var line in diff.Lines)
            {
                if (line.Type is ChangeType.Inserted ||
                    line.Type is ChangeType.Deleted ||
                    line.Type is ChangeType.Modified)
                {
                    return true;
                }
            }

            return false;
        }
    }

    public enum UpdateResult
    {
        NotFound,
        Updated,
        Correct,
    }
}
