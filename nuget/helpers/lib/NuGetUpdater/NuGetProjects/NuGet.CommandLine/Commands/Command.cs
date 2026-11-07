// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.
#nullable disable

using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using NuGet.Common;
using NuGet.Credentials;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Protocol.Plugins;

namespace NuGet.CommandLine
{
    public abstract class Command : ICommand
    {
        private const string CommandSuffix = "Command";
        private CommandAttribute _commandAttribute;
        private string _currentDirectory;

        protected Command()
        {
            Arguments = new List<string>();
        }

        public IList<string> Arguments { get; private set; }

        [Import]
        public IConsole Console { get; set; }

        [Import]
        public HelpCommand HelpCommand { get; set; }

        [Import]
        public ICommandManager Manager { get; set; }

        [Import]
        public Configuration.IMachineWideSettings MachineWideSettings { get; set; }

        [Option(typeof(NuGetCommand), "Option_Help", AltName = "?")]
        public bool Help { get; set; }

        [Option(typeof(NuGetCommand), "Option_Verbosity")]
        public Verbosity Verbosity { get; set; }

        [Option(typeof(NuGetCommand), "Option_NonInteractive")]
        public bool NonInteractive { get; set; }

        [Option(typeof(NuGetCommand), "Option_ConfigFile")]
        public string ConfigFile { get; set; }

        [Option(typeof(NuGetCommand), "Option_ForceEnglishOutput")]
        public bool ForceEnglishOutput { get; set; }

        protected Configuration.ICredentialService CredentialService { get; private set; }

        public DeprecatedCommandAttribute DeprecatedCommandAttribute
        {
            get
            {
                var deprecatedAttrs = GetType().GetCustomAttributes(typeof(DeprecatedCommandAttribute), false);

                if (deprecatedAttrs.Length > 0)
                {
                    return deprecatedAttrs[0] as DeprecatedCommandAttribute;
                }

                return null;
            }
        }

        public string CurrentDirectory
        {
            get
            {
                return _currentDirectory ?? Directory.GetCurrentDirectory();
            }
            set
            {
                _currentDirectory = value;
            }
        }

        protected internal Configuration.ISettings Settings { get; set; }

        protected internal Configuration.IPackageSourceProvider SourceProvider { get; set; }

        private Lazy<MsBuildToolset> MsBuildToolset
        {
            get
            {
                if (_defaultMsBuildToolset == null)
                {
                    _defaultMsBuildToolset = MsBuildUtility.GetMsBuildDirectoryFromMsBuildPath(null, null, Console);

                }
                return _defaultMsBuildToolset;
            }
        }

        private Lazy<MsBuildToolset> _defaultMsBuildToolset;

        public CommandAttribute CommandAttribute
        {
            get
            {
                if (_commandAttribute == null)
                {
                    _commandAttribute = GetCommandAttribute();
                }
                return _commandAttribute;
            }
        }

        public virtual bool IncludedInHelp(string optionName)
        {
            return true;
        }

        public void Execute()
        {
            if (Help)
            {
                if (DeprecatedCommandAttribute != null)
                {
                    var deprecationMessage = DeprecatedCommandAttribute.GetDeprecationMessage(CommandAttribute.CommandName);
                    Console.WriteWarning(deprecationMessage);
                }

                HelpCommand.ViewHelpForCommand(CommandAttribute.CommandName);
            }
            else
            {
                if (string.IsNullOrEmpty(ConfigFile))
                {
                    string configFileName = null;

                    var packCommand = this as PackCommand;
                    if (packCommand != null && !string.IsNullOrEmpty(packCommand.ConfigFile))
                    {
                        configFileName = packCommand.ConfigFile;
                    }

                    Settings = Configuration.Settings.LoadDefaultSettings(
                        CurrentDirectory,
                        configFileName: configFileName,
                        machineWideSettings: MachineWideSettings);
                }
                else
                {
                    var configFileFullPath = Path.GetFullPath(ConfigFile);
                    var directory = Path.GetDirectoryName(configFileFullPath);
                    var configFileName = Path.GetFileName(configFileFullPath);
                    Settings = Configuration.Settings.LoadDefaultSettings(
                        directory,
                        configFileName,
                        MachineWideSettings);
                }

                SourceProvider = PackageSourceBuilder.CreateSourceProvider(Settings);

                SetDefaultCredentialProvider();

                UserAgent.SetUserAgentString(new UserAgentStringBuilder(CommandLineConstants.UserAgent));

                if (DeprecatedCommandAttribute != null)
                {
                    var deprecationMessage = DeprecatedCommandAttribute.GetDeprecationMessage(CommandAttribute.CommandName);
                    Console.WriteWarning(deprecationMessage);
                }

                OutputNuGetVersion();
                ExecuteCommandAsync().GetAwaiter().GetResult();
            }
        }

        /// <summary>
        /// Outputs the current NuGet version (by default, only when vebosity is detailed).
        /// </summary>
        private void OutputNuGetVersion()
        {
            if (ShouldOutputNuGetVersion)
            {
                var assemblyName = typeof(Command).Assembly.GetName();
                var assemblyLocation = typeof(Command).Assembly.Location;
                var version = System.Diagnostics.FileVersionInfo.GetVersionInfo(assemblyLocation).FileVersion;
                var message = string.Format(
                    CultureInfo.CurrentCulture,
                    LocalizedResourceManager.GetString("OutputNuGetVersion"),
                    assemblyName.Name,
                    version);
                Console.WriteLine(message);
            }
        }

        protected virtual bool ShouldOutputNuGetVersion
        {
            get { return Console.Verbosity == Verbosity.Detailed; }
        }

        protected virtual void SetDefaultCredentialProvider()
        {
            SetDefaultCredentialProvider(MsBuildToolset);
        }

        /// <summary>
        /// Set default credential provider for the HttpClient, which is used by V2 sources.
        /// Also set up authenticated proxy handling for V3 sources.
        /// </summary>
        protected void SetDefaultCredentialProvider(Lazy<MsBuildToolset> msbuildDirectory)
        {
            PluginDiscoveryUtility.InternalPluginDiscoveryRoot = new Lazy<string>(() => PluginDiscoveryUtility.GetInternalPluginRelativeToMSBuildDirectory(msbuildDirectory.Value.Path));
            CredentialService = new CredentialService(new AsyncLazy<IEnumerable<ICredentialProvider>>(() => GetCredentialProvidersAsync()), NonInteractive, handlesDefaultCredentials: PreviewFeatureSettings.DefaultCredentialsAfterCredentialProviders);

            HttpHandlerResourceV3.CredentialService = new Lazy<Configuration.ICredentialService>(() => CredentialService);

            HttpHandlerResourceV3.CredentialsSuccessfullyUsed = (uri, credentials) =>
            {
            };
        }

        private async Task<IEnumerable<ICredentialProvider>> GetCredentialProvidersAsync()
        {
            var extensionLocator = new ExtensionLocator();
            var providers = new List<ICredentialProvider>();
            var pluginProviders = new PluginCredentialProviderBuilder(extensionLocator, Settings, Console)
                .BuildAll(Verbosity.ToString())
                .ToList();
            var securePluginProviders = await (new SecurePluginCredentialProviderBuilder(PluginManager.Instance, canShowDialog: true, logger: Console)).BuildAllAsync();

            providers.Add(new SettingsCredentialProvider(SourceProvider, Console));
            providers.AddRange(securePluginProviders);
            providers.AddRange(pluginProviders);

            if (pluginProviders.Any() || securePluginProviders.Any())
            {
                if (PreviewFeatureSettings.DefaultCredentialsAfterCredentialProviders)
                {
                    providers.Add(new DefaultNetworkCredentialsCredentialProvider());
                }
            }
            providers.Add(new ConsoleCredentialProvider(Console));

            return providers;
        }

        public virtual Task ExecuteCommandAsync()
        {
            ExecuteCommand();
            return Task.CompletedTask;
        }

        public virtual void ExecuteCommand()
        {
        }

        [SuppressMessage("Microsoft.Design", "CA1024:UsePropertiesWhereAppropriate", Justification = "This method does quite a bit of processing.")]
        public virtual CommandAttribute GetCommandAttribute()
        {
            var type = GetType();
            var attributes = type.GetCustomAttributes(typeof(CommandAttribute), true);
            var attribute = attributes.FirstOrDefault();
            if (attribute != null)
            {
                return (CommandAttribute)attribute;
            }

            // Use the command name minus the suffix if present and default description
            var name = type.Name;
            var idx = name.LastIndexOf(CommandSuffix, StringComparison.OrdinalIgnoreCase);
            if (idx >= 0)
            {
                name = name.Substring(0, idx);
            }
            if (!string.IsNullOrEmpty(name))
            {
                return new CommandAttribute(name, LocalizedResourceManager.GetString("DefaultCommandDescription"));
            }
            return null;
        }
    }
}
