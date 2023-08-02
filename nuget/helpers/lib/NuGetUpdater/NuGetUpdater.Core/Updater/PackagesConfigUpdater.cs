using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;

using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

internal static class PackagesConfigUpdater
{
    internal const string PackagesConfigFileName = "packages.config";

    public static bool HasProjectConfigFile(string projectPath)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath);
        var packagesConfigPath = PathHelper.JoinPath(projectDirectory, PackagesConfigFileName);
        return File.Exists(packagesConfigPath);
    }

    public static async Task UpdateDependencyAsync(string projectPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive, Logger logger)
    {
        logger.Log($"  Found {PackagesConfigFileName}; running with NuGet.exe");

        // use NuGet.exe to perform update

        // ensure local packages directory exists
        var projectFileContents = await File.ReadAllTextAsync(projectPath);
        var packagesSubDirectory = GetPathToPackagesDirectory(projectFileContents, dependencyName, previousDependencyVersion);
        if (packagesSubDirectory is null)
        {
            logger.Log($"    Project [{projectPath}] does not reference this dependency.");
            return;
        }

        logger.Log($"    Using packages directory [{packagesSubDirectory}] for project [{projectPath}].");

        var projectDirectory = Path.GetDirectoryName(projectPath);
        var packagesConfigPath = PathHelper.JoinPath(projectDirectory, PackagesConfigFileName);

        var packagesDirectory = PathHelper.JoinPath(projectDirectory, packagesSubDirectory);
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

        logger.Log("    Finding MSBuild...");
        var msbuildDirectory = MSBuildHelper.MSBuildPath;
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
            logger.Log($"    Running NuGet.exe with args: {string.Join(" ", args)}");

            Environment.CurrentDirectory = packagesDirectory;
            var result = NuGet.CommandLine.Program.Main(args.ToArray());
            var fullOutput = outputBuilder.ToString();
            logger.Log($"    Result: {result}");
            logger.Log($"    Output:\n{fullOutput}");
            if (result != 0)
            {
                throw new Exception(fullOutput);
            }
        }
        catch (Exception e)
        {
            logger.Log($"Error: {e}");
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

        logger.Log("    Writing project file back to disk");
        await File.WriteAllTextAsync(projectPath, normalizedProjectFileContents);
    }

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
}