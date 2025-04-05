using System.Collections.Immutable;
using System.Text;
using System.Text.RegularExpressions;

using NuGet.Common;
using NuGet.Configuration;
using NuGet.Frameworks;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;

using Task = System.Threading.Tasks.Task;

namespace NuGetUpdater.Core;

// Data type to store information of a given package
public class PackageToUpdate
{
    public string PackageName { get; set; }
    public string CurrentVersion { get; set; }
    public string NewVersion { get; set; }

    // Second version in case there's a "bounds" on the package version
    public string SecondVersion { get; set; }

    // Bool to determine if a package has to be a specific version
    public bool IsSpecific { get; set; }
}

public class PackageManager
{
    // Dictionaries to store the relationships of a package (dependencies and parents)
    private readonly Dictionary<PackageToUpdate, HashSet<PackageToUpdate>> packageDependencies = new Dictionary<PackageToUpdate, HashSet<PackageToUpdate>>();
    private readonly Dictionary<PackageToUpdate, HashSet<PackageToUpdate>> reverseDependencies = new Dictionary<PackageToUpdate, HashSet<PackageToUpdate>>();

    // Path of the repository
    private readonly string repoRoot;

    // Path to the project within the repository
    private readonly string projectPath;

    public PackageManager(string repoRoot, string projectPath)
    {
        this.repoRoot = repoRoot;
        this.projectPath = projectPath;
    }

    // Method alterted from VersionFinder.cs to find the metadata of a given package
    private async Task<IPackageSearchMetadata?> FindPackageMetadataAsync(PackageIdentity packageIdentity, CancellationToken cancellationToken)
    {
        string? currentDirectory = Path.GetDirectoryName(projectPath);
        string CurrentDirectory = currentDirectory ?? Environment.CurrentDirectory;
        SourceCacheContext SourceCacheContext = new SourceCacheContext();
        PackageDownloadContext PackageDownloadContext = new PackageDownloadContext(SourceCacheContext);
        var Logger = NullLogger.Instance;

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

            try
            {
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
            }
            catch (FatalProtocolException)
            {
                // if anything goes wrong here, the package source obviously doesn't contain the requested package
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
    public async Task<List<PackageToUpdate>> GetDependenciesAsync(PackageToUpdate package, string targetFramework, string projectDirectory, ILogger logger)
    {
        if (!NuGetVersion.TryParse(package.NewVersion, out var otherVersion))
        {
            return null;
        }

        // Create a package identity to use for obtaining the metadata url
        PackageIdentity packageIdentity = new PackageIdentity(package.PackageName, otherVersion);

        bool specific = false;

        List<PackageToUpdate> dependencyList = new List<PackageToUpdate>();

        try
        {
            // Fetch package metadata URL
            var metadataUrl = await FindPackageMetadataAsync(packageIdentity, CancellationToken.None);
            IEnumerable<NuGet.Packaging.PackageDependencyGroup> dependencySet = metadataUrl?.DependencySets ?? [];

            // Get the bestMatchFramework based off the dependencies
            var bestMatchFramework = FindBestMatchFramework(dependencySet, targetFramework);

            if (bestMatchFramework != null)
            {
                // Process the best match framework
                var bestMatchGroup = dependencySet.First(dg => dg.TargetFramework == bestMatchFramework);

                foreach (var packageDependency in bestMatchGroup.Packages)
                {
                    string version = packageDependency.VersionRange.OriginalString;
                    string firstVersion = null;
                    string SecondVersion = null;

                    // Conditions to check if the version has bounds specified
                    if (version.StartsWith("[") && version.EndsWith("]"))
                    {
                        version = version.Trim('[', ']');
                        var versions = version.Split(',');
                        version = versions.FirstOrDefault().Trim();
                        if (versions.Length > 1)
                        {
                            SecondVersion = versions.LastOrDefault()?.Trim();
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
                            SecondVersion = versions.LastOrDefault()?.Trim();
                        }
                    }
                    else if (version.StartsWith("(") && version.EndsWith("]"))
                    {
                        version = version.Trim('(', ']');
                        var versions = version.Split(',');
                        version = versions.FirstOrDefault().Trim();
                        if (versions.Length > 1)
                        {
                            SecondVersion = versions.LastOrDefault()?.Trim();
                        }
                    }
                    else if (version.StartsWith("(") && version.EndsWith(")"))
                    {
                        version = version.Trim('(', ')');
                        var versions = version.Split(',');
                        version = versions.FirstOrDefault().Trim();
                        if (versions.Length > 1)
                        {
                            SecondVersion = versions.LastOrDefault()?.Trim();
                        }
                    }

                    // Store the dependency data to later add to the dependencyList
                    PackageToUpdate dependencyPackage = new PackageToUpdate
                    {
                        PackageName = packageDependency.Id,
                        CurrentVersion = version,
                    };

                    if (specific == true)
                    {
                        dependencyPackage.IsSpecific = true;
                    }

                    if (SecondVersion != null)
                    {
                        dependencyPackage.SecondVersion = SecondVersion;
                    }

                    dependencyList.Add(dependencyPackage);
                }
            }
            else
            {
                logger.Info("No compatible framework found.");
            }
        }
        catch (HttpRequestException ex)
        {
            logger.Error($"HTTP error occurred: {ex.Message}");
        }
        catch (ArgumentNullException ex)
        {
            logger.Error($"Argument is null error: {ex.ParamName}, {ex.Message}");
        }
        catch (InvalidOperationException ex)
        {
            logger.Error($"Invalid operation exception: {ex.Message}");
        }
        catch (Exception ex)
        {
            logger.Error($"An error occurred: {ex.Message}");
        }

        return dependencyList;
    }

    // Method AddDependency to create the relationships between a parent and child
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
    public async Task PopulatePackageDependenciesAsync(List<PackageToUpdate> packages, string targetFramework, string projectDirectory, ILogger logger)
    {
        // Loop through each package and get their dependencies
        foreach (PackageToUpdate package in packages)
        {
            List<PackageToUpdate> dependencies = await GetDependenciesAsync(package, targetFramework, projectDirectory, logger);

            if (dependencies == null)
            {
                continue;
            }

            // Add each dependency based off if it exists or not
            foreach (PackageToUpdate dependency in dependencies)
            {
                PackageToUpdate checkInExisting = packages.FirstOrDefault(p => string.Compare(p.PackageName, dependency.PackageName, StringComparison.OrdinalIgnoreCase) == 0);
                if (checkInExisting != null)
                {
                    checkInExisting.IsSpecific = dependency.IsSpecific;
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

    // Method to update the version of a desired package based off framework
    public async Task<string> UpdateVersion(List<PackageToUpdate> existingPackages, PackageToUpdate package, string targetFramework, string projectDirectory, ILogger logger)
    {
        // Bool to track if the package was in the original existing list
        bool inExisting = true;

        // If there is no new version to update or if the current version isn't updated
        if (package.NewVersion == null)
        {
            return "No new version";
        }

        // If the package is already updated or needs to be updated
        if (package.CurrentVersion != null)
        {
            if (package.CurrentVersion == package.NewVersion)
            {
                return "Already updated to new version";
            }
        }
        // Place the current version as the new version for updating purposes
        else
        {
            package.CurrentVersion = package.NewVersion;
            inExisting = false;
        }

        try
        {
            NuGetVersion CurrentVersion = new NuGetVersion(package.CurrentVersion);
            NuGetVersion newerVersion = new NuGetVersion(package.NewVersion);

            // If the CurrentVersion is less than or equal to the newerVersion, proceed with the update
            if (CurrentVersion <= newerVersion)
            {
                string currentVersiontemp = package.CurrentVersion;
                package.CurrentVersion = package.NewVersion;

                // Check if the current package has dependencies 
                List<PackageToUpdate> dependencyList = await GetDependenciesAsync(package, targetFramework, projectDirectory, logger);

                // If there are dependencies
                if (dependencyList != null)
                {
                    foreach (PackageToUpdate dependency in dependencyList)
                    {
                        // Check if the dependency is in the existing packages
                        foreach (PackageToUpdate existingPackage in existingPackages)
                        {
                            // If you find the dependency
                            if (string.Equals(dependency.PackageName, existingPackage.PackageName, StringComparison.OrdinalIgnoreCase))
                            {
                                NuGetVersion existingCurrentVersion = new NuGetVersion(existingPackage.CurrentVersion);
                                NuGetVersion dependencyCurrentVersion = new NuGetVersion(dependency.CurrentVersion);

                                // Check if the existing version is less than the dependency's existing version
                                if (existingCurrentVersion < dependencyCurrentVersion)
                                {
                                    // Create temporary copy of the current version and of the existing package
                                    string dependencyOldVersion = existingPackage.CurrentVersion;

                                    // Susbtitute the current version of the existingPackage with the dependency current version
                                    existingPackage.CurrentVersion = dependency.CurrentVersion;

                                    // If the family is compatible with the dependency's version, update with the dependency version
                                    if (await AreAllParentsCompatibleAsync(existingPackages, existingPackage, targetFramework, projectDirectory, logger) == true)
                                    {
                                        existingPackage.CurrentVersion = dependencyOldVersion;
                                        existingPackage.NewVersion = dependency.CurrentVersion;
                                        await UpdateVersion(existingPackages, existingPackage, targetFramework, projectDirectory, logger);
                                    }
                                    // If not, resort to putting version back to normal and remove new version
                                    else
                                    {
                                        existingPackage.CurrentVersion = dependencyOldVersion;
                                        package.CurrentVersion = currentVersiontemp;
                                        package.NewVersion = package.CurrentVersion;
                                        return "Out of scope";
                                    }
                                }
                            }
                        }

                        // If the dependency has brackets or parenthesis, it's a specific version
                        if (dependency.CurrentVersion.Contains('[') || dependency.CurrentVersion.Contains(']') || dependency.CurrentVersion.Contains('{') || dependency.CurrentVersion.Contains('}'))
                        {
                            dependency.IsSpecific = true;
                        }

                        await UpdateVersion(existingPackages, dependency, targetFramework, projectDirectory, logger);
                    }
                }

                var projectFramework = NuGetFramework.Parse(targetFramework);

                // Get the parent packages of the package and check the compatibility between its family
                HashSet<PackageToUpdate> parentPackages = GetParentPackages(package);

                foreach (PackageToUpdate parent in parentPackages)
                {
                    bool isCompatible = await IsCompatibleAsync(parent, package, targetFramework, projectDirectory, logger);

                    // If the parent and package are not compatible
                    if (!isCompatible)
                    {
                        // Attempt to find and update to a compatible version between the two
                        NuGetVersion compatibleVersion = await FindCompatibleVersionAsync(existingPackages, parent, package, targetFramework, logger);
                        if (compatibleVersion == null)
                        {
                            return "Failed to update";
                        }

                        // If a version is found, update to that version
                        parent.NewVersion = compatibleVersion.ToString();
                        await UpdateVersion(existingPackages, parent, targetFramework, projectDirectory, logger);
                    }

                    // If it's compatible and the package you updated wasn't in the existing package, check if the parent's dependencies version is the same as the current version
                    else if (isCompatible == true && inExisting == false)
                    {
                        List<PackageToUpdate> dependencyListParent = await GetDependenciesAsync(parent, targetFramework, projectDirectory, logger);

                        PackageToUpdate parentDependency = dependencyListParent.FirstOrDefault(p => string.Compare(p.PackageName, package.PackageName, StringComparison.OrdinalIgnoreCase) == 0);

                        // If the parent's dependency current version is not the same as the current version of the package
                        if (parentDependency.CurrentVersion != package.CurrentVersion)
                        {
                            // Create a NugetContext instance to get the latest versions of the parent
                            NuGetContext nugetContext = new NuGetContext(Path.GetDirectoryName(projectPath));

                            string currentVersionString = parent.CurrentVersion;
                            NuGetVersion currentVersionParent = NuGetVersion.Parse(currentVersionString);

                            var result = await VersionFinder.GetVersionsAsync([projectFramework], parent.PackageName, currentVersionParent, nugetContext, logger, CancellationToken.None);
                            var versions = result.GetVersions();
                            NuGetVersion latestVersion = versions.Where(v => !v.IsPrerelease).Max();

                            // Loop from the current version to the latest version, use next patch as a limit (unless there's a limit) so it doesn't look for versions that don't exist
                            for (NuGetVersion version = currentVersionParent; version <= latestVersion; version = NextPatch(version, versions))
                            {
                                NuGetVersion nextPatch = NextPatch(version, versions);

                                // If the next patch is the same as the currentVersioon, then the update is a Success
                                if (nextPatch == version)
                                {
                                    return "Success";
                                }

                                string parentVersion = version.ToString();
                                parent.NewVersion = parentVersion;

                                // Check if the parent needs to be updated since the child isn't in the existing package list  and the parent can update to a newer version to remove the dependency
                                List<PackageToUpdate> dependencyListParentTemp = await GetDependenciesAsync(parent, targetFramework, projectDirectory, logger);
                                PackageToUpdate parentDependencyTemp = dependencyListParentTemp.FirstOrDefault(p => string.Compare(p.PackageName, package.PackageName, StringComparison.OrdinalIgnoreCase) == 0);

                                // If the newer package version of the parent has the same version as the parent's previous dependency, update
                                if (parentDependencyTemp.CurrentVersion == package.CurrentVersion)
                                {
                                    parent.NewVersion = parentVersion;
                                    parent.CurrentVersion = null;
                                    await UpdateVersion(existingPackages, parent, targetFramework, projectDirectory, logger);
                                    package.IsSpecific = true;
                                    return "Success";
                                }
                            }
                            parent.CurrentVersion = currentVersionString;
                        }
                    }
                }
            }

            else
            {
                logger.Info("Current version is >= latest version");
            }
        }
        catch
        {
            return "Failed to update";
        }

        return "Success";
    }

    // Method to determine if a parent and child are compatible with their versions
    public async Task<bool> IsCompatibleAsync(PackageToUpdate parent, PackageToUpdate child, string targetFramework, string projectDirectory, ILogger logger)
    {
        // Get the dependencies of the parent
        List<PackageToUpdate> dependencies = await GetDependenciesAsync(parent, targetFramework, projectDirectory, logger);

        foreach (PackageToUpdate dependency in dependencies)
        {

            // If the child is present
            if (string.Equals(dependency.PackageName, child.PackageName, StringComparison.OrdinalIgnoreCase))
            {
                NuGetVersion dependencyVersion = new NuGetVersion(dependency.CurrentVersion);
                NuGetVersion childVersion = new NuGetVersion(child.CurrentVersion);

                // If the dependency version of the parent and the childversion is the same, or if the child version can be >=
                if (dependencyVersion == childVersion || (childVersion > dependencyVersion && dependency.IsSpecific != true))
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
        var versions = allVersions.Where(v => v > version);

        if (!versions.Any())
        {
            // If there are no greater versions, return current version
            return version;
        }

        // Find smallest version in the versions
        return versions.Min();
    }

    // Method to find a compatible version with the child for the parent to update to
    public async Task<NuGetVersion> FindCompatibleVersionAsync(List<PackageToUpdate> existingPackages, PackageToUpdate possibleParent, PackageToUpdate possibleDependency, string targetFramework, ILogger logger)
    {
        string packageId = possibleParent.PackageName;
        string currentVersionString = possibleParent.CurrentVersion;
        NuGetVersion CurrentVersion = NuGetVersion.Parse(currentVersionString);
        string currentVersionStringDependency = possibleDependency.CurrentVersion;
        NuGetVersion currentVersionDependency = NuGetVersion.Parse(currentVersionStringDependency);

        // Create a NugetContext instance to get the latest versions of the parent
        NuGetContext nugetContext = new NuGetContext(Path.GetDirectoryName(projectPath));
        var projectFramework = NuGetFramework.Parse(targetFramework);

        var result = await VersionFinder.GetVersionsAsync([projectFramework], possibleParent.PackageName, CurrentVersion, nugetContext, logger, CancellationToken.None);
        var versions = result.GetVersions();

        // If there are no versions
        if (versions.Length == 0)
        {
            return null;
        }

        NuGetVersion latestVersion = versions
            .Where(v => !v.IsPrerelease)
           .Max();

        // If there's a version bounds that the parent has 
        if (possibleParent.SecondVersion != null)
        {
            NuGetVersion SecondVersion = NuGetVersion.Parse(possibleParent.SecondVersion);
            latestVersion = SecondVersion;
        }

        // If there is no later version
        if (CurrentVersion == latestVersion)
        {
            return null;
        }

        // Loop from the current version to the latest version, use next patch as a limit (unless there's a limit) so it doesn't look for versions that don't exist
        for (NuGetVersion version = CurrentVersion; version <= latestVersion; version = NextPatch(version, versions))
        {
            possibleParent.NewVersion = version.ToString();

            NuGetVersion nextPatch = NextPatch(version, versions);

            // If the next patch is the same as the CurrentVersion, then nothing is needed
            if (nextPatch == version)
            {
                return nextPatch;
            }

            // Check if there's compatibility with parent and dependency
            if (await IsCompatibleAsync(possibleParent, possibleDependency, targetFramework, nugetContext.CurrentDirectory, logger))
            {
                // Check if parents are compatible, recursively
                if (await AreAllParentsCompatibleAsync(existingPackages, possibleParent, targetFramework, nugetContext.CurrentDirectory, logger))
                {
                    // If compatible, return the new version
                    if (Regex.IsMatch(possibleParent.NewVersion, @"[a-zA-Z]"))
                    {
                        possibleParent.IsSpecific = true;
                    }
                    return version;
                }
            }
        }

        // If no compatible version is found, return null
        return null;
    }

    // Method to determine if all the parents of a given package are compatible with the parent's desired version
    public async Task<bool> AreAllParentsCompatibleAsync(List<PackageToUpdate> existingPackages, PackageToUpdate possibleParent, string targetFramework, string projectDirectory, ILogger logger)
    {
        // Get the possibleParent parentPackages
        HashSet<PackageToUpdate> parentPackages = GetParentPackages(possibleParent);

        foreach (PackageToUpdate parent in parentPackages)
        {
            // Check compatibility between the possibleParent and current parent
            bool isCompatible = await IsCompatibleAsync(parent, possibleParent, targetFramework, projectDirectory, logger);

            // If the possibleParent and parent are not compatible
            if (!isCompatible)
            {
                // Find a compatible version if possible
                NuGetVersion compatibleVersion = await FindCompatibleVersionAsync(existingPackages, parent, possibleParent, targetFramework, logger);
                if (compatibleVersion == null)
                {
                    return false;
                }

                parent.NewVersion = compatibleVersion.ToString();
                await UpdateVersion(existingPackages, parent, targetFramework, projectDirectory, logger);
            }

            // Recursively check if all ancestors are compatible
            if (!await AreAllParentsCompatibleAsync(existingPackages, parent, targetFramework, projectDirectory, logger))
            {
                return false;
            }
        }

        return true;
    }

    // Method to update the existing packages with new version of the desired packages to update
    public void UpdateExistingPackagesWithNewVersions(List<PackageToUpdate> existingPackages, List<PackageToUpdate> packagesToUpdate, ILogger logger)
    {
        foreach (PackageToUpdate packageToUpdate in packagesToUpdate)
        {
            PackageToUpdate existingPackage = existingPackages.FirstOrDefault(p => string.Compare(p.PackageName, packageToUpdate.PackageName, StringComparison.OrdinalIgnoreCase) == 0);

            if (existingPackage != null)
            {
                existingPackage.NewVersion = packageToUpdate.NewVersion;
            }
            else
            {
                logger.Info($"Package {packageToUpdate.PackageName} not found in existing packages");
            }
        }
    }
}
