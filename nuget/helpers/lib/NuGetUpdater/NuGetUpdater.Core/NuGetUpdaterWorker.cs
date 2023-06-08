using System;
using System.Collections.Generic;
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

    public async Task RunAsync(string filePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion)
    {
        var extension = Path.GetExtension(filePath).ToLowerInvariant();
        switch (extension)
        {
            case ".sln":
                await RunForSolutionAsync(filePath, dependencyName, previousDependencyVersion, newDependencyVersion);
                break;
            case ".proj":
                await RunForProjFileAsync(filePath, dependencyName, previousDependencyVersion, newDependencyVersion);
                break;
            case ".csproj":
            case ".fsproj":
            case ".vbproj":
                await RunForProjectAsync(filePath, dependencyName, previousDependencyVersion, newDependencyVersion);
                break;
        }
    }

    private async Task RunForSolutionAsync(string solutionPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion)
    {
        Log($"Running for solution [{solutionPath}]");
        var solutionDirectory = Path.GetDirectoryName(solutionPath);
        var solutionContent = await File.ReadAllTextAsync(solutionPath);
        var projectSubPaths = GetProjectSubPathsFromSolution(solutionContent);
        foreach (var projectSubPath in projectSubPaths)
        {
            var projectFullPath = JoinPath(solutionDirectory, projectSubPath);
            await RunForProjectAsync(projectFullPath, dependencyName, previousDependencyVersion, newDependencyVersion);
        }
    }

    private async Task RunForProjFileAsync(string projFilePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion)
    {
        Log($"Running for proj file [{projFilePath}]");
        var projectFilePaths = MSBuildHelper.GetAllProjectPaths(projFilePath);
        foreach (var projectFullPath in projectFilePaths)
        {
            // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
            if (File.Exists(projectFullPath))
            {
                await RunForProjectAsync(projectFullPath, dependencyName, previousDependencyVersion, newDependencyVersion);
            }
        }
    }

    private async Task RunForProjectAsync(string projectPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion)
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
            var updatedProjectFileContents = UpdateProjectReference(projectFileContents, dependencyName, previousDependencyVersion, newDependencyVersion);
            if (HasAnyNonWhitespaceChanges(projectFileContents, updatedProjectFileContents))
            {
                await File.WriteAllTextAsync(projectPath, updatedProjectFileContents);
            }
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

    private static string UpdateProjectReference(string content, string dependencyName, string previousDependencyVersion, string newDependencyVersion)
    {
        var originalXml = Parser.ParseText(content);
        var packageReferenceNode = originalXml.Descendants().SingleOrDefault(e =>
            e.Name == "PackageReference" &&
            e.GetAttributeValue("Include") == dependencyName &&
            e.GetAttributeValue("Version") == previousDependencyVersion);
        if (packageReferenceNode is null)
        {
            // no change
            return content;
        }

        var packageReferenceVersionAttribute = packageReferenceNode.GetAttribute("Version");
        var updatedPackageReferenceVersionAttribute = packageReferenceVersionAttribute.WithValue(newDependencyVersion);
        var updatedXml = originalXml.ReplaceNode(packageReferenceVersionAttribute, updatedPackageReferenceVersionAttribute);
        var updatedContent = updatedXml.ToFullString();
        return updatedContent;
    }
}
