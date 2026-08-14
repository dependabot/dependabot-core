// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

#nullable disable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NuGet.Commands;
using NuGet.Common;
using NuGet.Configuration;
using NuGet.PackageManagement;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.Packaging.PackageExtraction;
using NuGet.Packaging.Signing;
using NuGet.ProjectManagement;
using NuGet.Protocol.Core.Types;
using NuGet.Resolver;
using NuGet.Versioning;

namespace NuGet.CommandLine
{
    [Command(typeof(NuGetCommand), "update", "UpdateCommandDescription", UsageSummary = "<packages.config|solution|project>",
        UsageExampleResourceName = "UpdateCommandUsageExamples")]
    public class UpdateCommand : Command
    {
        [Option(typeof(NuGetCommand), "UpdateCommandSourceDescription")]
        public ICollection<string> Source { get; } = new List<string>();

        [Option(typeof(NuGetCommand), "UpdateCommandIdDescription")]
        public ICollection<string> Id { get; } = new List<string>();

        [Option(typeof(NuGetCommand), "UpdateCommandVersionDescription")]
        public string Version { get; set; }

        [Option(typeof(NuGetCommand), "UpdateCommandDependencyVersion")]
        public string DependencyVersion { get; set; }

        [Option(typeof(NuGetCommand), "UpdateCommandRepositoryPathDescription")]
        public string RepositoryPath { get; set; }

        [Option(typeof(NuGetCommand), "UpdateCommandSafeDescription")]
        public bool Safe { get; set; }

        [Option(typeof(NuGetCommand), "UpdateCommandSelfDescription")]
        public bool Self { get; set; }

        [Option(typeof(NuGetCommand), "UpdateCommandVerboseDescription")]
        public bool Verbose { get; set; }

        [Option(typeof(NuGetCommand), "UpdateCommandPrerelease")]
        public bool Prerelease { get; set; }

        [Option(typeof(NuGetCommand), "UpdateCommandFileConflictAction")]
        public ProjectManagement.FileConflictAction FileConflictAction { get; set; }

        [Option(typeof(NuGetCommand), "CommandMSBuildVersion")]
        public string MSBuildVersion { get; set; }

        [Option(typeof(NuGetCommand), "CommandMSBuildPath")]
        public string MSBuildPath { get; set; }

        // The directory that contains msbuild
        private string _msbuildDirectory;

        public override async Task ExecuteCommandAsync()
        {
            // update with self as parameter
            if (Self)
            {
                await UpdateSelfAsync();
                return;
            }

            string inputFile = GetInputFile();

            if (string.IsNullOrEmpty(inputFile))
            {
                throw new CommandException(NuGetResources.InvalidFile);
            }

            _msbuildDirectory = MsBuildUtility.GetMsBuildDirectoryFromMsBuildPath(MSBuildPath, MSBuildVersion, Console).Value.Path;
            var context = new UpdateConsoleProjectContext(Console, FileConflictAction);

            var logger = new LoggerAdapter(context);
            var clientPolicyContext = ClientPolicyContext.GetClientPolicy(Settings, logger);

            context.PackageExtractionContext = new PackageExtractionContext(
                PackageSaveMode.Defaultv2,
                PackageExtractionBehavior.XmlDocFileSaveMode,
                clientPolicyContext,
                logger);

            string inputFileName = Path.GetFileName(inputFile);
            // update with packages.config as parameter
            if (CommandLineUtility.IsValidConfigFileName(inputFileName))
            {
                await UpdatePackagesAsync(inputFile, context);
                return;
            }

            // update with project file as parameter
            if (ProjectHelper.SupportedProjectExtensions.Contains(Path.GetExtension(inputFile)))
            {
                if (!File.Exists(inputFile))
                {
                    throw new CommandException(NuGetResources.UnableToFindProject, inputFile);
                }

                var projectSystem = new MSBuildProjectSystem(
                    _msbuildDirectory,
                    inputFile,
                    context);
                await UpdatePackagesAsync(projectSystem, GetRepositoryPath(projectSystem.ProjectFullPath));
                return;
            }

            if (!File.Exists(inputFile))
            {
                throw new CommandException(NuGetResources.UnableToFindSolution, inputFile);
            }

            // update with solution as parameter
            string solutionDir = Path.GetDirectoryName(inputFile);
            await UpdateAllPackages(solutionDir, context);
        }

        private async Task UpdateSelfAsync()
        {
            PackageSource targetSource;
            switch (Source.Count)
            {
                case 0:
                    targetSource = new PackageSource(NuGetConstants.V3FeedUrl);
                    break;
                case 1:
                    // Use the package source from the load config to preload any creds that might be needed for authentication.
                    var availableSources = SourceProvider.LoadPackageSources().Where(source => source.IsEnabled);
                    targetSource = Common.PackageSourceProviderExtensions.ResolveSource(availableSources, Source.Single());
                    break;
                default:
                    throw new CommandException(NuGetResources.Error_UpdateSelf_Source);
            }
            var selfUpdater = new SelfUpdater(Console);
            await selfUpdater.UpdateSelfAsync(Prerelease, targetSource);
        }

        [System.Diagnostics.CodeAnalysis.SuppressMessage("Microsoft.Design", "CA1031:DoNotCatchGeneralExceptionTypes")]
        private async Task UpdateAllPackages(string solutionDir, INuGetProjectContext projectContext)
        {
            Console.WriteLine(LocalizedResourceManager.GetString("ScanningForProjects"));

            // Search recursively for all packages.xxx.config files
            string[] packagesConfigFiles = Directory.GetFiles(
                solutionDir, "*.config", SearchOption.AllDirectories);

            var projects = packagesConfigFiles.Where(s => Path.GetFileName(s).StartsWith("packages.", StringComparison.OrdinalIgnoreCase))
                                              .Select(s => GetProject(s, projectContext))
                                              .Where(p => p != null)
                                              .Distinct()
                                              .ToList();

            if (projects.Count == 0)
            {
                Console.WriteLine(LocalizedResourceManager.GetString("NoProjectsFound"));
                return;
            }

            if (projects.Count == 1)
            {
                Console.WriteLine(LocalizedResourceManager.GetString("FoundProject"), projects.Single().ProjectName);
            }
            else
            {
                Console.WriteLine(LocalizedResourceManager.GetString("FoundProjects"), projects.Count, String.Join(", ", projects.Select(p => p.ProjectName)));
            }

            string repositoryPath = GetRepositoryPathFromSolution(solutionDir);

            foreach (var project in projects)
            {
                try
                {
                    await UpdatePackagesAsync(project, repositoryPath);
                    if (Verbose)
                    {
                        Console.WriteLine();
                    }
                }
                catch (Exception e)
                {
                    if (Console.Verbosity == Verbosity.Detailed || ExceptionLogger.Instance.ShowStack)
                    {
                        Console.WriteWarning(e.ToString());
                    }
                    else
                    {
                        Console.WriteWarning(ExceptionUtilities.DisplayMessage(e));
                    }
                }
            }
        }

        private MSBuildProjectSystem GetProject(string path, INuGetProjectContext projectContext)
        {
            try
            {
                return GetMSBuildProject(path, projectContext);
            }
            catch (CommandException e)
            {
                if (Console.Verbosity == Verbosity.Detailed || ExceptionLogger.Instance.ShowStack)
                {
                    Console.WriteWarning(e.ToString());
                }
                else
                {
                    Console.WriteWarning(ExceptionUtilities.DisplayMessage(e));
                }
            }

            return null;
        }

        private string GetInputFile()
        {
            if (Arguments.Any())
            {
                string path = Arguments[0];
                string extension = Path.GetExtension(path) ?? string.Empty;

                if (extension.Equals(".config", StringComparison.OrdinalIgnoreCase))
                {
                    return GetPackagesConfigPath(path);
                }

                if (path.IsSolutionFile())
                {
                    return Path.GetFullPath(path);
                }

                if (ProjectHelper.SupportedProjectExtensions.Contains(extension))
                {
                    return Path.GetFullPath(path);
                }
            }

            return null;
        }

        private static string GetPackagesConfigPath(string path)
        {
            if (CommandLineUtility.IsValidConfigFileName(Path.GetFileName(path)))
            {
                return Path.GetFullPath(path);
            }

            return null;
        }

        private IReadOnlyCollection<PackageSource> GetPackageSources()
        {
            var availableSources = SourceProvider.LoadPackageSources().Where(source => source.IsEnabled).ToList();
            var packageSources = new List<PackageSource>();
            foreach (var source in Source)
            {
                packageSources.Add(Common.PackageSourceProviderExtensions.ResolveSource(availableSources, source));
            }

            if (packageSources.Count == 0)
            {
                packageSources.AddRange(availableSources);
            }

            return packageSources;
        }

        private Task UpdatePackagesAsync(string packagesConfigPath, INuGetProjectContext projectContext)
        {
            var project = GetMSBuildProject(packagesConfigPath, projectContext);
            var packagesDirectory = GetRepositoryPath(project.ProjectFullPath);
            return UpdatePackagesAsync(project, packagesDirectory);
        }

        private async Task UpdatePackagesAsync(MSBuildProjectSystem project, string packagesDirectory)
        {
            var sourceRepositoryProvider = GetSourceRepositoryProvider();
            var packageManager = new NuGetPackageManager(sourceRepositoryProvider, Settings, packagesDirectory);
            var nugetProject = new MSBuildNuGetProject(project, packagesDirectory, project.ProjectFullPath);
            if (!nugetProject.PackagesConfigNuGetProject.PackagesConfigExists())
            {
                throw new CommandException(LocalizedResourceManager.GetString("NoPackagesConfig"));
            }

            var versionConstraints = Safe ?
                VersionConstraints.ExactMajor | VersionConstraints.ExactMinor :
                VersionConstraints.None;

            var projectActions = new List<NuGetProjectAction>();

            using (var sourceCacheContext = new SourceCacheContext())
            {
                var dependencyBehavior = DependencyBehaviorHelper.GetDependencyBehavior(DependencyBehavior.Highest, DependencyVersion, Settings);
                var resolutionContext = new ResolutionContext(
                               dependencyBehavior,
                               Prerelease,
                               includeUnlisted: false,
                               versionConstraints: versionConstraints,
                               gatherCache: new GatherCache(),
                               sourceCacheContext: sourceCacheContext);

                var packageSources = GetPackageSources();

                Console.PrintPackageSources(packageSources);

                var sourceRepositories = packageSources.Select(sourceRepositoryProvider.CreateRepository);
                if (Id.Count > 0)
                {
                    var targetIds = new HashSet<string>(Id, StringComparer.OrdinalIgnoreCase);

                    var installed = await nugetProject.GetInstalledPackagesAsync(CancellationToken.None);

                    // If -Id has been specified and has exactly one package, use the explicit version requested
                    var targetVersion = Version != null && Id != null && Id.Count == 1 ? new NuGetVersion(Version) : null;

                    var targetIdentities = installed
                        .Select(pr => pr.PackageIdentity.Id)
                        .Where(id => targetIds.Contains(id))
                        .Select(id => new PackageIdentity(id, targetVersion))
                        .ToList();

                    if (targetIdentities.Any())
                    {
                        var actions = await packageManager.PreviewUpdatePackagesAsync(
                            targetIdentities,
                            new[] { nugetProject },
                            resolutionContext,
                            project.NuGetProjectContext,
                            sourceRepositories,
                            Enumerable.Empty<SourceRepository>(),
                            CancellationToken.None);

                        projectActions.AddRange(actions);
                    }
                }
                else
                {
                    var actions = await packageManager.PreviewUpdatePackagesAsync(
                            new[] { nugetProject },
                            resolutionContext,
                            project.NuGetProjectContext,
                            sourceRepositories,
                            Enumerable.Empty<SourceRepository>(),
                            CancellationToken.None);
                    projectActions.AddRange(actions);
                }

                await packageManager.ExecuteNuGetProjectActionsAsync(
                    nugetProject,
                    projectActions,
                    project.NuGetProjectContext,
                    sourceCacheContext,
                    CancellationToken.None);
            }

            project.Save();
        }

        private CommandLineSourceRepositoryProvider GetSourceRepositoryProvider()
        {
            var sourceRepositoryProvider = new CommandLineSourceRepositoryProvider(SourceProvider);
            return sourceRepositoryProvider;
        }

        private string GetRepositoryPath(string projectRoot)
        {
            string packagesDir = RepositoryPath;

            if (String.IsNullOrEmpty(packagesDir))
            {
                packagesDir = SettingsUtility.GetRepositoryPath(Settings);
                if (String.IsNullOrEmpty(packagesDir))
                {
                    // Try to resolve the packages directory from the project
                    string projectDir = Path.GetDirectoryName(projectRoot);
                    string solutionDir = ProjectHelper.GetSolutionDir(projectDir);

                    return GetRepositoryPathFromSolution(solutionDir);
                }
            }

            return GetPackagesDirectory(packagesDir);
        }

        private string GetRepositoryPathFromSolution(string solutionDir)
        {
            string packagesDir = RepositoryPath;

            if (String.IsNullOrEmpty(packagesDir))
            {
                // Try and get the packages folder from the nuget.config file otherwise full back to assuming it's <solution>\'packages'.
                packagesDir = SettingsUtility.GetRepositoryPath(Settings);
                if (String.IsNullOrEmpty(packagesDir) &&
                    !String.IsNullOrEmpty(solutionDir))
                {
                    packagesDir = Path.Combine(solutionDir, CommandLineConstants.PackagesDirectoryName);
                }
            }

            return GetPackagesDirectory(packagesDir);
        }

        private string GetPackagesDirectory(string packagesDir)
        {
            if (!String.IsNullOrEmpty(packagesDir))
            {
                // Get the full path to the packages directory
                packagesDir = Path.GetFullPath(packagesDir);

                // REVIEW: Do we need to check for existence?
                if (Directory.Exists(packagesDir))
                {
                    string relativePath =
                        PathUtility.GetRelativePath(
                            PathUtility.EnsureTrailingSlash(CurrentDirectory), packagesDir);
                    Console.LogVerbose(
                        string.Format(
                            CultureInfo.CurrentCulture,
                            LocalizedResourceManager.GetString("LookingForInstalledPackages"),
                            relativePath));
                    return packagesDir;
                }
            }

            throw new CommandException(LocalizedResourceManager.GetString("UnableToLocatePackagesFolder"));
        }

        private MSBuildProjectSystem GetMSBuildProject(string packageReferenceFilePath, INuGetProjectContext projectContext)
        {
            // Try to locate the project file associated with this packages.config file
            var directory = Path.GetDirectoryName(packageReferenceFilePath);
            var projectFiles = ProjectHelper.GetProjectFiles(directory).Take(2).ToArray();

            if (projectFiles.Length == 0)
            {
                throw new CommandException(LocalizedResourceManager.GetString("UnableToLocateProjectFile"), packageReferenceFilePath);
            }

            if (projectFiles.Length > 1)
            {
                throw new CommandException(LocalizedResourceManager.GetString("MultipleProjectFilesFound"), packageReferenceFilePath);
            }

            return new MSBuildProjectSystem(_msbuildDirectory, projectFiles[0], projectContext);
        }


        private class UpdateConsoleProjectContext : ConsoleProjectContext
        {
            private readonly IConsole _console;
            private readonly ProjectManagement.FileConflictAction FileConflictAction;
            private bool _overwriteAll;
            private bool _ignoreAll;

            public UpdateConsoleProjectContext(
                IConsole console,
                ProjectManagement.FileConflictAction conflictAction)
                : base(console)
            {
                _console = console;
                FileConflictAction = conflictAction;
            }

            public override ProjectManagement.FileConflictAction ResolveFileConflict(string message)
            {
                // the -FileConflictAction is set to Overwrite or user has chosen Overwrite All previously
                if (FileConflictAction == ProjectManagement.FileConflictAction.Overwrite || _overwriteAll)
                {
                    return ProjectManagement.FileConflictAction.Overwrite;
                }

                // the -FileConflictAction is set to Ignore or user has chosen Ignore All previously
                if (FileConflictAction == ProjectManagement.FileConflictAction.Ignore || _ignoreAll)
                {
                    return ProjectManagement.FileConflictAction.Ignore;
                }

                // otherwise, prompt user for choice, unless we're in non-interactive mode
                if (_console != null && !_console.IsNonInteractive)
                {
                    var resolution = GetUserInput(message);
                    _overwriteAll = resolution == ProjectManagement.FileConflictAction.OverwriteAll;
                    _ignoreAll = resolution == ProjectManagement.FileConflictAction.IgnoreAll;
                    return resolution;
                }

                return ProjectManagement.FileConflictAction.Ignore;
            }

            private ProjectManagement.FileConflictAction GetUserInput(string message)
            {
                // make the question stand out from previous text
                _console.WriteLine();

                _console.WriteLine(ConsoleColor.Yellow, "File Conflict.");
                _console.WriteLine(message);

                // Yes - Yes To All - No - No To All
                var acceptedAnswers = new List<string> { "Y", "A", "N", "L" };
                var choices = new[]
                {
                    ProjectManagement.FileConflictAction.Overwrite,
                    ProjectManagement.FileConflictAction.OverwriteAll,
                    ProjectManagement.FileConflictAction.Ignore,
                    ProjectManagement.FileConflictAction.IgnoreAll
                };

                while (true)
                {
                    _console.Write(LocalizedResourceManager.GetString("FileConflictChoiceText"));
                    string answer = _console.ReadLine();
                    if (!String.IsNullOrEmpty(answer))
                    {
                        int index = acceptedAnswers.FindIndex(a => a.Equals(answer, StringComparison.OrdinalIgnoreCase));
                        if (index > -1)
                        {
                            return choices[index];
                        }
                    }
                }
            }
        }
    }
}
