// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;

using NuGet.Common;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.Versioning;

namespace NuGet.CommandLine
{
    internal sealed class AssemblyMetadataExtractor
    {
        private readonly ILogger _logger;

        public AssemblyMetadataExtractor(ILogger logger) => _logger = logger ?? NullLogger.Instance;

        private static T CreateInstance<T>(AppDomain domain)
        {
            string assemblyLocation = Assembly.GetExecutingAssembly().Location;

            try
            {
                return (T)domain.CreateInstanceFromAndUnwrap(assemblyLocation, typeof(T).FullName);
            }
            catch (FileLoadException flex) when (UriUtility.GetLocalPath(flex.FileName).Equals(assemblyLocation, StringComparison.Ordinal))
            {
                // Reflection loading error for sandboxed assembly
                var exceptionMessage = string.Format(
                    CultureInfo.InvariantCulture,
                    LocalizedResourceManager.GetString("Error_NuGetExeNeedsToBeUnblockedAfterDownloading"),
                    UriUtility.GetLocalPath(flex.FileName));
                throw new PackagingException(NuGetLogCode.NU5133, exceptionMessage, flex);
            }
        }

        public AssemblyMetadata GetMetadata(string assemblyPath)
        {
            return new AssemblyMetadata();
        }

        public void ExtractMetadata(PackageBuilder builder, string assemblyPath)
        {
            AssemblyMetadata assemblyMetadata = GetMetadata(assemblyPath);
            builder.Title = assemblyMetadata.Title;
            builder.Description = assemblyMetadata.Description;
            builder.Copyright = assemblyMetadata.Copyright;

            // using InformationalVersion if possible, fallback to Version otherwise
            if (NuGetVersion.TryParse(assemblyMetadata.InformationalVersion, out var informationalVersion))
            {
                builder.Version = informationalVersion;
            }
            else
            {
                _logger.LogInformation(string.Format(
                    CultureInfo.CurrentCulture, NuGetResources.InvalidAssemblyInformationalVersion,
                    assemblyMetadata.InformationalVersion, assemblyPath, assemblyMetadata.Version));

                builder.Version = NuGetVersion.Parse(assemblyMetadata.Version);
            }

            if (!builder.Authors.Any())
            {
                if (assemblyMetadata.Properties.ContainsKey("authors"))
                {
                    builder.Authors.AddRange(assemblyMetadata.Properties["authors"].Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries));
                }
                else if (!string.IsNullOrEmpty(assemblyMetadata.Company))
                {
                    builder.Authors.Add(assemblyMetadata.Company);
                }
            }

            if (assemblyMetadata.Properties.ContainsKey("owners"))
            {
                builder.Owners.AddRange(assemblyMetadata.Properties["owners"].Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries));
            }

            builder.Properties.AddRange(assemblyMetadata.Properties);
            // Let the id be overridden by AssemblyMetadataAttribute
            // This preserves the existing behavior if no id metadata 
            // is provided by the assembly.
            if (builder.Properties.ContainsKey("id"))
            {
                builder.Id = builder.Properties["id"];
            }
            else
            {
                builder.Id = assemblyMetadata.Name;
            }
        }

        private sealed class MetadataExtractor : MarshalByRefObject
        {
            private class AssemblyResolver
            {
                private readonly string _lookupPath;

                public AssemblyResolver(string assemblyPath)
                {
                    _lookupPath = Path.GetDirectoryName(assemblyPath);
                }

                public Assembly ReflectionOnlyAssemblyResolve(object sender, ResolveEventArgs args)
                {
                    var name = new AssemblyName(AppDomain.CurrentDomain.ApplyPolicy(args.Name));
                    var assemblyPath = Path.Combine(_lookupPath, name.Name + ".dll");
                    return File.Exists(assemblyPath) ?
                        Assembly.ReflectionOnlyLoadFrom(assemblyPath) : // load from same folder as parent assembly
                        Assembly.ReflectionOnlyLoad(name.FullName);     // load from GAC
                }
            }

            [SuppressMessage("Microsoft.Performance", "CA1822:MarkMembersAsStatic", Justification = "It's a marshal by ref object used to collection information in another app domain")]
            public AssemblyMetadata GetAssemblyMetadata(string path)
            {
                var resolver = new AssemblyResolver(path);
                AppDomain.CurrentDomain.ReflectionOnlyAssemblyResolve += resolver.ReflectionOnlyAssemblyResolve;

                try
                {
                    Assembly assembly = Assembly.ReflectionOnlyLoadFrom(path);
                    AssemblyName assemblyName = assembly.GetName();

                    var attributes = CustomAttributeData.GetCustomAttributes(assembly);

                    // We should not try to parse the version and eventually throw here: this leads to incorrect errors when, later on, ProjectFactory is trying to retrieve Authors and Description
                    // Best to parse the version into a NuGetVersion later.
                    // We should also not decide here whether to use informationalVersion or assembly version. Let's let consumers decide.
                    var version = assemblyName.Version.ToString();
                    var informationalVersion = GetAttributeValueOrDefault<AssemblyInformationalVersionAttribute>(attributes);
                    informationalVersion = string.IsNullOrEmpty(informationalVersion) ? version : informationalVersion;

                    return new AssemblyMetadata(GetProperties(attributes))
                    {
                        Name = assemblyName.Name,
                        Version = version,
                        InformationalVersion = informationalVersion,
                        Title = GetAttributeValueOrDefault<AssemblyTitleAttribute>(attributes),
                        Company = GetAttributeValueOrDefault<AssemblyCompanyAttribute>(attributes),
                        Description = GetAttributeValueOrDefault<AssemblyDescriptionAttribute>(attributes),
                        Copyright = GetAttributeValueOrDefault<AssemblyCopyrightAttribute>(attributes)
                    };
                }
                finally
                {
                    AppDomain.CurrentDomain.ReflectionOnlyAssemblyResolve -= resolver.ReflectionOnlyAssemblyResolve;
                }
            }

            private static Dictionary<string, string> GetProperties(IList<CustomAttributeData> attributes)
            {
                var properties = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                // NOTE: we make this check only by attribute type fullname, and we try to duck
                // type it, therefore enabling the same metadata extesibility behavior for other platforms
                // that don't define the attribute already as part of the framework. 
                // A package author could simply declare this attribute in his own project, using 
                // the same namespace and members, and we'd pick it up automatically. This is consistent 
                // with what MS did in the past with the System.Runtime.CompilerServices.ExtensionAttribute 
                // which allowed Linq to be re-implemented for .NET 2.0 :).
                var attributeName = typeof(AssemblyMetadataAttribute).FullName;
                foreach (var attribute in attributes.Where(x =>
                    x.Constructor.DeclaringType.FullName == attributeName &&
                    x.ConstructorArguments.Count == 2))
                {
                    string key = attribute.ConstructorArguments[0].Value.ToString();
                    string value = attribute.ConstructorArguments[1].Value.ToString();
                    // Return the value only if it isn't null or empty so that we can use ?? to fall back
                    if (!string.IsNullOrEmpty(key) && !string.IsNullOrEmpty(value))
                    {
                        properties[key] = value;
                    }
                }

                return properties;
            }

            private static string GetAttributeValueOrDefault<T>(IList<CustomAttributeData> attributes) where T : Attribute
            {
                foreach (var attribute in attributes)
                {
                    if (attribute.Constructor.DeclaringType == typeof(T))
                    {
                        string value = attribute.ConstructorArguments[0].Value.ToString();
                        // Return the value only if it isn't null or empty so that we can use ?? to fall back
                        if (!string.IsNullOrEmpty(value))
                        {
                            return value;
                        }
                    }
                }
                return null;
            }
        }
    }
}
