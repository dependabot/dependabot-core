using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using System.Xml.XPath;

using Microsoft.Language.Xml;

using NuGet.CommandLine;

using NuGetUpdater.Core.Updater;

using Console = System.Console;

namespace NuGetUpdater.Core;

/// <summary>
/// Handles package updates for projects that use packages.config.
/// </summary>
/// <remarks>
/// packages.config can appear in non-SDK-style projects, but not in SDK-style projects.
/// See: https://learn.microsoft.com/en-us/nuget/reference/packages-config
///      https://learn.microsoft.com/en-us/nuget/resources/check-project-format
/// <remarks>
internal static class PackagesConfigUpdater
{
    public static async Task UpdateDependencyAsync(
        string repoRootPath,
        string projectPath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        string packagesConfigPath,
        ILogger logger
    )
    {
        // packages.config project; use NuGet.exe to perform update
        logger.Log($"  Found '{NuGetHelper.PackagesConfigFileName}' project; running NuGet.exe update");

        // ensure local packages directory exists
        var projectBuildFile = ProjectBuildFile.Open(repoRootPath, projectPath);
        var packagesSubDirectory = GetPathToPackagesDirectory(projectBuildFile, dependencyName, previousDependencyVersion, packagesConfigPath);
        if (packagesSubDirectory is null)
        {
            logger.Log($"    Project [{projectPath}] does not reference this dependency.");
            return;
        }

        logger.Log($"    Using packages directory [{packagesSubDirectory}] for project [{projectPath}].");

        var projectDirectory = Path.GetDirectoryName(projectPath);
        var packagesDirectory = PathHelper.JoinPath(projectDirectory, packagesSubDirectory);
        Directory.CreateDirectory(packagesDirectory);

        var updateArgs = new List<string>
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

        var restoreArgs = new List<string>
        {
            "restore",
            projectPath,
            "-PackagesDirectory",
            packagesDirectory,
            "-NonInteractive",
        };

        logger.Log("    Finding MSBuild...");
        var msbuildDirectory = MSBuildHelper.MSBuildPath;
        if (msbuildDirectory is not null)
        {
            foreach (var args in new[] { updateArgs, restoreArgs })
            {
                args.Add("-MSBuildPath");
                args.Add(msbuildDirectory); // e.g., /usr/share/dotnet/sdk/7.0.203
            }
        }

        using (new WebApplicationTargetsConditionPatcher(projectPath))
        {
            RunNugetUpdate(updateArgs, restoreArgs, projectDirectory ?? packagesDirectory, logger);
        }

        projectBuildFile = ProjectBuildFile.Open(repoRootPath, projectPath);
        projectBuildFile.NormalizeDirectorySeparatorsInProject();

        // Update binding redirects
        await BindingRedirectManager.UpdateBindingRedirectsAsync(projectBuildFile, dependencyName, newDependencyVersion);

        logger.Log("    Writing project file back to disk");
        await projectBuildFile.SaveAsync();
    }

    private static void RunNugetUpdate(List<string> updateArgs, List<string> restoreArgs, string projectDirectory, ILogger logger)
    {
        var outputBuilder = new StringBuilder();
        var writer = new StringWriter(outputBuilder);

        var originalOut = Console.Out;
        var originalError = Console.Error;
        Console.SetOut(writer);
        Console.SetError(writer);

        var currentDir = Environment.CurrentDirectory;
        var existingSpawnedProcesses = GetLikelyNuGetSpawnedProcesses();
        try
        {
            Environment.CurrentDirectory = projectDirectory;
            var retryingAfterRestore = false;

        doRestore:
            logger.Log($"    Running NuGet.exe with args: {string.Join(" ", updateArgs)}");
            outputBuilder.Clear();
            var result = Program.Main(updateArgs.ToArray());
            var fullOutput = outputBuilder.ToString();
            logger.Log($"    Result: {result}");
            logger.Log($"    Output:\n{fullOutput}");
            if (result != 0)
            {
                // The initial `update` command can fail for several reasons:
                // 1. One possibility is that the `packages.config` file contains a delisted package.  If that's the
                //    case, `update` will fail with the message "Existing packages must be restored before performing
                //    an install or update."
                // 2. Another possibility is that the `update` command fails because the package contains no assemblies
                //    and doesn't appear in the cache.  The message in this case will be "Could not install package
                //    '<name> <version>'...the package does not contain any assembly references or content files that
                //    are compatible with that framework.".
                // 3. Yet another possibility is that the project explicitly imports a targets file without a condition
                //    of `Exists(...)`.
                // The solution in all cases is to run `restore` then try the update again.
                if (!retryingAfterRestore && OutputIndicatesRestoreIsRequired(fullOutput))
                {
                    retryingAfterRestore = true;
                    logger.Log($"    Running NuGet.exe with args: {string.Join(" ", restoreArgs)}");
                    outputBuilder.Clear();
                    var exitCodeAgain = Program.Main(restoreArgs.ToArray());
                    var restoreOutput = outputBuilder.ToString();

                    if (exitCodeAgain != 0)
                    {
                        MSBuildHelper.ThrowOnMissingFile(fullOutput);
                        MSBuildHelper.ThrowOnMissingFile(restoreOutput);
                        MSBuildHelper.ThrowOnMissingPackages(restoreOutput);
                        throw new Exception($"Unable to restore.\nOutput:\n${restoreOutput}\n");
                    }

                    goto doRestore;
                }

                MSBuildHelper.ThrowOnUnauthenticatedFeed(fullOutput);
                MSBuildHelper.ThrowOnMissingFile(fullOutput);
                MSBuildHelper.ThrowOnMissingPackages(fullOutput);
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

            // NuGet.exe can spawn processes that hold on to the temporary directory, so we need to kill them
            var currentSpawnedProcesses = GetLikelyNuGetSpawnedProcesses();
            var deltaSpawnedProcesses = currentSpawnedProcesses.Except(existingSpawnedProcesses).ToArray();
            foreach (var credProvider in deltaSpawnedProcesses)
            {
                logger.Log($"Ending spawned credential provider process");
                credProvider.Kill();
            }
        }
    }

    private static bool OutputIndicatesRestoreIsRequired(string output)
    {
        return output.Contains("Existing packages must be restored before performing an install or update.")
            || output.Contains("the package does not contain any assembly references or content files that are compatible with that framework.")
            || MSBuildHelper.GetMissingFile(output) is not null;
    }

    private static Process[] GetLikelyNuGetSpawnedProcesses()
    {
        var processes = Process.GetProcesses().Where(p => p.ProcessName.StartsWith("CredentialProvider", StringComparison.OrdinalIgnoreCase) == true).ToArray();
        return processes;
    }

    internal static string? GetPathToPackagesDirectory(ProjectBuildFile projectBuildFile, string dependencyName, string dependencyVersion, string? packagesConfigPath)
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
        //
        // first try to do an exact match with the provided version number, but optionally fall back to just matching the package name and _any_ version
        var hintPathSubString = $"{dependencyName}.{dependencyVersion}";

        string? partialPathMatch = null;
        var specificHintPathNodes = projectBuildFile.Contents.Descendants().Where(e => e.IsHintPathNodeForDependency(dependencyName)).ToArray();
        foreach (var hintPathNode in specificHintPathNodes)
        {
            var hintPath = hintPathNode.GetContentValue();
            var hintPathSubStringLocation = hintPath.IndexOf(hintPathSubString, StringComparison.OrdinalIgnoreCase);
            if (hintPathSubStringLocation >= 0)
            {
                // exact match was found, use it
                var subpath = GetUpToIndexWithoutTrailingDirectorySeparator(hintPath, hintPathSubStringLocation);
                return subpath.NormalizePathToUnix();
            }

            if (partialPathMatch is null)
            {
                var partialHintPathSubStringLocation = hintPath.IndexOf($"{dependencyName}.", StringComparison.OrdinalIgnoreCase);
                if (partialHintPathSubStringLocation >= 0)
                {
                    // look instead for, e.g., "Newtonsoft.Json.<digit>"
                    var candidateVersionLocation = partialHintPathSubStringLocation + dependencyName.Length + 1; // 1 is the dot
                    if (hintPath.Length > candidateVersionLocation && char.IsDigit(hintPath[candidateVersionLocation]))
                    {
                        // partial match was found, save it in case we don't find anything better
                        var subpath = GetUpToIndexWithoutTrailingDirectorySeparator(hintPath, partialHintPathSubStringLocation);
                        partialPathMatch = subpath;
                    }
                }
            }
        }

        if (partialPathMatch is null && packagesConfigPath is not null)
        {
            // if we got this far, we couldn't find the packages directory for the specified dependency and there are 2 possibilities:
            // 1. the dependency doesn't actually exist in this project
            // 2. the dependency exists, but doesn't have any assemblies, e.g., jQuery

            // first let's check the packages.config file to see if we actually need it.
            XDocument packagesDocument = XDocument.Load(packagesConfigPath);
            var hasPackage = packagesDocument.XPathSelectElements("/packages/package")
                .Where(e => e.Attribute("id")?.Value.Equals(dependencyName, StringComparison.OrdinalIgnoreCase) == true).Any();
            if (hasPackage)
            {
                // the dependency exists in the packages.config file, so it must be the second case
                // at this point there's no perfect way to determine what the packages path is, but there's a really good chance that
                // for any given package it looks something like this:
                //   ..\..\packages\Package.Name.[version]\lib\Tfm\Package.Name.dll
                var genericHintPathNodes = projectBuildFile.Contents.Descendants().Where(IsHintPathNode).ToArray();
                if (genericHintPathNodes.Length > 0)
                {
                    foreach (var hintPathNode in genericHintPathNodes)
                    {
                        var hintPath = hintPathNode.GetContentValue();
                        var match = Regex.Match(hintPath, @"^(?<PackagesPath>.*)[/\\](?<PackageNameAndVersion>[^/\\]+)[/\\]lib[/\\](?<Tfm>[^/\\]+)[/\\](?<AssemblyName>[^/\\]+)$");
                        // e.g.,                              ..\..\packages     \    Some.Package.1.2.3              \    lib\     net45          \   Some.Package.dll
                        if (match.Success)
                        {
                            partialPathMatch = match.Groups["PackagesPath"].Value;
                            break;
                        }
                    }
                }
                else
                {
                    // we know the dependency is used, but we have absolutely no idea where the packages path is, so we'll default to something reasonable
                    partialPathMatch = "../packages";
                }
            }
        }

        return partialPathMatch?.NormalizePathToUnix();
    }

    private static bool IsHintPathNode(this IXmlElementSyntax element)
    {
        if (element.Name.Equals("HintPath", StringComparison.OrdinalIgnoreCase) &&
            element.Parent.Name.Equals("Reference", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return false;
    }

    private static bool IsHintPathNodeForDependency(this IXmlElementSyntax element, string dependencyName)
    {
        if (element.IsHintPathNode())
        {
            // the include attribute will look like one of the following:
            //   <Reference Include="Some.Dependency, Version=1.0.0.0, Culture=neutral, PublicKeyToken=abcd">
            // or
            //   <Reference Include="Some.Dependency">
            string includeAttributeValue = element.Parent.GetAttributeValue("Include", StringComparison.OrdinalIgnoreCase);
            if (includeAttributeValue.Equals(dependencyName, StringComparison.OrdinalIgnoreCase) ||
                includeAttributeValue.StartsWith($"{dependencyName},", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static string GetUpToIndexWithoutTrailingDirectorySeparator(string path, int index)
    {
        var subpath = path[..index];
        if (subpath.EndsWith('/') || subpath.EndsWith('\\'))
        {
            subpath = subpath[..^1];
        }

        return subpath;
    }
}
