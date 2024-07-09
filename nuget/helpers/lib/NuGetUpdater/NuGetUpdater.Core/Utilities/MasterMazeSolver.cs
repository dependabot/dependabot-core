using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;

using NuGet.Common;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

using NuGetUpdater.Core;

// Data type to store information of a given package
public class PackageToUpdate
{
    public string packageName { get; set; }
    public string currentVersion { get; set; }
    public string newVersion { get; set; }

    // Second version in case there's a "bounds" on the package version
    public string secondVersion { get; set; }

    // Bool to determine if a package has to be a specific version
    public bool isSpecific { get; set; }
}

public class PackageManager
{
    // What packages a given package depends on
    private Dictionary<PackageToUpdate, HashSet<PackageToUpdate>> packageDependencies = new Dictionary<PackageToUpdate, HashSet<PackageToUpdate>>();

    // What packages depend on a given package
    private Dictionary<PackageToUpdate, HashSet<PackageToUpdate>> reverseDependencies = new Dictionary<PackageToUpdate, HashSet<PackageToUpdate>>();

    // Path of the repository
    private string repoRoot;

    // Path to the project within the repository
    private string projectPath;

    public PackageManager(string repoRoot, string projectPath)
    {
        this.repoRoot = repoRoot;
        this.projectPath = projectPath;
    }

    // Method that converts from string to string[]
     private string[] ParseCommandLineArgs(string commandString)
    {
        List<string> argsList = new List<string>();
        StringBuilder argsBuilder = new StringBuilder();
        bool quotes = false;

        foreach (char c in commandString)
        {
            if (c == '\"')
            {
                quotes = !quotes;
            }
            else if (c == ' ' && !quotes)
            {
                if (argsBuilder.Length > 0)
                {
                    argsList.Add(argsBuilder.ToString());
                    argsBuilder.Clear();
                }
            }
            else
            {
                argsBuilder.Append(c);
            }
        }

        if (argsBuilder.Length > 0)
        {
            argsList.Add(argsBuilder.ToString());
        }

        return argsList.ToArray();
    }

    // Method to get the dependencies of a package
    public async Task<List<PackageToUpdate>> GetDependenciesAsync(PackageToUpdate package, string targetFramework)
    {
        // Lower the characters in the package name to put in the nuspec url
        string packageNameLower = package.packageName.ToLower();
        string nuspecContent = null;

        // Create temporary directory for OutputDirectory
        string tempDirectory = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        Directory.CreateDirectory(tempDirectory);

        // Get the path to the NuGet.Config file
        string configFile = PathHelper.GetFileInDirectoryOrParent(projectPath, repoRoot, "NuGet.Config", caseSensitive: false);

        // Generate config file if none is present
        if (configFile == null)
        {
            configFile = Path.Combine(tempDirectory, "NuGet.Config");
            string configContent = @"<?xml version=""1.0"" encoding=""utf-8""?>
                                <configuration>
                                    <packageSources>
                                        <add key=""nuget.org"" value=""https://api.nuget.org/v3/index.json"" protocolVersion=""3"" />
                                    </packageSources>
                                </configuration>";
            File.WriteAllText(configFile, configContent);
        }

        // Remove any brackets and parantheses from the version, so that you can compare for later use
        if (package.newVersion != null)
        {
            if (package.newVersion.StartsWith("[") && package.newVersion.EndsWith("]"))
            {
                package.newVersion = package.newVersion.Trim('[', ']');
                package.newVersion = package.newVersion.Split(',').FirstOrDefault().Trim();
                package.isSpecific = true;
            }

            // Construct the command to run and run it
            string nugetCommand = $"install {package.packageName} -Version {package.newVersion} -NonInteractive -OutputDirectory \"{tempDirectory}\" -ConfigFile \"{configFile}\" -PackageSaveMode nuspec";
            string[] args = ParseCommandLineArgs(nugetCommand);

            try
            {
                int exitCode = NuGet.CommandLine.Program.Main(args);
                if (exitCode != 0)
                {
                    throw new Exception($"NuGet CLI command failed with exit code {exitCode}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Exception: {ex.Message}");
                throw;
            }

            string nameAndVersion = $"{package.packageName}.{package.newVersion}";
            string nuspecDirectory = Path.Combine(tempDirectory, nameAndVersion);
            string nuspec = Path.Combine(nuspecDirectory, $"{package.packageName}.nuspec");

            try
            {
                if (File.Exists(nuspec))
                {
                    using (var reader = new StreamReader(File.OpenRead(nuspec)))
                    {
                        nuspecContent = reader.ReadToEnd();
                    }
                }
                else
                {
                    Console.WriteLine($"The .nuspec file does not exist at {nuspec}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"An error occurred while extracting the .nuspec file: {ex.Message}");
            }
        }

        else
        {
            if (package.currentVersion.StartsWith("[") && package.currentVersion.EndsWith("]"))
            {
                package.currentVersion = package.currentVersion.Trim('[', ']');
                package.currentVersion = package.currentVersion.Split(',').FirstOrDefault().Trim();
                package.isSpecific = true;
            }

            // Construct the command to run and run it
            string nugetCommand = $"install {package.packageName} -Version {package.currentVersion} -NonInteractive -OutputDirectory \"{tempDirectory}\" -ConfigFile \"{configFile}\" -PackageSaveMode nuspec";

            string[] args = ParseCommandLineArgs(nugetCommand);

            try
            {
                int exitCode = NuGet.CommandLine.Program.Main(args);
                if (exitCode != 0)
                {
                    throw new Exception($"NuGet CLI command failed with exit code {exitCode}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Exception: {ex.Message}");
                throw;
            }

            string nameAndVersion = $"{package.packageName}.{package.currentVersion}";
            string nuspecDirectory = Path.Combine(tempDirectory, nameAndVersion);
            string nuspec = Path.Combine(nuspecDirectory, $"{package.packageName}.nuspec");
            
            try
            {
                if (File.Exists(nuspec))
                {
                    using (var reader = new StreamReader(File.OpenRead(nuspec)))
                    {
                        nuspecContent = reader.ReadToEnd();
                    }
                }
                else
                {
                    Console.WriteLine($"The .nuspec file does not exist at {nuspec}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"An error occurred while extracting the .nuspec file: {ex.Message}");
            }
        }

        List<PackageToUpdate> dependencyList = new List<PackageToUpdate>();

        try
        {
            XDocument nuspecXml = XDocument.Parse(nuspecContent);
            XNamespace ns = "http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd";

            var availableTargetFrameworks = nuspecXml.Descendants(ns + "dependencies")
                                        .Elements(ns + "group")
                                        .Select(g => (string)g.Attribute("targetFramework"))
                                        .Distinct()
                                        .ToList();

            availableTargetFrameworks.Sort((a, b) => -1 * string.Compare(a, b, StringComparison.Ordinal));

            // Find the best match for the user's input framework.
            string bestMatchFramework = availableTargetFrameworks
                .FirstOrDefault(framework => string.Compare(framework, targetFramework, StringComparison.Ordinal) <= 0);

            // If there aren't dependencies compatible with the framework / there aren't dependencies, return null, if not, 
            if (bestMatchFramework == null)
            {
                dependencyList = null;
                return dependencyList;
            }

            var dependencyGroups = nuspecXml.Descendants(ns + "dependencies")
                            .Elements(ns + "group")
                            .Where(g => (string)g.Attribute("targetFramework") == bestMatchFramework);

            bool hasDependencies = dependencyGroups.Any(group => group.Elements(ns + "dependency").Any());

            if (!hasDependencies)
            {
                dependencyList = null;
                return dependencyList;
            }

            // Loop through each group and the depdenencies in each (based on framework)
            foreach (var group in dependencyGroups)
            {
                bool specific = false;
                foreach (var dependency in group.Elements(ns + "dependency"))
                {
                    string version = dependency.Attribute("version").Value;
                    string firstVersion = null;
                    string secondVersion = null;

                    // Conditions to check if the version has bounds specified
                    if (version.StartsWith("[") && version.EndsWith("]"))
                    {
                        version = version.Trim('[', ']');
                        var versions = version.Split(',');
                        version = versions.FirstOrDefault().Trim();
                        if (versions.Length > 1)
                        {
                            secondVersion = versions.LastOrDefault()?.Trim();
                        }
                        specific = true;
                    }
                    else if (version.StartsWith("[") && version.EndsWith(")"))
                    {
                        version = version.Trim('[', ')');
                        var versions = version.Split(',');
                        version = versions.FirstOrDefault().Trim();
                        if (versions.Length > 1)
                        {
                            secondVersion = versions.LastOrDefault()?.Trim();
                        }
                        specific = true;
                    }
                    else if (version.StartsWith("(") && version.EndsWith("]"))
                    {
                        version = version.Trim('(', ']');
                        var versions = version.Split(',');
                        version = versions.FirstOrDefault().Trim();
                        if (versions.Length > 1)
                        {
                            secondVersion = versions.LastOrDefault()?.Trim();
                        }
                        specific = true;
                    }
                    else if (version.StartsWith("(") && version.EndsWith(")"))
                    {
                        version = version.Trim('(', ')');
                        var versions = version.Split(',');
                        version = versions.FirstOrDefault().Trim();
                        if (versions.Length > 1)
                        {
                            secondVersion = versions.LastOrDefault()?.Trim();
                        }
                        specific = true;
                    }

                    PackageToUpdate dependencyPackage = new PackageToUpdate
                    {
                        packageName = dependency.Attribute("id").Value,
                        currentVersion = version,
                    };

                    if (specific == true)
                    {
                        dependencyPackage.isSpecific = true;
                    }

                    if (secondVersion != null)
                    {
                        dependencyPackage.secondVersion = secondVersion;
                    }
                    
                    dependencyList.Add(dependencyPackage);
                }
            }
        }
        catch (FileNotFoundException)
        {
            Console.WriteLine($"The file was not found.");
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            Console.WriteLine($"Unauthorized access to the file.");
            return null;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"An error occurred while reading the file: {ex.Message}");
            return null;
        }

        return dependencyList;
    }

    // Method to AddDependency to create the relationships between a parent and child
    private void AddDependency(PackageToUpdate parent, PackageToUpdate child)
    {
        if (!packageDependencies.ContainsKey(parent))
        {
            packageDependencies[parent] = new HashSet<PackageToUpdate>();
        }
        else if (packageDependencies[parent].Contains(child))
        {
            // Remove the old child dependency if it exists
            packageDependencies[parent].Remove(child);
        }

        packageDependencies[parent].Add(child);

        if (!reverseDependencies.ContainsKey(child))
        {
            reverseDependencies[child] = new HashSet<PackageToUpdate>();
        }
        else if (reverseDependencies[child].Contains(parent))
        {
            // Remove the old parent dependency if it exists
            reverseDependencies[child].Remove(parent);
        }

        reverseDependencies[child].Add(parent);
    }

    // Method to get the dependencies of a package and add them as a dependency
    public async Task PopulatePackageDependenciesAsync(List<PackageToUpdate> packages, string targetFramework)
    {
        // Loop through each package and get their dependencies
        foreach (PackageToUpdate package in packages)
        {
            List<PackageToUpdate> dependencies = await GetDependenciesAsync(package, targetFramework);

            if (dependencies == null)
            {
                continue;
            }

            // Add each dependency based off if it exists or not
            foreach (PackageToUpdate dependency in dependencies)
            {
                PackageToUpdate checkInExisting = packages.FirstOrDefault(p => p.packageName == dependency.packageName);
                if (checkInExisting != null)
                {
                    checkInExisting.isSpecific = dependency.isSpecific;
                    AddDependency(package, checkInExisting);
                }
                else
                {
                    AddDependency(package, dependency);
                }
            }
        }
    }

    // Method to get the parent packages of a given package
    public HashSet<PackageToUpdate> GetParentPackages(PackageToUpdate package)
    {
        if (reverseDependencies.TryGetValue(package, out var parents))
        {
            return parents;
        }

        return new HashSet<PackageToUpdate>();
    }

    // Method to update the version of a desired package based off framwork
    public async Task<string> UpdateVersion(List<PackageToUpdate> existingPackages, PackageToUpdate package, string targetFramework)
    {
        Boolean inExisting = true;
        // Check if there is no new version to update or if the current version isnt updated
        if (package.newVersion == null)
        {
            return "No new version";
        }

        if (package.currentVersion != null)
        {
            if (package.currentVersion == package.newVersion)
            {
                return "Already updated to new version";
            }
        }
        else
        {
            package.currentVersion = package.newVersion;
            inExisting = false ;
        }

        try
        {
            NuGetVersion currentVersion = new NuGetVersion(package.currentVersion);
            NuGetVersion newerVersion = new NuGetVersion(package.newVersion);

            // If the lastest verion is not the same / is greater than the current version, then update it to that
            if (currentVersion <= newerVersion)
            {
                string currentVersiontemp = package.currentVersion;
                package.currentVersion = package.newVersion;

                // Check if the current package has dependencies 
                List<PackageToUpdate> dependencyList = await GetDependenciesAsync(package, targetFramework);

                // If there are dependencies
                if (dependencyList != null)
                {
                    foreach (PackageToUpdate dependency in dependencyList)
                    {
                        // Check if the dependency is in the existing packages. 
                        foreach (PackageToUpdate existingPackage in existingPackages)
                        {
                            // If you find the dependency
                            if (dependency.packageName == existingPackage.packageName)
                            {
                                NuGetVersion existingCurrentVersion = new NuGetVersion(existingPackage.currentVersion);
                                NuGetVersion dependencyCurrentVersion = new NuGetVersion(dependency.currentVersion);

                                // Check if the existing version is less than the dependency's existing version
                                if (existingCurrentVersion <= dependencyCurrentVersion)
                                {
                                    // Create temporary copy of the current version and of the existing package
                                    string dependencyOldVersion = existingPackage.currentVersion;
                                    PackageToUpdate packageDupe = existingPackage;
                                    packageDupe.currentVersion = dependency.currentVersion;

                                    // If the family is compatible with the dependency's version, update with the dependency version
                                    if (await AreAllParentsCompatibleAsync(existingPackages, packageDupe, targetFramework) == true)
                                    {
                                        existingPackage.currentVersion = dependencyOldVersion;
                                        string newVersion = dependency.currentVersion;
                                        existingPackage.newVersion = dependency.currentVersion;
                                        await UpdateVersion(existingPackages, existingPackage, targetFramework);
                                    }
                                    // If not, resort to putting version back to normal and remove new version
                                    else
                                    {
                                        existingPackage.currentVersion = dependencyOldVersion;
                                        package.currentVersion = currentVersiontemp;
                                        package.newVersion = package.currentVersion;
                                        return "UNSOLVEABLE";
                                    }
                                }
                            }
                        }

                        // If the dependency has brackets or paranthesis, it's a specific version
                        if (dependency.currentVersion.Contains('[') || dependency.currentVersion.Contains(']') || dependency.currentVersion.Contains('{') || dependency.currentVersion.Contains('}'))
                        {
                            dependency.isSpecific = true;
                        }

                        await UpdateVersion(existingPackages, dependency, targetFramework);
                    }
                }

                // Get the parent packages of the package and check the compatibility between its family
                HashSet<PackageToUpdate> parentPackages = GetParentPackages(package);

                foreach (PackageToUpdate parent in parentPackages)
                {
                    bool familyCompatible = await AreAllParentsCompatibleAsync(existingPackages, parent, targetFramework);
                    bool isCompatible = await IsCompatibleAsync(existingPackages, parent, package, targetFramework);

                    // If it's not compatible
                    if (!isCompatible)
                    {
                        // Attempt to find and update to a compatible version
                        NuGetVersion compatibleVersion = await FindCompatibleVersionAsync(existingPackages, parent, package, targetFramework);
                        if (compatibleVersion == null)
                        {
                            return "FAILED to update";
                        }

                        parent.newVersion = compatibleVersion.ToString();
                        await UpdateVersion(existingPackages, parent, targetFramework);
                    }

                    // If it's compatible and the package you updated wasn't in the existing package, check if the parent's dependencies version is the same as the current
                    else if (isCompatible == true && inExisting == false && parent.isSpecific != true)
                    {
                        List<PackageToUpdate> dependencyListParent = await GetDependenciesAsync(parent, targetFramework);
                        PackageToUpdate parentDependency = dependencyListParent.FirstOrDefault(p => p.packageName == package.packageName);
                        if (parentDependency.currentVersion != package.currentVersion)
                        {
                            //update parent to next version that has this version
                            // if it doesnt have it, then you can add the package in the existing list
                            // Get the latest version as a limit
                            SourceRepository repo = Repository.Factory.GetCoreV3("https://api.nuget.org/v3/index.json");
                            FindPackageByIdResource resource = await repo.GetResourceAsync<FindPackageByIdResource>();

                            // Find the latest version of the package
                            IEnumerable<NuGetVersion> versions = await resource.GetAllVersionsAsync(
                                parent.packageName, new SourceCacheContext(), NullLogger.Instance, CancellationToken.None);
                            NuGetVersion latestVersion = versions.Where(v => !v.IsPrerelease).Max();

                            string currentVersionString = parent.currentVersion;
                            NuGetVersion currentVersionParent = NuGetVersion.Parse(currentVersionString);

                            // Loop from the current version to the latest version, use next patch as a limit (unless theres a limit) so it doesn't look for versions that don't exist
                            for (NuGetVersion version = currentVersionParent; version <= latestVersion; version = NextPatch(version, versions))
                            {
                                NuGetVersion nextPatch = NextPatch(version, versions);
                                if(nextPatch == version)
                                {
                                    return "Success";
                                }
                                string parentVersion = version.ToString();
                                PackageToUpdate parentTemp = parent;
                                parentTemp.currentVersion = parentVersion;

                                List<PackageToUpdate> dependencyListParentTemp = await GetDependenciesAsync(parentTemp, targetFramework);
                                PackageToUpdate parentDependencyTemp = dependencyListParentTemp.FirstOrDefault(p => p.packageName == package.packageName);
                                if ((parentDependencyTemp.currentVersion == package.currentVersion) && (parent.isSpecific != true))
                                {
                                    parent.newVersion = parentVersion;
                                    await UpdateVersion(existingPackages, parent, targetFramework);
                                    package.isSpecific = true;
                                    return "Success";
                                }
                            }
                            parent.currentVersion = currentVersionString;
                        }
                    }
                }
            }
                    
            else
            {
                Console.WriteLine("Current version >= latest version");
            }
        }
        catch (Exception ex)
        {
            return "FAILED to update";
        }

        return "Success";
    }

    // Method to determine if a parent and child are compatible with their versions
    public async Task<bool> IsCompatibleAsync(List<PackageToUpdate> existingPackages, PackageToUpdate parent, PackageToUpdate child, string targetFramework)
    {
        List<PackageToUpdate> dependencies = await GetDependenciesAsync(parent, targetFramework);

        foreach (PackageToUpdate dependency in dependencies)
        {
            if (dependency.packageName == child.packageName)
            {
                NuGetVersion dependencyVersion = new NuGetVersion(dependency.currentVersion);
                NuGetVersion childVersion = new NuGetVersion(child.currentVersion);

                if (dependencyVersion == childVersion || (childVersion > dependencyVersion && dependency.isSpecific != true))
                {
                    return true;
                }
                else
                {
                    return false;
                }
            }
        }

        return false;
    }

    // Method to update a version to the next available version for a package
    public NuGetVersion NextPatch(NuGetVersion version, IEnumerable<NuGetVersion> allVersions)
    {
        NuGetVersion nextPatchVersion = new NuGetVersion(version.Major, version.Minor, version.Patch + 1);

        if (allVersions.Contains(nextPatchVersion))
        {
            return nextPatchVersion;
        }

        NuGetVersion nextMinorVersion = new NuGetVersion(version.Major, version.Minor + 1, 0);

        if (allVersions.Any(v => v.Major == nextMinorVersion.Major && v.Minor == nextMinorVersion.Minor))
        {
            return nextMinorVersion;
        }

        NuGetVersion nextMajorVersion = new NuGetVersion(version.Major + 1, 0, 0);

        if (allVersions.Any(v => v.Major == nextMajorVersion.Major))
        {
            return nextMajorVersion;
        }

        // If no next version found, return the current version (or handle it accordingly)
        return version;
    }

    // Method to find a compatible version with the child for the parent to update to
    public async Task<NuGetVersion> FindCompatibleVersionAsync(List<PackageToUpdate> existingPackages, PackageToUpdate possibleParent, PackageToUpdate possibleDependency, string targetFramework)
    {
        string packageId = possibleParent.packageName;
        string currentVersionString = possibleParent.currentVersion;
        NuGetVersion currentVersion = NuGetVersion.Parse(currentVersionString);

        // Get the latest version as a limit
        SourceRepository repo = Repository.Factory.GetCoreV3("https://api.nuget.org/v3/index.json");
         FindPackageByIdResource resource = await repo.GetResourceAsync<FindPackageByIdResource>();

        // Find the latest version of the package
        IEnumerable<NuGetVersion> versions = await resource.GetAllVersionsAsync(
            packageId, new SourceCacheContext(), NullLogger.Instance, CancellationToken.None);
        NuGetVersion latestVersion = versions.Where(v => !v.IsPrerelease).Max();

        // If there's a version bounds that the parent has 
        if (possibleParent.secondVersion != null)
        {
            NuGetVersion secondVersion = NuGetVersion.Parse(possibleParent.secondVersion);
            latestVersion = secondVersion;
        }

        // If there is no later version
        if (currentVersion == latestVersion)
        {
            return null;
        }

        // Loop from the current version to the latest version, use next patch as a limit (unless theres a limit) so it doesn't look for versions that don't exist
        for (NuGetVersion version = currentVersion; version <= latestVersion; version = NextPatch(version, versions))
        {
            possibleParent.newVersion = version.ToString();

            // Check if there's compatibility with parent and depdendency
            if (await IsCompatibleAsync(existingPackages, possibleParent, possibleDependency, targetFramework))
            {
                // Check if parents are compatible, recursively
                if (await AreAllParentsCompatibleAsync(existingPackages, possibleParent, targetFramework))
                {
                    // If compatible, return the new version
                    if (Regex.IsMatch(possibleParent.newVersion, @"[a-zA-Z]"))
                    {
                        possibleParent.isSpecific = true;
                    }
                    return version;
                }
            }
        }

        // If no compatible version is found, return null
        return null;
    }

    // Method to determine if all the parents of a given package are compatible with the parent's desired version
    public async Task<bool> AreAllParentsCompatibleAsync(List<PackageToUpdate> existingPackages, PackageToUpdate possibleParent, string targetFramework)
    {
        // Get the parents packages and loop through them
        HashSet<PackageToUpdate> parentPackages = GetParentPackages(possibleParent);

        foreach (PackageToUpdate parent in parentPackages)
        {
            bool isCompatible = await IsCompatibleAsync(existingPackages, parent, possibleParent, targetFramework);

            // If the package and parent are not compatible
            if (!isCompatible)
            {
                // Find a compatible version if possible
                NuGetVersion compatibleVersion = await FindCompatibleVersionAsync(existingPackages, parent, possibleParent, targetFramework);
                if (compatibleVersion == null)
                {
                    return false;
                }

                parent.newVersion = compatibleVersion.ToString();
                await UpdateVersion(existingPackages, parent, targetFramework);
            }

            // Recursively check if all ancestors are compatible
            if (!await AreAllParentsCompatibleAsync(existingPackages, parent, targetFramework))
            {
                return false;
            }
        }

        return true;
    }

    // Method to update the existing packages with new version of the desired packages to update
    public void UpdateExistingPackagesWithNewVersions(List<PackageToUpdate> existingPackages, List<PackageToUpdate> packagesToUpdate)
    {
        foreach (PackageToUpdate packageToUpdate in packagesToUpdate)
        {
            PackageToUpdate existingPackage = existingPackages.FirstOrDefault(p => p.packageName == packageToUpdate.packageName);

            if (existingPackage != null)
            {
                existingPackage.newVersion = packageToUpdate.newVersion;
            }
            else
            {
                Console.WriteLine($"Package {packageToUpdate.packageName} not found in existing packages.");
            }
        }
    }

}
