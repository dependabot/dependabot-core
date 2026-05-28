// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

#nullable disable

using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.ComponentModel.Composition.Hosting;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Text;
using Microsoft.Win32;
using NuGet.Common;
using NuGet.PackageManagement;

namespace NuGet.CommandLine
{
    public class Program
    {
        private const string Utf8Option = "-utf8";
        private const string ForceEnglishOutputOption = "-forceEnglishOutput";
#if DEBUG
        private const string DebugOption = "--debug";
#endif
        private const string OSVersionRegistryKey = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion";
        private const string FilesystemRegistryKey = @"SYSTEM\CurrentControlSet\Control\FileSystem";
        private const string DotNetSetupRegistryKey = @"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\";
        private const int Net462ReleasedVersion = 394802;

        internal static readonly Assembly NuGetExeAssembly = typeof(Program).Assembly;
        private static readonly string ThisExecutableName = NuGetExeAssembly.GetName().Name;

        [Import]
        public HelpCommand HelpCommand { get; set; }

        [ImportMany]
        public IEnumerable<ICommand> Commands { get; set; }

        [Import]
        public ICommandManager Manager { get; set; }

        /// <summary>
        /// Flag meant for unit tests that prevents command line extensions from being loaded.
        /// </summary>
        public static bool IgnoreExtensions { get; set; }

        public static int Main(string[] args)
        {
            AppContext.SetSwitch("Switch.System.IO.UseLegacyPathHandling", false);
            AppContext.SetSwitch("Switch.System.IO.BlockLongPaths", false);

#if DEBUG
            if (args.Contains(DebugOption, StringComparer.OrdinalIgnoreCase))
            {
                args = args.Where(arg => !string.Equals(arg, DebugOption, StringComparison.OrdinalIgnoreCase)).ToArray();
                System.Diagnostics.Debugger.Launch();
            }
#endif

            NuGet.Common.Migrations.MigrationRunner.Run();

#if IS_DESKTOP
            // Find any response files and resolve the args
            if (!RuntimeEnvironmentHelper.IsMono)
            {
                args = CommandLineResponseFile.ParseArgsResponseFiles(args);
            }
#endif
            return MainCore(Directory.GetCurrentDirectory(), args, EnvironmentVariableWrapper.Instance);
        }

        public static int MainCore(string workingDirectory, string[] args, IEnvironmentVariableReader environmentVariableReader)
        {
            var console = new Console();

            // First, optionally disable localization in resources.
            if (args.Any(arg => string.Equals(arg, ForceEnglishOutputOption, StringComparison.OrdinalIgnoreCase)))
            {
                CultureUtility.DisableLocalization();
            }
            else
            {
                UILanguageOverride.Setup(console);
            }

            // set output encoding to UTF8 if -utf8 is specified
            var oldOutputEncoding = System.Console.OutputEncoding;
            if (args.Any(arg => string.Equals(arg, Utf8Option, StringComparison.OrdinalIgnoreCase)))
            {
                args = args.Where(arg => !string.Equals(arg, Utf8Option, StringComparison.OrdinalIgnoreCase)).ToArray();
                SetConsoleOutputEncoding(Encoding.UTF8);
            }

            // Increase the maximum number of connections per server.
            if (!RuntimeEnvironmentHelper.IsMono)
            {
                ServicePointManager.DefaultConnectionLimit = 64;
            }
            else
            {
                // Keep mono limited to a single download to avoid issues.
                ServicePointManager.DefaultConnectionLimit = 1;
            }

            try
            {
                // Remove NuGet.exe.old
                RemoveOldFile();

                // Import Dependencies
                var p = new Program();
                p.Initialize(console);

                // Add commands to the manager
                foreach (var cmd in p.Commands)
                {
                    p.Manager.RegisterCommand(cmd);
                }

                var parser = new CommandLineParser(p.Manager);

                // Parse the command
                var command = parser.ParseCommandLine(args) ?? p.HelpCommand;
                command.CurrentDirectory = workingDirectory;
                if (command is DownloadCommandBase downloadCommandBase && downloadCommandBase.NoCache)
                {
                    // NoCache option is deprecated. Users should use NoHttpCache instead.
                    console.LogInformation(NuGetCommand.Log_RestoreNoCacheInformation);
                }

                if (command is Command commandImpl)
                {
                    console.Verbosity = commandImpl.Verbosity;
                }

                // Fallback on the help command if we failed to parse a valid command
                if (!ArgumentCountValid(command))
                {
                    // Get the command name and add it to the argument list of the help command
                    var commandName = command.CommandAttribute.CommandName;

                    // Print invalid arguments command error message in stderr
                    console.WriteError(LocalizedResourceManager.GetString("InvalidArguments"), commandName);

                    // then show help
                    p.HelpCommand.ViewHelpForCommand(commandName);

                    return 1;
                }
                else
                {
                    if (command is Command baseCommand)
                    {
                        SetConsoleInteractivity(console, baseCommand, environmentVariableReader);
                    }

                    try
                    {
                        command.Execute();
                    }
                    catch (CommandLineArgumentCombinationException e)
                    {
                        var commandName = command.CommandAttribute.CommandName;

                        console.WriteLine($"{string.Format(CultureInfo.CurrentCulture, LocalizedResourceManager.GetString("InvalidArguments"), commandName)} {e.Message}");

                        p.HelpCommand.ViewHelpForCommand(commandName);

                        return 1;
                    }
                }
            }
            catch (AggregateException exception)
            {
                var unwrappedEx = ExceptionUtility.Unwrap(exception);

                LogException(unwrappedEx, console);
                return 1;
            }
            catch (ExitCodeException e)
            {
                return e.ExitCode;
            }
            catch (PathTooLongException e)
            {
                LogException(e, console);
                if (RuntimeEnvironmentHelper.IsWindows)
                {
                    LogHelperMessageForPathTooLongException(console);
                }
                return 1;
            }
            catch (Exception exception)
            {
                LogException(exception, console);
                return 1;
            }
            finally
            {
                SetConsoleOutputEncoding(oldOutputEncoding);
            }

            return 0;
        }

        private void Initialize(IConsole console)
        {
            AppDomain.CurrentDomain.AssemblyResolve += CurrentDomain_AssemblyResolve;
            AppDomain.CurrentDomain.ResourceResolve += CurrentDomain_ResourceResolve;

            using (var catalog = new AggregateCatalog(new AssemblyCatalog(GetType().Assembly)))
            {
                if (!IgnoreExtensions)
                {
                    AddExtensionsToCatalog(catalog, console);
                }

                try
                {
                    using (var container = new CompositionContainer(catalog))
                    {
                        container.ComposeExportedValue(console);
                        container.ComposeParts(this);
                    }
                }
                catch (ReflectionTypeLoadException ex) when (ex?.LoaderExceptions.Length > 0)
                {
                    throw new AggregateException(ex.LoaderExceptions);
                }
            }
        }

        private Assembly CurrentDomain_ResourceResolve(object sender, ResolveEventArgs args)
        {
            Assembly returnedResource = null;

            // We want to intercept NuGet.Resources resources and redirect it to nuget.exe assembly
            if (!args.Name.StartsWith("NuGet.CommandLine", StringComparison.OrdinalIgnoreCase) && args.Name.StartsWith("NuGet", StringComparison.OrdinalIgnoreCase) && string.Equals("NuGet.Resources", args.RequestingAssembly.GetName().Name, StringComparison.OrdinalIgnoreCase))
            {
                ManifestResourceInfo resource = NuGetExeAssembly.GetManifestResourceInfo(args.Name);
                if (resource != null)
                {
                    // Return nuget.exe assembly, since it contains the requested resource by NuGet.Resources assembly
                    returnedResource = NuGetExeAssembly;
                }
            }

            return returnedResource;
        }

        // This method acts as a binding redirect
        private Assembly CurrentDomain_AssemblyResolve(object sender, ResolveEventArgs args)
        {
            AssemblyName name = new AssemblyName(args.Name);
            Assembly customLoadedAssembly = null;

            if (string.Equals(name.Name, ThisExecutableName, StringComparison.OrdinalIgnoreCase))
            {
                customLoadedAssembly = NuGetExeAssembly;
            }
            // .NET Framework 4.x now triggers AssemblyResolve event for resource assemblies
            // We want to catch failed NuGet.resources.dll assembly load to look for it in embedded resources
            else if (name.Name == "NuGet.resources")
            {
                // Load satellite resource assembly from embedded resources
                customLoadedAssembly = GetNuGetResourcesAssembly(name.Name, name.CultureInfo);
            }

            return customLoadedAssembly;
        }

        private static Assembly GetNuGetResourcesAssembly(string name, CultureInfo culture)
        {
            string resourceName = $"NuGet.CommandLine.{culture.Name}.{name}.dll";
            Assembly resourceAssembly = LoadAssemblyFromEmbeddedResources(resourceName);
            if (resourceAssembly == null)
            {
                // Sometimes, embedded assembly names have dashes replaced by underscores
                string altResourceName = $"NuGet.CommandLine.{culture.Name.Replace("-", "_")}.{name}.dll";
                resourceAssembly = LoadAssemblyFromEmbeddedResources(altResourceName);
            }

            return resourceAssembly;
        }

        private static Assembly LoadAssemblyFromEmbeddedResources(string resourceName)
        {
            Assembly resourceAssembly = null;
            using (var stream = NuGetExeAssembly.GetManifestResourceStream(resourceName))
            {
                if (stream != null)
                {
                    byte[] assemblyData = new byte[stream.Length];
                    stream.Read(assemblyData, offset: 0, assemblyData.Length);
                    try
                    {
                        resourceAssembly = Assembly.Load(assemblyData);
                    }
                    catch (BadImageFormatException)
                    {
                        resourceAssembly = null;
                    }
                }
            }

            return resourceAssembly;
        }

        [SuppressMessage("Microsoft.Design", "CA1031:DoNotCatchGeneralExceptionTypes", Justification = "We don't want to block the exe from usage if anything failed")]
        internal static void RemoveOldFile()
        {
            var oldFile = NuGetExeAssembly.Location + ".old";
            try
            {
                if (File.Exists(oldFile))
                {
                    File.Delete(oldFile);
                }
            }
            catch
            {
                // We don't want to block the exe from usage if anything failed
            }
        }

        public static bool ArgumentCountValid(ICommand command)
        {
            var attribute = command.CommandAttribute;
            return command.Arguments.Count >= attribute.MinArgs &&
                   command.Arguments.Count <= attribute.MaxArgs;
        }

        private static void AddExtensionsToCatalog(AggregateCatalog catalog, IConsole console)
        {
            var extensionLocator = new ExtensionLocator();
            var files = extensionLocator.FindExtensions();
            RegisterExtensions(catalog, files, console);
        }

        private static void RegisterExtensions(AggregateCatalog catalog, IEnumerable<string> enumerateFiles, IConsole console)
        {
            foreach (var item in enumerateFiles)
            {
                AssemblyCatalog assemblyCatalog = null;
                try
                {
                    assemblyCatalog = new AssemblyCatalog(item);

                    // get the parts - throw if something went wrong
                    var parts = assemblyCatalog.Parts;

                    // load all the types - throw if assembly cannot load (missing dependencies is a good example)
                    var assembly = Assembly.LoadFile(item);
                    assembly.GetTypes();

                    catalog.Catalogs.Add(assemblyCatalog);
                }
                catch (BadImageFormatException ex)
                {
                    if (assemblyCatalog != null)
                    {
                        assemblyCatalog.Dispose();
                    }

                    // Ignore if the dll wasn't a valid assembly
                    console.WriteWarning(ex.Message);
                }
                catch (FileLoadException ex)
                {
                    // Ignore if we couldn't load the assembly.

                    if (assemblyCatalog != null)
                    {
                        assemblyCatalog.Dispose();
                    }

                    var message =
                        string.Format(CultureInfo.CurrentCulture, LocalizedResourceManager.GetString(nameof(NuGetResources.FailedToLoadExtension)),
                                      item);

                    console.WriteWarning(message);
                    console.WriteWarning(ex.Message);
                }
                catch (ReflectionTypeLoadException rex)
                {
                    // ignore if the assembly is missing dependencies

                    var resource =
                        LocalizedResourceManager.GetString(nameof(NuGetResources.FailedToLoadExtensionDuringMefComposition));

                    var perAssemblyError = string.Empty;

                    if (rex?.LoaderExceptions.Length > 0)
                    {
                        var builder = new StringBuilder();

                        builder.AppendLine(string.Empty);

                        var errors = rex.LoaderExceptions.Select(e => e.Message).Distinct(StringComparer.Ordinal);

                        foreach (var error in errors)
                        {
                            builder.AppendLine(error);
                        }

                        perAssemblyError = builder.ToString();
                    }

                    var warning = string.Format(CultureInfo.CurrentCulture, resource, item, perAssemblyError);

                    console.WriteWarning(warning);
                }
            }
        }

        private static void SetConsoleInteractivity(IConsole console, Command command, IEnvironmentVariableReader environmentVariableReader)
        {
            // Apply command setting
            console.IsNonInteractive = command.NonInteractive;

            // Global environment variable to prevent the exe for prompting for credentials
            if (!string.IsNullOrEmpty(environmentVariableReader.GetEnvironmentVariable("NUGET_EXE_NO_PROMPT")))
            {
                console.IsNonInteractive = true;
            }

            // Disable non-interactive if force is set.
            var forceInteractive = environmentVariableReader.GetEnvironmentVariable("FORCE_NUGET_EXE_INTERACTIVE");
            if (!string.IsNullOrEmpty(forceInteractive))
            {
                console.IsNonInteractive = false;
            }
        }

        private static void SetConsoleOutputEncoding(System.Text.Encoding encoding)
        {
            try
            {
                System.Console.OutputEncoding = encoding;
            }
            catch (IOException)
            {
            }
        }

        private static void LogException(Exception exception, IConsole console)
        {
            var logStackAsError = console.Verbosity == Verbosity.Detailed;

            ExceptionUtilities.LogException(exception, console, logStackAsError);
        }

        private static void LogHelperMessageForPathTooLongException(Console logger)
        {
            if (!IsWindows10(logger))
            {
                logger.WriteWarning(LocalizedResourceManager.GetString(nameof(NuGetResources.Warning_LongPath_UnsupportedOS)));
            }
            else if (!IsSupportLongPathEnabled(logger))
            {
                logger.WriteWarning(LocalizedResourceManager.GetString(nameof(NuGetResources.Warning_LongPath_DisabledPolicy)));
            }
            else if (!IsRuntimeGreaterThanNet462(logger))
            {
                logger.WriteWarning(LocalizedResourceManager.GetString(nameof(NuGetResources.Warning_LongPath_UnsupportedNetFramework)));
            }
        }

        private static bool IsWindows10(ILogger logger)
        {
            var productName = (string)RegistryKeyUtility.GetValueFromRegistryKey("ProductName", OSVersionRegistryKey, Registry.LocalMachine, logger);

            return productName != null && productName.StartsWith("Windows 10", StringComparison.Ordinal);
        }

        private static bool IsSupportLongPathEnabled(ILogger logger)
        {
            var longPathsEnabled = RegistryKeyUtility.GetValueFromRegistryKey("LongPathsEnabled", FilesystemRegistryKey, Registry.LocalMachine, logger);

            return longPathsEnabled != null && (int)longPathsEnabled > 0;
        }

        private static bool IsRuntimeGreaterThanNet462(ILogger logger)
        {
            var release = RegistryKeyUtility.GetValueFromRegistryKey("Release", DotNetSetupRegistryKey, Registry.LocalMachine, logger);

            return release != null && (int)release >= Net462ReleasedVersion;
        }
    }
}
