#nullable disable

using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Versioning;
using System.Threading;
using System.Xml.Linq;
using NuGet.Commands;
using NuGet.Common;
using NuGet.Configuration;
using NuGet.Frameworks;
using NuGet.PackageManagement;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.ProjectManagement;
using NuGet.ProjectModel;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;
using XElementExtensions = NuGet.Packaging.XElementExtensions;

namespace NuGet.CommandLine
{
    public class ProjectFactory : IProjectFactory, IDisposable
    {
        private const string NUGET_ENABLE_LEGACY_CSPROJ_PACK = nameof(NUGET_ENABLE_LEGACY_CSPROJ_PACK);

        // Its type is Microsoft.Build.Evaluation.Project
        private dynamic _project;

        private ILogger _logger;

        private IEnvironmentVariableReader _environmentVariableReader;

        // Files we want to always exclude from the resulting package
        private static readonly HashSet<string> ExcludeFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
            NuGetConstants.PackageReferenceFile,
            "Web.Debug.config",
            "Web.Release.config"
        };

        private readonly Dictionary<string, string> _properties = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        private readonly MSBuildAssemblyResolver _msbuildAssemblyResolver;

        // Packaging folders
        private const string ContentFolder = "content";

        private const string ReferenceFolder = "lib";
        private const string ToolsFolder = "tools";
        private const string SourcesFolder = "src";

        // Common item types
        private const string SourcesItemType = "Compile";

        private const string ContentItemType = "Content";
        private const string ProjectReferenceItemType = "ProjectReference";
        private const string ReferenceOutputAssembly = "ReferenceOutputAssembly";
        private const string TransformFileExtension = ".transform";

        [Import]
        public IMachineWideSettings MachineWideSettings { get; set; }

        public static IProjectFactory ProjectCreator(PackArgs packArgs, string path)
        {
            return new ProjectFactory(packArgs.MsBuildDirectory.Value, path, packArgs.Properties)
            {
                IsTool = packArgs.Tool,
                LogLevel = packArgs.LogLevel,
                Logger = packArgs.Logger,
                MachineWideSettings = packArgs.MachineWideSettings,
                Build = packArgs.Build,
                IncludeReferencedProjects = packArgs.IncludeReferencedProjects,
                SymbolPackageFormat = packArgs.SymbolPackageFormat,
                PackagesDirectory = packArgs.PackagesDirectory,
                SolutionDirectory = packArgs.SolutionDirectory,
            };
        }

        public ProjectFactory(string msbuildDirectory, string path, IDictionary<string, string> projectProperties)
        {
            _environmentVariableReader = EnvironmentVariableWrapper.Instance;

            _msbuildAssemblyResolver = new MSBuildAssemblyResolver(msbuildDirectory);

            var project = Activator.CreateInstance(
                    _msbuildAssemblyResolver.ProjectType,
                    path,
                    projectProperties,
                    null);
            Initialize(project);
        }

        public ProjectFactory(string msbuildDirectory, dynamic project)
        {
            Initialize(project);
            _environmentVariableReader = EnvironmentVariableWrapper.Instance;
        }

        private ProjectFactory(
            MSBuildAssemblyResolver msbuildAssemblyResolver,
            dynamic project,
            IEnvironmentVariableReader environmentVariableReader)
        {
            _msbuildAssemblyResolver = msbuildAssemblyResolver;
            _environmentVariableReader = environmentVariableReader;
            Initialize(project);
        }

        private void Initialize(dynamic project)
        {
            _project = project;
            ProjectProperties = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            AddSolutionDir();
            // Get the target framework of the project
            string targetFrameworkMoniker = _project.GetPropertyValue("TargetFrameworkMoniker");
            if (!string.IsNullOrEmpty(targetFrameworkMoniker))
            {
                TargetFramework = NuGetFramework.Parse(targetFrameworkMoniker);
            }

            // This happens before we obtain warning properties, so this Logger is still IConsole.
            IConsole console = Logger as IConsole;
            switch (LogLevel)
            {
                case LogLevel.Verbose:
                    {
                        console.Verbosity = Verbosity.Detailed;
                        break;
                    }
                case LogLevel.Information:
                    {
                        console.Verbosity = Verbosity.Normal;
                        break;
                    }
                case LogLevel.Minimal:
                    {
                        console.Verbosity = Verbosity.Quiet;
                        break;
                    }
            }
        }

        public WarningProperties GetWarningPropertiesForProject()
        {
            var treatWarningsAsErrors = GetPropertyValue("TreatWarningsAsErrors");
            return WarningProperties.GetWarningProperties(treatWarningsAsErrors: string.IsNullOrEmpty(treatWarningsAsErrors) ? "false" : treatWarningsAsErrors,
                warningsAsErrors: GetPropertyValue("WarningsAsErrors"),
                noWarn: GetPropertyValue("NoWarn"),
                warningsNotAsErrors: GetPropertyValue("WarningsNotAsErrors"));
        }

        private string TargetPath
        {
            get;
            set;
        }

        private NuGetFramework TargetFramework
        {
            get;
            set;
        }

        public void SetIncludeSymbols(bool includeSymbols)
        {
            IncludeSymbols = includeSymbols;
        }
        public bool IncludeSymbols { get; set; }

        public bool IncludeReferencedProjects { get; set; }
        public bool Build { get; set; }

        public Dictionary<string, string> GetProjectProperties()
        {
            return ProjectProperties;
        }
        public Dictionary<string, string> ProjectProperties { get; private set; }

        public bool IsTool { get; set; }

        public LogLevel LogLevel { get; set; }

        public SymbolPackageFormat SymbolPackageFormat { get; set; }

        public string PackagesDirectory { get; set; }

        public string SolutionDirectory { get; set; }

        public ILogger Logger
        {
            get
            {
                return _logger ?? Common.NullLogger.Instance;
            }
            set
            {
                _logger = value;
            }
        }

        [SuppressMessage("Microsoft.Design", "CA1031:DoNotCatchGeneralExceptionTypes", Justification = "We want to continue regardless of any error we encounter extracting metadata.")]
        public PackageBuilder CreateBuilder(string basePath, NuGetVersion version, string suffix, bool buildIfNeeded, PackageBuilder builder = null)
        {
            if (buildIfNeeded)
            {
                BuildProject();
            }

            if (!string.IsNullOrEmpty(TargetPath))
            {
                Logger.Log(PackagingLogMessage.CreateMessage(string.Format(
                        CultureInfo.CurrentCulture,
                        LocalizedResourceManager.GetString("PackagingFilesFromOutputPath"),
                        Path.GetFullPath(Path.GetDirectoryName(TargetPath))), LogLevel.Minimal));
            }

            string usingNETSDK = _project.GetPropertyValue("UsingMicrosoftNETSDK");
            if (!string.IsNullOrEmpty(usingNETSDK)) // NuGet.exe cannot correctly pack SDK based projects.
            {
                _ = bool.TryParse(_environmentVariableReader.GetEnvironmentVariable(NUGET_ENABLE_LEGACY_CSPROJ_PACK),
                    out bool enableLegacyCsprojPack);

                if (!enableLegacyCsprojPack)
                {
                    Logger.Log(PackagingLogMessage.CreateError(string.Format(NuGetResources.Error_AttemptingToPackSDKproject, NUGET_ENABLE_LEGACY_CSPROJ_PACK, CultureInfo.CurrentCulture), NuGetLogCode.NU5049));
                    return null;
                }
            }

            builder = new PackageBuilder(false, Logger);

            try
            {
                ExtractMetadata(builder);
            }
            catch (PackagingException packex) when (packex.AsLogMessage().Code.Equals(NuGetLogCode.NU5133))
            {
                ExceptionUtilities.LogException(packex, Logger);
                return null;
            }
            catch (Exception ex)
            {
                Logger.Log(PackagingLogMessage.CreateError(string.Format(
                        CultureInfo.CurrentCulture,
                        LocalizedResourceManager.GetString("UnableToExtractAssemblyMetadata"),
                        Path.GetFileName(TargetPath)), NuGetLogCode.NU5011));
                if (LogLevel == LogLevel.Verbose)
                {
                    Logger.Log(PackagingLogMessage.CreateError(ex.ToString(), NuGetLogCode.NU5011));
                }
                else
                {
                    Logger.Log(PackagingLogMessage.CreateError(ex.Message, NuGetLogCode.NU5011));
                }

                return null;
            }

            var projectAuthor = InitializeProperties(builder);

            // Set version based on version argument from console?
            if (version != null)
            {
                // make sure the $version$ placeholder gets populated correctly
                _properties["version"] = version.ToFullString();

                builder.Version = version;
            }

            // Only override properties from assembly extracted metadata if they haven't
            // been specified also at construction time for the factory (that is,
            // console properties always take precedence.
            foreach ((var key, var value) in builder.Properties)
            {
                if (!_properties.ContainsKey(key) &&
                    !ProjectProperties.ContainsKey(key))
                {
                    _properties.Add(key, value);
                }
            }

            // If the package contains a nuspec file then use it for metadata
            Manifest manifest = ProcessNuspec(builder, basePath);

            // Remove the extra author
            if (builder.Authors.Count > 1)
            {
                builder.Authors.Remove(projectAuthor);
            }

            // Add output files
            ApplyAction(p => p.AddOutputFiles(builder));

            // Add content files if there are any. They could come from a project or nuspec file
            // In order to be compliant with the documented behavior, if the nuspec file has an
            // empty <files> element, we do not add any content files at all. If the <files> element
            // has one or more files specified, then those files are added to the package along with
            // any files of type Content from the csproj file.
            if (manifest == null || !manifest.HasFilesNode || manifest.Files.Count > 0)
            {
                ApplyAction(p => p.AddFiles(builder, ContentItemType, ContentFolder));
            }

            // Add sources if this is a symbol package
            if (IncludeSymbols)
            {
                if (SymbolPackageFormat == SymbolPackageFormat.SymbolsNupkg)
                {
                    ApplyAction(p => p.AddFiles(builder, SourcesItemType, SourcesFolder));
                }

            }

            ProcessDependencies(builder);

            // Set defaults if some required fields are missing
            if (string.IsNullOrEmpty(builder.Description))
            {
                builder.Description = "Description";
                Logger.Log(PackagingLogMessage.CreateWarning(string.Format(
                        CultureInfo.CurrentCulture,
                        LocalizedResourceManager.GetString("Warning_UnspecifiedField"),
                        "Description",
                        "Description"), NuGetLogCode.NU5115));
            }

            if (!builder.Authors.Any())
            {
                builder.Authors.Add(Environment.UserName);
                Logger.Log(PackagingLogMessage.CreateWarning(string.Format(
                        CultureInfo.CurrentCulture,
                        LocalizedResourceManager.GetString("Warning_UnspecifiedField"),
                        "Author",
                        Environment.UserName), NuGetLogCode.NU5115));
            }

            return builder;
        }

        public string InitializeProperties(Packaging.IPackageMetadata metadata)
        {
            // Set the properties that were resolved from the assembly/project so they can be
            // resolved by name if the nuspec contains tokens
            _properties.Clear();

            // Allow Id to be overridden by cmd line properties
            if (ProjectProperties.TryGetValue("Id", out var id))
            {
                _properties.Add("Id", id);
            }
            else
            {
                _properties.Add("Id", metadata.Id);
            }

            _properties.Add("Version", metadata.Version.ToFullString());

            if (!string.IsNullOrEmpty(metadata.Title))
            {
                _properties.Add("Title", metadata.Title);
            }

            if (!string.IsNullOrEmpty(metadata.Description))
            {
                _properties.Add("Description", metadata.Description);
            }

            if (!string.IsNullOrEmpty(metadata.Copyright))
            {
                _properties.Add("Copyright", metadata.Copyright);
            }

            string projectAuthor = metadata.Authors.FirstOrDefault();
            if (!string.IsNullOrEmpty(projectAuthor))
            {
                _properties.Add("Author", projectAuthor);
            }
            return projectAuthor;
        }

        public string GetPropertyValue(string propertyName)
        {
            string value;
            if (!_properties.TryGetValue(propertyName, out value) &&
                !ProjectProperties.TryGetValue(propertyName, out value))
            {
                dynamic property = _project.GetProperty(propertyName);
                if (property != null)
                {
                    value = property.EvaluatedValue;
                }
            }

            return value;
        }

        private void BuildProject()
        {
            if (Build)
            {
                if (TargetFramework != null)
                {
                    Logger.Log(PackagingLogMessage.CreateMessage(string.Format(
                            CultureInfo.CurrentCulture,
                            LocalizedResourceManager.GetString("BuildingProjectTargetingFramework"),
                            _project.FullPath,
                            TargetFramework), LogLevel.Minimal));
                }

                BuildProjectWithMsbuild();
            }
            else
            {
                TargetPath = ResolveTargetPath();

                // Make if the target path doesn't exist, fail
                if (!Directory.Exists(TargetPath) && !File.Exists(TargetPath))
                {
                    throw new PackagingException(NuGetLogCode.NU5012, string.Format(CultureInfo.CurrentCulture, LocalizedResourceManager.GetString("UnableToFindBuildOutput"), TargetPath));
                }
            }
        }

        private void BuildProjectWithMsbuild()
        {
            string properties = string.Empty;
            foreach (var property in ProjectProperties)
            {
                string escapedValue = MsBuildUtility.Escape(property.Value);
                properties += $" /p:{property.Key}={escapedValue}";
            }

            int result = MsBuildUtility.Build(_msbuildAssemblyResolver.MSBuildDirectory, $"\"{_project.FullPath}\" {properties} /toolsversion:{_project.ToolsVersion}");

            if (0 != result) // 0 is msbuild.exe success code
            {
                // If the build fails, report the error
                var error = string.Format(CultureInfo.CurrentCulture, LocalizedResourceManager.GetString("FailedToBuildProject"), Path.GetFileName(_project.FullPath));
                throw new PackagingException(NuGetLogCode.NU5013, error);
            }

            TargetPath = ResolveTargetPath();
        }

        private string ResolveTargetPath()
        {
            // Set the project properties
            foreach (var property in ProjectProperties)
            {
                var existingProperty = _project.GetProperty(property.Key);
                if (existingProperty == null || !IsGlobalProperty(existingProperty))
                {
                    // Only set the property if it's not already defined as a global property
                    // (which those passed in via the ctor are) as trying to set global properties
                    // with this method throws.
                    _project.SetProperty(property.Key, property.Value);
                }
            }

            // Re-evaluate the project so that the new property values are applied
            _project.ReevaluateIfNecessary();

            // Return the new target path
            string targetPath = _project.GetPropertyValue("TargetPath");

            if (string.IsNullOrEmpty(targetPath))
            {
                string outputPath = _project.GetPropertyValue("OutputPath");
                string configuration = _project.GetPropertyValue("Configuration");
                string projectName = Path.GetFileName(Path.GetDirectoryName(_project.FullPath));
                targetPath = PathUtility.EnsureTrailingSlash(Path.Combine(outputPath, projectName, "bin", configuration));
            }

            return targetPath;
        }

        // The type of projectProperty is Microsoft.Build.Evaluation.ProjectProperty
        private static bool IsGlobalProperty(object projectProperty)
        {
            // This property isn't available on xbuild (mono)
            var property = projectProperty.GetType().GetProperty("IsGlobalProperty", BindingFlags.Public | BindingFlags.Instance);
            if (property != null)
            {
                return (bool)property.GetValue(projectProperty, null);
            }

            // REVIEW: Maybe there's something better we can do on mono
            // Just return false if the property isn't there
            return false;
        }

        private void ExtractMetadataFromProject(Packaging.PackageBuilder builder)
        {
            builder.Id = builder.Id ??
                        _project.GetPropertyValue("AssemblyName") ??
                        Path.GetFileNameWithoutExtension(_project.FullPath);

            string version = _project.GetPropertyValue("Version");
            if (builder.Version == null)
            {
                NuGetVersion parsedVersion;

                if (NuGetVersion.TryParse(version, out parsedVersion))
                {
                    builder.Version = parsedVersion;
                }
                else
                {
                    builder.Version = new NuGetVersion(1, 0, 0);
                }
            }
        }

        private static IEnumerable<string> GetFiles(string path, ISet<string> fileNames, SearchOption searchOption)
        {
            return Directory.EnumerateFiles(path, "*", searchOption)
                .Where(filePath => fileNames.Contains(Path.GetFileName(filePath)));
        }

        private void ApplyAction(Action<ProjectFactory> action)
        {
            if (IncludeReferencedProjects)
            {
                RecursivelyApply(action);
            }
            else
            {
                action(this);
            }
        }

        /// <summary>
        /// Recursively execute the specified action on the current project and
        /// projects referenced by the current project.
        /// </summary>
        /// <param name="action">The action to be executed.</param>
        private void RecursivelyApply(Action<ProjectFactory> action)
        {
            var projectCollection = Activator.CreateInstance(_msbuildAssemblyResolver.ProjectCollectionType) as IDisposable;
            using (projectCollection)
            {
                RecursivelyApply(action, projectCollection);
            }
        }

        /// <summary>
        /// Recursively execute the specified action on the current project and
        /// projects referenced by the current project.
        /// </summary>
        /// <param name="action">The action to be executed.</param>
        /// <param name="alreadyAppliedProjects">The collection of projects that have been processed.
        /// It is used to avoid processing the same project more than once.</param>
        private void RecursivelyApply(Action<ProjectFactory> action, dynamic alreadyAppliedProjects)
        {
            action(this);
            foreach (var item in _project.GetItems(ProjectReferenceItemType))
            {
                if (ShouldExcludeItem(item))
                {
                    continue;
                }

                string fullPath = item.GetMetadataValue("FullPath");
                if (!string.IsNullOrEmpty(fullPath) &&
                    !NuspecFileExists(fullPath) &&
                    !File.Exists(ProjectJsonPathUtilities.GetProjectConfigPath(Path.GetDirectoryName(fullPath), Path.GetFileName(fullPath))) &&
                    alreadyAppliedProjects.GetLoadedProjects(fullPath).Count == 0)
                {
                    dynamic project = Activator.CreateInstance(
                        _msbuildAssemblyResolver.ProjectType,
                        fullPath,
                        null,
                        null,
                        alreadyAppliedProjects);
                    var referencedProject = new ProjectFactory(_msbuildAssemblyResolver, project, _environmentVariableReader);
                    referencedProject.Logger = _logger;
                    referencedProject.IncludeSymbols = IncludeSymbols;
                    referencedProject.Build = Build;
                    referencedProject.IncludeReferencedProjects = IncludeReferencedProjects;
                    referencedProject.ProjectProperties = ProjectProperties;
                    referencedProject.TargetFramework = TargetFramework;
                    referencedProject.BuildProject();
                    referencedProject.SymbolPackageFormat = SymbolPackageFormat;
                    referencedProject.RecursivelyApply(action, alreadyAppliedProjects);
                }
            }
        }

        /// <summary>
        /// Should the project item be excluded based on the Reference output assembly metadata
        /// </summary>
        /// <param name="item">Dynamic item which is a project item</param>
        /// <returns>true, if the item should be excluded. false, otherwise.</returns>
        private static bool ShouldExcludeItem(dynamic item)
        {
            if (item == null)
            {
                return true;
            }

            if (item.HasMetadata(ReferenceOutputAssembly))
            {
                bool result;
                if (bool.TryParse(item.GetMetadataValue("ReferenceOutputAssembly"), out result))
                {
                    if (!result)
                    {
                        return true;
                    }
                }
            }

            return false;
        }

        /// <summary>
        /// Returns whether a project file has a corresponding nuspec file.
        /// </summary>
        /// <param name="projectFileFullName">The name of the project file.</param>
        /// <returns>True if there is a corresponding nuspec file.</returns>
        private static bool NuspecFileExists(string projectFileFullName)
        {
            var nuspecFile = Path.ChangeExtension(projectFileFullName, NuGetConstants.ManifestExtension);
            return File.Exists(nuspecFile);
        }

        /// <summary>
        /// Adds referenced projects that have corresponding nuspec files as dependencies.
        /// </summary>
        /// <param name="dependencies">The dependencies collection where the new dependencies
        /// are added into.</param>
        private void AddProjectReferenceDependencies(Dictionary<string, Packaging.Core.PackageDependency> dependencies)
        {
            var processedProjects = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var projectsToProcess = new Queue<object>();
            dynamic projectCollection = Activator.CreateInstance(_msbuildAssemblyResolver.ProjectCollectionType);
            using ((IDisposable)projectCollection)
            {
                projectsToProcess.Enqueue(_project);
                while (projectsToProcess.Count > 0)
                {
                    dynamic project = projectsToProcess.Dequeue();
                    processedProjects.Add(project.FullPath);

                    foreach (var projectReference in project.GetItems(ProjectReferenceItemType))
                    {
                        if (ShouldExcludeItem(projectReference))
                        {
                            continue;
                        }

                        string fullPath = projectReference.GetMetadataValue("FullPath");
                        if (string.IsNullOrEmpty(fullPath) ||
                            processedProjects.Contains(fullPath))
                        {
                            continue;
                        }

                        var loadedProjects = projectCollection.GetLoadedProjects(fullPath);
                        var referencedProject = loadedProjects.Count > 0 ?
                            loadedProjects[0] :
                            Activator.CreateInstance(
                                _msbuildAssemblyResolver.ProjectType,
                                fullPath,
                                project.GlobalProperties,
                                null,
                                projectCollection);

                        if (NuspecFileExists(fullPath) || File.Exists(ProjectJsonPathUtilities.GetProjectConfigPath(Path.GetDirectoryName(fullPath), Path.GetFileName(fullPath))))
                        {
                            var dependency = CreateDependencyFromProject(referencedProject, dependencies);
                            dependencies[dependency.Id] = dependency;
                        }
                        else
                        {
                            projectsToProcess.Enqueue(referencedProject);
                        }
                    }
                }
            }
        }

        // Creates a package dependency from the given project, which has a corresponding
        // nuspec file.
        private PackageDependency CreateDependencyFromProject(dynamic project, Dictionary<string, Packaging.Core.PackageDependency> dependencies)
        {
            try
            {
                var projectFactory = new ProjectFactory(_msbuildAssemblyResolver, project, EnvironmentVariableWrapper.Instance);
                projectFactory.Build = Build;
                projectFactory.ProjectProperties = ProjectProperties;
                projectFactory.SymbolPackageFormat = SymbolPackageFormat;
                projectFactory.BuildProject();
                var builder = new PackageBuilder();

                projectFactory.ExtractMetadata(builder);
                projectFactory.InitializeProperties(builder);
                projectFactory.ProcessNuspec(builder, null);

                VersionRange versionRange = null;
                if (dependencies.TryGetValue(builder.Id, out PackageDependency dependency))
                {
                    VersionRange nuspecVersion = dependency.VersionRange;
                    if (nuspecVersion != null)
                    {
                        versionRange = nuspecVersion;
                    }
                }

                if (versionRange == null)
                {
                    versionRange = VersionRange.Parse(builder.Version.ToString());
                }

                return new Packaging.Core.PackageDependency(
                    builder.Id,
                    versionRange);
            }
            catch (Exception ex)
            {
                var message = string.Format(
                    CultureInfo.InvariantCulture,
                    LocalizedResourceManager.GetString("Error_ProcessingNuspecFile"),
                    project.FullPath,
                    ex.Message);
                throw new PackagingException(NuGetLogCode.NU5014, message, ex);
            }
        }

        private void ExtractMetadata(Packaging.PackageBuilder builder)
        {
            // If building an xproj, then TargetPath points to the folder where the framework folders will be
            // instead of to a single dll. Skip trying to ExtractMetadata from the dll and instead
            // use only metadata from the project and json file.
            if (!Directory.Exists(TargetPath))
            {
                // If building a project targeting netstandard, assembly metadata extraction fails
                // because it tries to load system.runtime version 4.1.0 which is not present in the local
                // path or the gac. In this case, we should just skip it and extract metadata from the project.
                try
                {
                    new AssemblyMetadataExtractor(Logger).ExtractMetadata(builder, TargetPath);
                }
                catch (PackagingException packex) when (packex.AsLogMessage().Code.Equals(NuGetLogCode.NU5133))
                {
                    // Reflection loading error for sandboxed assembly, rethrow it to fail packing.
                    throw;
                }
                catch (Exception ex)
                {
                    Logger.Log(PackagingLogMessage.CreateMessage(ex.Message, LogLevel.Verbose));
                    ExtractMetadataFromProject(builder);
                }
            }
            else
            {
                ExtractMetadataFromProject(builder);
            }
        }

        private void AddOutputFiles(Packaging.PackageBuilder builder)
        {
            // Get the target framework of the project
            NuGetFramework nugetFramework = TargetFramework;

            var projectOutputDirectory = Path.GetDirectoryName(TargetPath);
            string targetFileName;

            if (Directory.Exists(TargetPath))
            {
                targetFileName = builder.Id;
            }
            else
            {
                targetFileName = Path.GetFileNameWithoutExtension(TargetPath);
            }

            var outputFileNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                $"{targetFileName}.dll",
                $"{targetFileName}.exe",
                $"{targetFileName}.xml",
                $"{targetFileName}.winmd"
            };

            if (IncludeSymbols)
            {
                // if this is a snupkg package, we don't want any files other than symbol files.
                if (SymbolPackageFormat == SymbolPackageFormat.Snupkg)
                {
                    outputFileNames.Clear();
                    outputFileNames.Add($"{targetFileName}.pdb");
                }
                else
                {
                    outputFileNames.Add($"{targetFileName}.pdb");
                    outputFileNames.Add($"{targetFileName}.dll.mdb");
                    outputFileNames.Add($"{targetFileName}.exe.mdb");
                }
            }

            foreach (var file in GetFiles(projectOutputDirectory, outputFileNames, SearchOption.AllDirectories))
            {
                string targetFolder;

                if (IsTool)
                {
                    targetFolder = ToolsFolder;
                }
                else
                {
                    if (Directory.Exists(TargetPath))
                    {
                        targetFolder = Path.Combine(ReferenceFolder, Path.GetDirectoryName(file.Replace(TargetPath, string.Empty)));
                    }
                    else if (nugetFramework == null)
                    {
                        targetFolder = ReferenceFolder;
                    }
                    else
                    {
                        string shortFolderName = nugetFramework.GetShortFolderName();
                        targetFolder = Path.Combine(ReferenceFolder, shortFolderName);
                    }
                }
                var packageFile = new Packaging.PhysicalPackageFile
                {
                    SourcePath = file,
                    TargetPath = Path.Combine(targetFolder, Path.GetFileName(file))
                };
                AddFileToBuilder(builder, packageFile);
            }
        }

        private void ProcessDependencies(Packaging.PackageBuilder builder)
        {
            // get all packages and dependencies, including the ones in project references
            var packagesAndDependencies = new Dictionary<string, Tuple<PackageReaderBase, Packaging.Core.PackageDependency>>();
            ApplyAction(p => p.AddDependencies(packagesAndDependencies));

            // list of all dependency packages
            var packages = packagesAndDependencies.Values.Select(t => t.Item1).ToList();

            // Add the transform file to the package builder
            ProcessTransformFiles(builder, packages.SelectMany(GetTransformFiles));

            var dependencies = builder.DependencyGroups.SelectMany(d => d.Packages)
                .ToDictionary(d => d.Id, StringComparer.OrdinalIgnoreCase);

            // Reduce the set of packages we want to include as dependencies to the minimal set.
            // Normally, packages.config has the full closure included, we only add top level
            // packages, i.e. packages with in-degree 0
            foreach (var package in packages)
            {
                // Don't add duplicate dependencies
                var packageIdentity = package.GetIdentity();
                if (dependencies.ContainsKey(packageIdentity.Id) ||
                    !FindDependency(packageIdentity, packagesAndDependencies.Values))
                {
                    continue;
                }

                var dependency = packagesAndDependencies[packageIdentity.Id].Item2;
                dependencies[dependency.Id] = dependency;
            }

            DisposePackageReaders(packagesAndDependencies);

            if (IncludeReferencedProjects)
            {
                AddProjectReferenceDependencies(dependencies);
            }

            builder.DependencyGroups.Clear();

            var targetFramework = TargetFramework ?? NuGetFramework.AnyFramework;
            builder.DependencyGroups.Add(new PackageDependencyGroup(targetFramework, new HashSet<PackageDependency>(dependencies.Values)));
        }

        private bool FindDependency(PackageIdentity projectPackage, IEnumerable<Tuple<PackageReaderBase, Packaging.Core.PackageDependency>> packagesAndDependencies)
        {
            // returns true if the dependency should be added to the package
            // This happens if the dependency is not a dependency of a dependency
            // Or if the project dependency version is != the dependency's dependency version
            bool found = false;
            foreach (var reader in packagesAndDependencies)
            {
                foreach (var set in reader.Item1.GetPackageDependencies())
                {
                    foreach (var dependency in set.Packages)
                    {
                        if (dependency.Id.Equals(projectPackage.Id, StringComparison.OrdinalIgnoreCase))
                        {
                            found = true;

                            if (dependency.VersionRange.MinVersion < projectPackage.Version ||
                                (!dependency.VersionRange.IsMinInclusive &&
                                dependency.VersionRange.MinVersion == projectPackage.Version))
                            {
                                return true;
                            }
                        }
                    }
                }
            }

            return !found;
        }

        private void AddDependencies(Dictionary<string, Tuple<PackageReaderBase, Packaging.Core.PackageDependency>> packagesAndDependencies)
        {
            Dictionary<string, object> props = new Dictionary<string, object>();

            foreach (var property in _project.Properties)
            {
                props.Add(property.Name, property.EvaluatedValue);
            }

            if (!props.ContainsKey(NuGetProjectMetadataKeys.TargetFramework))
            {
                props.Add(NuGetProjectMetadataKeys.TargetFramework, TargetFramework);
            }
            if (!props.ContainsKey(NuGetProjectMetadataKeys.Name))
            {
                props.Add(NuGetProjectMetadataKeys.Name, Path.GetFileNameWithoutExtension(_project.FullPath));
            }

            PackagesConfigNuGetProject packagesProject = new PackagesConfigNuGetProject(_project.DirectoryPath, props);

            if (!packagesProject.PackagesConfigExists())
            {
                return;
            }
            Logger.Log(PackagingLogMessage.CreateMessage(LocalizedResourceManager.GetString("UsingPackagesConfigForDependencies"), LogLevel.Minimal));

            var references = packagesProject.GetInstalledPackagesAsync(CancellationToken.None).Result;

            string packagesFolderPath;
            if (!string.IsNullOrEmpty(PackagesDirectory))
            {
                packagesFolderPath = PackagesDirectory;
            }
            else
            {
                var solutionDir = GetSolutionDir();
                if (solutionDir == null)
                {
                    packagesFolderPath = PackagesFolderPathUtility.GetPackagesFolderPath(_project.DirectoryPath, ReadSettings(_project.DirectoryPath));
                }
                else
                {
                    packagesFolderPath = PackagesFolderPathUtility.GetPackagesFolderPath(solutionDir, ReadSettings(solutionDir));
                }
            }

            var findLocalPackagesResource = Repository
                .Factory
                .GetCoreV3(packagesFolderPath)
                .GetResource<FindLocalPackagesResource>(CancellationToken.None);

            // Collect all packages
            IDictionary<PackageIdentity, PackageReference> packageReferences =
                references
                .Where(r => !r.IsDevelopmentDependency)
                .ToDictionary(r => r.PackageIdentity);

            // add all packages and create an associated dependency to the dictionary
            foreach (PackageReference reference in packageReferences.Values)
            {
                var packageReference = references.FirstOrDefault(r => r.PackageIdentity == reference.PackageIdentity);
                if (packageReference != null && !packagesAndDependencies.ContainsKey(packageReference.PackageIdentity.Id))
                {
                    VersionRange range;
                    if (packageReference.HasAllowedVersions)
                    {
                        range = packageReference.AllowedVersions;
                    }
                    else
                    {
                        range = new VersionRange(packageReference.PackageIdentity.Version);
                    }

                    var localPackageInfo = findLocalPackagesResource.GetPackage(
                        packageReference.PackageIdentity,
                        _logger,
                        CancellationToken.None);

                    var reader = localPackageInfo?.GetReader();
                    if (reader != null)
                    {
                        try
                        {
                            var dependency = new PackageDependency(packageReference.PackageIdentity.Id, range);
                            packagesAndDependencies.Add(packageReference.PackageIdentity.Id, Tuple.Create<PackageReaderBase, PackageDependency>(reader, dependency));
                        }
                        catch (Exception)
                        {
                            DisposePackageReaders(packagesAndDependencies);
                            reader.Dispose();

                            throw;
                        }
                    }
                    else
                    {
                        DisposePackageReaders(packagesAndDependencies);

                        var packageName = $"{packageReference.PackageIdentity.Id}.{packageReference.PackageIdentity.Version}";
                        throw new PackagingException(NuGetLogCode.NU5012, string.Format(CultureInfo.CurrentCulture, NuGetResources.UnableToFindBuildOutput, $"{packageName}.nupkg"));
                    }
                }
            }
        }

        private static void DisposePackageReaders(Dictionary<string, Tuple<PackageReaderBase, PackageDependency>> packagesAndDependencies)
        {
            // Release the open file handles
            foreach (var package in packagesAndDependencies)
            {
                package.Value.Item1.Dispose();
            }
        }

        private ISettings ReadSettings(string solutionDirectory)
        {
            // Read the solution-level settings
            var solutionSettingsFile = Path.Combine(
                solutionDirectory,
                NuGetConstants.NuGetSolutionSettingsFolder);

            return Settings.LoadDefaultSettings(
                solutionSettingsFile,
                configFileName: null,
                machineWideSettings: MachineWideSettings);
        }

        private static void ProcessTransformFiles(PackageBuilder builder, IEnumerable<IPackageFile> transformFiles)
        {
            // Group transform by target file
            var transformGroups = transformFiles.GroupBy(file => RemoveExtension(file.Path), StringComparer.OrdinalIgnoreCase);
            var fileLookup = builder.Files.ToDictionary(file => file.Path, StringComparer.OrdinalIgnoreCase);

            foreach (var transformGroup in transformGroups)
            {
                IPackageFile file;
                if (fileLookup.TryGetValue(transformGroup.Key, out file))
                {
                    // Replace the original file with a file that removes the transforms
                    builder.Files.Remove(file);
                    builder.Files.Add(new ReverseTransformFormFile(file, transformGroup));
                }
            }
        }

        /// <summary>
        /// Removes a file extension keeping the full path intact
        /// </summary>
        private static string RemoveExtension(string path)
        {
            return Path.Combine(Path.GetDirectoryName(path), Path.GetFileNameWithoutExtension(path));
        }

        private IEnumerable<IPackageFile> GetTransformFiles(PackageReaderBase package)
        {
            var groups = package.GetContentItems();
            return groups.SelectMany(g => g.Items).Where(IsTransformFile).Select(f =>
            {
                var element = XElement.Load(package.GetStream(f));
                var memStream = new MemoryStream();
                element.Save(memStream);
                memStream.Seek(0, SeekOrigin.Begin);

                var file = new PhysicalPackageFile(memStream)
                {
                    TargetPath = f
                };
                return file;
            }
        );
        }

        private static bool IsTransformFile(string file)
        {
            return Path.GetExtension(file).Equals(TransformFileExtension, StringComparison.OrdinalIgnoreCase);
        }

        private void AddSolutionDir()
        {
            // Add the solution dir to the list of properties
            string solutionDir = GetSolutionDir();

            // Add a path separator for Visual Studio macro compatibility
            solutionDir += Path.DirectorySeparatorChar;

            if (!string.IsNullOrEmpty(solutionDir))
            {
                if (ProjectProperties.ContainsKey("SolutionDir"))
                {
                    Logger.Log(PackagingLogMessage.CreateWarning(string.Format(
                            CultureInfo.CurrentCulture,
                            LocalizedResourceManager.GetString("Warning_DuplicatePropertyKey"),
                            "SolutionDir"), NuGetLogCode.NU5114));
                }

                ProjectProperties["SolutionDir"] = solutionDir;
            }
        }

        private string GetSolutionDir()
        {
            if (!string.IsNullOrEmpty(SolutionDirectory))
            {
                return SolutionDirectory;
            }
            return ProjectHelper.GetSolutionDir(_project.DirectoryPath);
        }

        private Packaging.Manifest ProcessNuspec(Packaging.PackageBuilder builder, string basePath)
        {
            string nuspecFile = GetNuspec();

            if (string.IsNullOrEmpty(nuspecFile))
            {
                return null;
            }

            Logger.Log(PackagingLogMessage.CreateMessage(string.Format(
                    CultureInfo.CurrentCulture,
                    LocalizedResourceManager.GetString("UsingNuspecForMetadata"),
                    Path.GetFileName(nuspecFile)), LogLevel.Minimal));

            using (Stream stream = File.OpenRead(nuspecFile))
            {
                // Don't validate the manifest since this might be a partial manifest
                // The bulk of the metadata might be coming from the project.
                Packaging.Manifest manifest = Packaging.Manifest.ReadFrom(stream, GetPropertyValue, validateSchema: true);
                builder.Populate(manifest.Metadata);

                if (manifest.HasFilesNode)
                {
                    basePath = string.IsNullOrEmpty(basePath) ? Path.GetDirectoryName(nuspecFile) : basePath;
                    builder.PopulateFiles(basePath, manifest.Files);
                }

                return manifest;
            }
        }

        private string GetNuspec()
        {
            return GetNuspecPaths().FirstOrDefault(File.Exists);
        }

        private IEnumerable<string> GetNuspecPaths()
        {
            // Check for a nuspec in the project file
            yield return GetContentOrNone(file => Path.GetExtension(file).Equals(NuGetConstants.ManifestExtension, StringComparison.OrdinalIgnoreCase));
            // Check for a nuspec named after the project
            yield return Path.Combine(_project.DirectoryPath, Path.GetFileNameWithoutExtension(_project.FullPath) + NuGetConstants.ManifestExtension);
        }

        private string GetContentOrNone(Func<string, bool> matcher)
        {
            return GetFiles("Content").Concat(GetFiles("None")).FirstOrDefault(matcher);
        }

        private IEnumerable<string> GetFiles(string itemType)
        {
            foreach (dynamic item in _project.GetItems(itemType))
            {
                // the type of item is ProjectItem
                var fullPath = item.GetMetadataValue("FullPath") as string;
                yield return fullPath;
            }
        }

        private void AddFiles(Packaging.PackageBuilder builder, string itemType, string targetFolder)
        {
            // Skip files that are added by dependency packages
            ProjectManagement.FolderNuGetProject project = new ProjectManagement.FolderNuGetProject(_project.FullPath);
            var referencesTask = project.GetInstalledPackagesAsync(new CancellationToken());
            referencesTask.Wait();
            var references = referencesTask.Result;

            string projectName = Path.GetFileNameWithoutExtension(_project.FullPath);

            var contentFilesInDependencies = new List<FrameworkSpecificGroup>();
            if (references.Any())
            {
                contentFilesInDependencies = references
                    .Select(reference => new PackageArchiveReader(project.GetInstalledPackageFilePath(reference.PackageIdentity)))
                    .SelectMany(a => a.GetContentItems())
                    .ToList();
            }

            // Get the content files from the project
            foreach (var item in _project.GetItems(itemType))
            {
                string fullPath = item.GetMetadataValue("FullPath");
                if (ExcludeFiles.Contains(Path.GetFileName(fullPath)))
                {
                    continue;
                }

                if (IncludeSymbols &&
                    SymbolPackageFormat == SymbolPackageFormat.Snupkg &&
                    !string.Equals(Path.GetExtension(fullPath), ".pdb", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                string targetFilePath = GetTargetPath(item);

                if (!File.Exists(fullPath))
                {
                    Logger.Log(PackagingLogMessage.CreateWarning(string.Format(
                            CultureInfo.CurrentCulture,
                            LocalizedResourceManager.GetString("Warning_FileDoesNotExist"),
                            targetFilePath), NuGetLogCode.NU5116));
                    continue;
                }

                // Skip target file paths containing msbuild variables since we do not offer a way to install files with variable paths.
                // These are show up in shared files found in universal apps.
                if (targetFilePath.IndexOf("$(MSBuild", StringComparison.OrdinalIgnoreCase) > -1)
                {
                    Logger.Log(PackagingLogMessage.CreateWarning(string.Format(
                            CultureInfo.CurrentCulture,
                            LocalizedResourceManager.GetString("Warning_UnresolvedFilePath"),
                            targetFilePath), NuGetLogCode.NU5117));
                    continue;
                }

                // if IncludeReferencedProjects is true and we are adding source files,
                // add projectName as part of the target to avoid file conflicts.
                string targetPath = IncludeReferencedProjects && itemType == SourcesItemType ?
                    Path.Combine(targetFolder, projectName, targetFilePath) :
                    Path.Combine(targetFolder, targetFilePath);

                // Check that file is added by dependency
                var targetFile = contentFilesInDependencies.SelectMany(f => f.Items).FirstOrDefault(a => a.Equals(targetPath, StringComparison.OrdinalIgnoreCase));
                if (targetFile != null)
                {
                    // Compare contents as well
                    var isEqual = ContentEquals(targetFile, fullPath);
                    if (isEqual)
                    {
                        Logger.Log(PackagingLogMessage.CreateMessage(string.Format(
                                CultureInfo.CurrentCulture,
                                LocalizedResourceManager.GetString("PackageCommandFileFromDependencyIsNotChanged"),
                                targetFilePath), LogLevel.Minimal));
                        continue;
                    }

                    Logger.Log(PackagingLogMessage.CreateMessage(string.Format(
                            CultureInfo.CurrentCulture,
                            LocalizedResourceManager.GetString("PackageCommandFileFromDependencyIsChanged"),
                            targetFilePath), LogLevel.Minimal));
                }

                var packageFile = new PhysicalPackageFile
                {
                    SourcePath = fullPath,
                    TargetPath = targetPath
                };
                AddFileToBuilder(builder, packageFile);
            }
        }

        private void AddFileToBuilder(PackageBuilder builder, PhysicalPackageFile packageFile)
        {
            if (!builder.Files.Any(p => packageFile.Path.Equals(p.Path, StringComparison.OrdinalIgnoreCase)))
            {
                WriteDetail(LocalizedResourceManager.GetString("AddFileToPackage"), packageFile.SourcePath, packageFile.TargetPath);
                builder.Files.Add(packageFile);
            }
            else
            {
                Logger.Log(PackagingLogMessage.CreateWarning(string.Format(
                        CultureInfo.CurrentCulture,
                        LocalizedResourceManager.GetString("FileNotAddedToPackage"),
                        packageFile.SourcePath,
                        packageFile.TargetPath), NuGetLogCode.NU5118));
            }
        }

        private void WriteDetail(string format, params object[] args)
        {
            if (LogLevel == LogLevel.Verbose)
            {
                Logger.Log(PackagingLogMessage.CreateMessage(string.Format(CultureInfo.CurrentCulture, format, args), LogLevel.Verbose));
            }
        }

        public static bool ContentEquals(string targetFile, string fullPath)
        {
            bool isEqual;
            using (var dependencyFileStream = File.OpenRead(targetFile))
            using (var fileContentStream = File.OpenRead(fullPath))
            {
                isEqual = StreamUtility.ContentEquals(dependencyFileStream, fileContentStream);
            }
            return isEqual;
        }

        private string GetTargetPath(dynamic item)
        {
            string path = item.EvaluatedInclude;
            if (item.HasMetadata("Link"))
            {
                path = item.GetMetadataValue("Link");
            }
            return Normalize(path);
        }

        private string Normalize(string path)
        {
            string projectDirectoryPath = PathUtility.EnsureTrailingSlash(_project.DirectoryPath);
            string fullPath = PathUtility.GetAbsolutePath(projectDirectoryPath, path);

            // If the file is under the project root then remove the project root
            if (fullPath.StartsWith(projectDirectoryPath, StringComparison.OrdinalIgnoreCase))
            {
                return fullPath.Substring(_project.DirectoryPath.Length).TrimStart(Path.DirectorySeparatorChar);
            }

            // Otherwise the file is probably a shortcut so just take the file name
            return Path.GetFileName(fullPath);
        }

        public void Dispose()
        {
            _msbuildAssemblyResolver.Dispose();
        }

        private class ReverseTransformFormFile : Packaging.IPackageFile
        {
            private readonly Lazy<Func<Stream>> _streamFactory;
            private readonly string _effectivePath;
            private DateTimeOffset _lastWriteTime = DateTimeOffset.UtcNow;

            public ReverseTransformFormFile(Packaging.IPackageFile file, IEnumerable<Packaging.IPackageFile> transforms)
            {
                Path = file.Path + ".transform";
                _streamFactory = new Lazy<Func<Stream>>(() => ReverseTransform(file, transforms), isThreadSafe: false);
                NuGetFramework = NuGet.Packaging.FrameworkNameUtility.ParseNuGetFrameworkFromFilePath(Path, out _effectivePath);
                if (NuGetFramework != null && NuGetFramework.Version.Major < 5)
                {
                    TargetFramework = new FrameworkName(NuGetFramework.DotNetFrameworkName);
                }
            }

            public string Path
            {
                get;
                private set;
            }

            public string EffectivePath
            {
                get
                {
                    return _effectivePath;
                }
            }

            public Stream GetStream()
            {
                return _streamFactory.Value();
            }

            public DateTimeOffset LastWriteTime
            {
                get
                {
                    return _lastWriteTime;
                }
            }

            [SuppressMessage("Microsoft.Reliability", "CA2000:Dispose objects before losing scope", Justification = "We need to return the MemoryStream for use.")]
            private static Func<Stream> ReverseTransform(Packaging.IPackageFile file, IEnumerable<Packaging.IPackageFile> transforms)
            {
                // Get the original
                XElement element = GetElement(file);

                // Remove all the transforms
                foreach (var transformFile in transforms)
                {
                    XElementExtensions.Except(element, GetElement(transformFile));
                }

                // Create the stream with the transformed content
                var ms = new MemoryStream();
                element.Save(ms);
                ms.Seek(0, SeekOrigin.Begin);
                byte[] buffer = ms.ToArray();
                return () => new MemoryStream(buffer);
            }

            private static XElement GetElement(Packaging.IPackageFile file)
            {
                using (Stream stream = file.GetStream())
                {
                    return XElement.Load(stream);
                }
            }

            public FrameworkName TargetFramework
            {
                get;
                private set;
            }

            public NuGetFramework NuGetFramework
            {
                get;
                private set;
            }
        }
    }
}
