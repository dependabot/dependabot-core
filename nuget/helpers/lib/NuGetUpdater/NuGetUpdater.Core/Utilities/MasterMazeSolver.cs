using System.Collections.Immutable;
using System.Text;
using System.Text.RegularExpressions;

using NuGet.Common;
using NuGet.Configuration;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;
using NuGet.Frameworks;
using NuGetUpdater.Core.Analyze;
using Microsoft.Build.Utilities;
using System.Threading;
using Task = System.Threading.Tasks.Task;

// Data type to store information of a given package

namespace NuGetUpdater.Core;
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

    // Method alterted from VersionFinder.cs to find the metadata of a given package
    private async Task<IPackageSearchMetadata?> FindPackageMetadataAsync(PackageIdentity packageIdentity, CancellationToken cancellationToken)
    {
        string? currentDirectory = null;
        string CurrentDirectory = currentDirectory ?? Environment.CurrentDirectory;
        SourceCacheContext SourceCacheContext = new SourceCacheContext();
        PackageDownloadContext PackageDownloadContext = new PackageDownloadContext(SourceCacheContext);
         ILogger Logger = NullLogger.Instance;

        IMachineWideSettings MachineWideSettings = new NuGet.CommandLine.CommandLineMachineWideSettings();
        ISettings Settings = NuGet.Configuration.Settings.LoadDefaultSettings(
            CurrentDirectory,
            configFileName: null,
            MachineWideSettings);

        var globalPackagesFolder = SettingsUtility.GetGlobalPackagesFolder(Settings);
        var sourceMapping = PackageSourceMapping.GetPackageSourceMapping(Settings);
        var packageSources = sourceMapping.GetConfiguredPackageSources(packageIdentity.Id).ToHashSet();
        var sourceProvider = new PackageSourceProvider(Settings);
       
       ImmutableArray<PackageSource> PackageSources = sourceProvider.LoadPackageSources()
            .Where(p => p.IsEnabled)
            .ToImmutableArray();
        
        var sources = packageSources.Count == 0
            ? PackageSources
            : PackageSources
                .Where(p => packageSources.Contains(p.Name))
                .ToImmutableArray();

        var message = new StringBuilder();
        message.AppendLine($"finding info url for {packageIdentity}, using package sources: {string.Join(", ", sources.Select(s => s.Name))}");

        foreach (var source in sources)
        {
            message.AppendLine($"  checking {source.Name}");
            var sourceRepository = Repository.Factory.GetCoreV3(source);
            var feed = await sourceRepository.GetResourceAsync<MetadataResource>(cancellationToken);
            if (feed is null)
            {
                message.AppendLine($"    feed for {source.Name} was null");
                continue;
            }

            var existsInFeed = await feed.Exists(
                packageIdentity,
                includeUnlisted: false,
                SourceCacheContext,
                NullLogger.Instance,
                cancellationToken);
            if (!existsInFeed)
            {
                message.AppendLine($"    package {packageIdentity} does not exist in {source.Name}");
                continue;
            }

            var metadataResource = await sourceRepository.GetResourceAsync<PackageMetadataResource>(cancellationToken);
            var metadata = await metadataResource.GetMetadataAsync(packageIdentity, SourceCacheContext, Logger, cancellationToken);
            return metadata;
        }

        return null;
    }

    // Method to find the best match framework of a given package's target framework availability
    public static NuGetFramework FindBestMatchFramework(IEnumerable<NuGet.Packaging.PackageDependencyGroup> dependencySet, string targetFrameworkString)
    {
        // Parse the given target framework string into a NuGetFramework object
        var targetFramework = NuGetFramework.ParseFolder(targetFrameworkString);
        var frameworkReducer = new FrameworkReducer();

        // Collect all target frameworks from the dependency set
        var availableFrameworks = dependencySet.Select(dg => dg.TargetFramework).ToList();

        // Return bestmatch framework
        return frameworkReducer.GetNearest(targetFramework, availableFrameworks);
    }

    // Method to get the dependencies of a package
    public async Task<List<PackageToUpdate>> GetDependenciesAsync(PackageToUpdate package, string targetFramework)
    {
        // Create a package identity to use for obtaining the metadata url
        PackageIdentity packageIdentity = new PackageIdentity(package.packageName, new NuGetVersion(package.newVersion ?? package.currentVersion));
        bool specific = false;

        List<PackageToUpdate> dependencyList = new List<PackageToUpdate>();

        try
        {
            // Fetch package metadata URL
            var metadataUrl = await FindPackageMetadataAsync(packageIdentity, CancellationToken.None);
            string nuspecContent = null;
            IEnumerable<NuGet.Packaging.PackageDependencyGroup> dependencySet = metadataUrl.DependencySets;

            var bestMatchFramework = FindBestMatchFramework(dependencySet, targetFramework);

            if (bestMatchFramework != null)
            {
                // Process the best match framework
                var bestMatchGroup = dependencySet.First(dg => dg.TargetFramework == bestMatchFramework);

                foreach (var packageDependency in bestMatchGroup.Packages)
                {
                    string version = packageDependency.VersionRange.OriginalString;
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
                    }

                    PackageToUpdate dependencyPackage = new PackageToUpdate
                    {
                        packageName = packageDependency.Id,
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
            else
            {
                Console.WriteLine("No compatible framework found.");
            }
        }
        catch (HttpRequestException ex)
        {
            Console.WriteLine($"HTTP error occurred: {ex.Message}");
        }
        catch (ArgumentNullException ex)
        {
            Console.WriteLine($"Argument is null error: {ex.ParamName}, {ex.Message}");
        }
        catch (InvalidOperationException ex)
        {
            Console.WriteLine($"Invalid operation exception: {ex.Message}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"An error occurred: {ex.Message}");
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
        bool inExisting = true;
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

                        // If the parent's dependency current version is not the same as the current version of the package
                        if (parentDependency.currentVersion != package.currentVersion)
                        {
                            // Create a NugetContext instance to get the latest versions of the parent
                            NuGetContext nugetContext = new NuGetContext(Path.GetDirectoryName(projectPath));
                            Logger logger = null;

                            string currentVersionString = parent.currentVersion;
                            NuGetVersion currentVersionParent = NuGetVersion.Parse(currentVersionString);

                            var result = await VersionFinder.GetVersionsAsync(parent.packageName, currentVersionParent,  nugetContext, logger, CancellationToken.None);
                            var versions = result.GetVersions();
                            NuGetVersion latestVersion = versions.Where(v => !v.IsPrerelease).Max();

                            // Loop from the current version to the latest version, use next patch as a limit (unless theres a limit) so it doesn't look for versions that don't exist
                            for (NuGetVersion version = currentVersionParent; version <= latestVersion; version = NextPatch(version, versions))
                            {
                                NuGetVersion nextPatch = NextPatch(version, versions);

                                // If the next patch is the same as the currentVersioon, then nothing is needed
                                if(nextPatch == version)
                                {
                                    return "Success";
                                }

                                string parentVersion = version.ToString();
                                PackageToUpdate parentTemp = parent;
                                parentTemp.currentVersion = parentVersion;

                                // Check if the parent needs to be updated (since the child isn't in existing and the parent can update to remove the child)
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

        // Create a NugetContext instance to get the latest versions of the parent
        NuGetContext nugetContext = new NuGetContext(Path.GetDirectoryName(projectPath));
        Logger logger = null;

        var result = await VersionFinder.GetVersionsAsync(possibleParent.packageName, currentVersion, nugetContext, logger, CancellationToken.None);
        var versions = result.GetVersions();
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
