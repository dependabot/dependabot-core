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
    public static async Task UpdateDependencyAsync(string repoRootPath, string projectPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive, Logger logger)
    {
        logger.Log($"  Found {NuGetHelper.PackagesConfigFileName}; running with NuGet.exe");

        // use NuGet.exe to perform update

        // ensure local packages directory exists
        var projectBuildFile = ProjectBuildFile.Open(repoRootPath, projectPath);
        var packagesSubDirectory = GetPathToPackagesDirectory(projectBuildFile, dependencyName, previousDependencyVersion);
        if (packagesSubDirectory is null)
        {
            logger.Log($"    Project [{projectPath}] does not reference this dependency.");
            return;
        }

        logger.Log($"    Using packages directory [{packagesSubDirectory}] for project [{projectPath}].");

        var projectDirectory = Path.GetDirectoryName(projectPath);
        var packagesConfigPath = PathHelper.JoinPath(projectDirectory, NuGetHelper.PackagesConfigFileName);

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

        RunNuget(args, packagesDirectory, logger);

        projectBuildFile = ProjectBuildFile.Open(repoRootPath, projectPath);
        projectBuildFile.NormalizeDirectorySeparatorsInProject();

        // Update binding redirects
        await BindingRedirectManager.UpdateBindingRedirectsAsync(projectBuildFile);

        logger.Log("    Writing project file back to disk");
        await projectBuildFile.SaveAsync();
    }

    private static void RunNuget(List<string> args, string packagesDirectory, Logger logger)
    {
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
    }

    internal static string? GetPathToPackagesDirectory(ProjectBuildFile projectBuildFile, string dependencyName, string dependencyVersion)
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

        var hintPathNodes = projectBuildFile.Contents.Descendants()
            .Where(e =>
                e.Name.Equals("HintPath", StringComparison.OrdinalIgnoreCase) &&
                e.Parent.Name.Equals("Reference", StringComparison.OrdinalIgnoreCase) &&
                e.Parent.GetAttributeValue("Include", StringComparison.OrdinalIgnoreCase)?.StartsWith($"{dependencyName},", StringComparison.OrdinalIgnoreCase) == true);
        foreach (var hintPathNode in hintPathNodes)
        {
            var hintPath = hintPathNode.GetContentValue();
            var hintPathSubStringLocation = hintPath.IndexOf(hintPathSubString);
            if (hintPathSubStringLocation >= 0)
            {
                var subpath = hintPath[..hintPathSubStringLocation];
                if (subpath.EndsWith("/") || subpath.EndsWith("\\"))
                {
                    subpath = subpath[..^1];
                }

                return subpath;
            }
        }

        return null;
    }
}
