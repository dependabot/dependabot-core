using System.Collections.Immutable;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;
using System.Xml.XPath;

using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Emit;

namespace NuGetUpdater.Core.Test
{
    public record MockNuGetPackage(
        string Id,
        string Version,
        XElement[]? AdditionalMetadata = null,
        (string? TargetFramework, (string Id, string Version)[] Packages)[]? DependencyGroups = null,
        (string Path, byte[] Content)[]? Files = null)
    {
        private static readonly XNamespace Namespace = "http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd";
        private static readonly XmlWriterSettings WriterSettings = new()
        {
            Encoding = Encoding.UTF8,
            Indent = true,
        };

        private XDocument? _nuspec;
        private Stream? _stream;

        public void WriteToDirectory(string localPackageSourcePath)
        {
            string cachePath = Path.Join(localPackageSourcePath, "_nupkg_cache");
            string nupkgPath = Path.Join(cachePath, $"{Id}.{Version}.nupkg");
            Directory.CreateDirectory(cachePath);
            Stream stream = GetZipStream();
            using (FileStream fileStream = new(nupkgPath, FileMode.Create))
            {
                stream.CopyTo(fileStream);
            }

            // add the package to the local feed; this is equivalent to running
            //   nuget add <nupkgPath> -source <localPackageSourcePath>
            // but running that in-process locks the files, so we have to do it manually
            // the end result is 4 files:
            //   .nupkg.metadata                // a JSON object with the package's content hash and some other fields
            //   <id>.<version>.nupkg           // the package itself
            //   <id>.<version>.nupkg.sha512    // the SHA512 hash of the package
            //   <id>.nuspec                    // the package's nuspec file
            string expandedPath = Path.Join(localPackageSourcePath, Id.ToLowerInvariant(), Version);
            Directory.CreateDirectory(expandedPath);
            File.Copy(nupkgPath, Path.Join(expandedPath, $"{Id}.{Version}.nupkg".ToLowerInvariant()));
            using XmlWriter writer = XmlWriter.Create(Path.Join(expandedPath, $"{Id}.nuspec".ToLowerInvariant()), WriterSettings);
            GetNuspec().WriteTo(writer);
            using SHA512 sha512 = SHA512.Create();
            byte[] hash = sha512.ComputeHash(File.ReadAllBytes(nupkgPath));
            string hashString = Convert.ToBase64String(hash);
            File.WriteAllText(Path.Join(expandedPath, $"{Id}.{Version}.nupkg.sha512".ToLowerInvariant()), hashString);
            JsonObject metadata = new()
            {
                ["version"] = 2,
                ["contentHash"] = hashString,
                ["source"] = null,
            };
            File.WriteAllText(Path.Join(expandedPath, ".nupkg.metadata"), metadata.ToString());
        }

        /// <summary>
        /// Creates a mock NuGet package with a single assembly in the appropriate `lib/` directory.  The assembly will
        /// be empty.
        /// </summary>
        public static MockNuGetPackage CreateSimplePackage(
            string id,
            string version,
            string targetFramework,
            (string? TargetFramework, (string Id, string Version)[] Packages)[]? dependencyGroups = null,
            XElement[]? additionalMetadata = null
        )
        {
            return new(
                id,
                version,
                AdditionalMetadata: additionalMetadata,
                DependencyGroups: dependencyGroups,
                Files:
                [
                    ($"lib/{targetFramework}/{id}.dll", Array.Empty<byte>())
                ]
            );
        }

        /// <summary>
        /// Creates a mock NuGet package with a single assembly in the appropriate `lib/` directory.  The assembly will
        /// contain the appropriate `AssemblyVersion` attribute and nothing else.
        /// </summary>
        public static MockNuGetPackage CreatePackageWithAssembly(string id, string version, string targetFramework, string assemblyVersion, ImmutableArray<byte>? assemblyPublicKey = null, (string? TargetFramework, (string Id, string Version)[] Packages)[]? dependencyGroups = null)
        {
            return new(
                id,
                version,
                AdditionalMetadata: null,
                DependencyGroups: dependencyGroups,
                Files:
                [
                    ($"lib/{targetFramework}/{id}.dll", CreateAssembly(id, assemblyVersion, assemblyPublicKey))
                ]
            );
        }

        /// <summary>
        /// Creates a mock NuGet package with empty analyzer assemblies for both C# and VB.
        /// </summary>
        public static MockNuGetPackage CreateAnalyzerPackage(string id, string version, (string? TargetFramework, (string Id, string Version)[] Packages)[]? dependencyGroups = null)
        {
            return new(
                id,
                version,
                AdditionalMetadata:
                [
                    new XElement("developmentDependency", "true"),
                ],
                DependencyGroups: dependencyGroups,
                Files:
                [
                    ($"analyzers/dotnet/cs/{id}.dll", Array.Empty<byte>()),
                    ($"analyzers/dotnet/vb/{id}.dll", Array.Empty<byte>()),
                ]
            );
        }

        public static MockNuGetPackage CreateDotNetToolPackage(string id, string version, string targetFramework, XElement[]? additionalMetadata = null)
        {
            var packageMetadata = new XElement("packageTypes", new XElement("packageType", new XAttribute("name", "DotnetTool")));
            var allMetadata = new[] { packageMetadata }.Concat(additionalMetadata ?? []).ToArray();
            return new(
                id,
                version,
                AdditionalMetadata: allMetadata,
                Files:
                [
                    ($"tools/{targetFramework}/any/DotnetToolSettings.xml", Encoding.UTF8.GetBytes($"""
                        <DotNetCliTool Version="1">
                          <Commands>
                            <Command Name="{id}" EntryPoint="{id}.dll" Runner="dotnet" />
                          </Commands>
                        </DotNetCliTool>
                        """)),
                    ($"tools/{targetFramework}/any/{id}.dll", Array.Empty<byte>()),
                ]
            );
        }

        public static MockNuGetPackage CreateMSBuildSdkPackage(string id, string version, string? sdkPropsContent = null, string? sdkTargetsContent = null, XElement[]? additionalMetadata = null)
        {
            var packageMetadata = new XElement("packageTypes", new XElement("packageType", new XAttribute("name", "MSBuildSdk")));
            var allMetadata = new[] { packageMetadata }.Concat(additionalMetadata ?? []).ToArray();
            sdkPropsContent ??= """
                <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                </Project>
                """;
            sdkTargetsContent ??= """
                <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                </Project>
                """;
            return new(
                id,
                version,
                AdditionalMetadata: additionalMetadata,
                Files:
                [
                    ("Sdk/Sdk.props", Encoding.UTF8.GetBytes(sdkPropsContent)),
                    ("Sdk/Sdk.targets", Encoding.UTF8.GetBytes(sdkTargetsContent)),
                ]
            );
        }

        private XDocument GetNuspec()
        {
            if (_nuspec is null)
            {
                _nuspec = new XDocument(
                    new XElement(Namespace + "package",
                        new XElement(Namespace + "metadata",
                            new XElement(Namespace + "id", Id),
                            new XElement(Namespace + "version", Version),
                            new XElement(Namespace + "authors", "MockNuGetPackage"),
                            new XElement(Namespace + "description", "Mock NuGet package"),
                            AdditionalMetadata?.Select(a => WithNamespace(a, Namespace)),
                            new XElement(Namespace + "dependencies",
                                // dependencies with no target framework
                                DependencyGroups?.Where(g => g.TargetFramework is null).SelectMany(g =>
                                    g.Packages.Select(p =>
                                        new XElement(Namespace + "dependency",
                                            new XAttribute("id", p.Id),
                                            new XAttribute("version", p.Version)
                                        )
                                    )
                                ),
                                // dependencies with a target framework
                                DependencyGroups?.Where(g => g.TargetFramework is not null).Select(g =>
                                    new XElement(Namespace + "group",
                                        new XAttribute("targetFramework", g.TargetFramework!),
                                        g.Packages.Select(p =>
                                            new XElement(Namespace + "dependency",
                                                new XAttribute("id", p.Id),
                                                new XAttribute("version", p.Version)
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                );
            }

            return _nuspec;
        }

        private static XElement WithNamespace(XElement element, XNamespace ns)
        {
            return new XElement(ns + element.Name.LocalName,
                element.Attributes(),
                element.Nodes().Select(n =>
                {
                    if (n is XElement e)
                    {
                        return WithNamespace(e, ns);
                    }

                    return n;
                })
            );
        }

        public Stream GetZipStream()
        {
            if (_stream is null)
            {
                XDocument nuspec = GetNuspec();
                _stream = new MemoryStream();
                using ZipArchive zip = new(_stream, ZipArchiveMode.Create, leaveOpen: true);
                ZipArchiveEntry nuspecEntry = zip.CreateEntry($"{Id}.nuspec");
                using (Stream contentStream = nuspecEntry.Open())
                using (XmlWriter writer = XmlWriter.Create(contentStream, WriterSettings))
                {
                    nuspec.WriteTo(writer);
                }

                foreach (var file in Files ?? [])
                {
                    ZipArchiveEntry fileEntry = zip.CreateEntry(file.Path);
                    using Stream contentStream = fileEntry.Open();
                    contentStream.Write(file.Content, 0, file.Content.Length);
                }
            }

            _stream.Seek(0, SeekOrigin.Begin);
            return _stream;
        }

        private static byte[] CreateAssembly(string assemblyName, string assemblyVersion, ImmutableArray<byte>? assemblyPublicKey = null)
        {
            CSharpCompilationOptions compilationOptions = new(OutputKind.DynamicallyLinkedLibrary);
            if (assemblyPublicKey is not null)
            {
                compilationOptions = compilationOptions.WithCryptoPublicKey(assemblyPublicKey.Value);
            }
            CSharpCompilation compilation = CSharpCompilation.Create(assemblyName, options: compilationOptions)
                .AddReferences(MetadataReference.CreateFromFile(typeof(object).Assembly.Location))
                .AddSyntaxTrees(CSharpSyntaxTree.ParseText($"[assembly: System.Reflection.AssemblyVersionAttribute(\"{assemblyVersion}\")]"));
            MemoryStream assemblyStream = new();
            EmitResult emitResult = compilation.Emit(assemblyStream);
            if (!emitResult.Success)
            {
                throw new Exception($"Unable to create test assembly:\n\t{string.Join("\n\t", emitResult.Diagnostics.ToString())}");
            }

            return assemblyStream.ToArray();
        }

        // some well-known packages
        public static MockNuGetPackage CentralPackageVersionsPackage =>
            CreateMSBuildSdkPackage(
                "Microsoft.Build.CentralPackageVersions",
                "2.1.3",
                sdkTargetsContent: """
                    <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                        <!-- this is a simplified version of this package used for testing -->
                        <PropertyGroup>
                        <CentralPackagesFile Condition=" '$(CentralPackagesFile)' == '' ">$([MSBuild]::GetPathOfFileAbove('Packages.props', $(MSBuildProjectDirectory)))</CentralPackagesFile>
                        </PropertyGroup>
                        <Import Project="$(CentralPackagesFile)" Condition="Exists('$(CentralPackagesFile)')" />
                    </Project>
                    """
            );

        private static readonly Lazy<string> BundledVersionsPropsPath = new(() =>
        {
            // we need to find the file `Microsoft.NETCoreSdk.BundledVersions.props` in the SDK directory

            DirectoryInfo projectDir = Directory.CreateTempSubdirectory("bundled_versions_props_path_discovery_");
            try
            {
                // get the sdk version
                string projectPath = Path.Combine(projectDir.FullName, "project.csproj");
                File.WriteAllText(projectPath, """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Target Name="_ReportCurrentSdkVersion">
                        <Message Text="_CurrentSdkVersion=$(NETCoreSdkVersion)" Importance="High" />
                      </Target>
                    </Project>
                    """
                );
                var (exitCode, stdout, stderr) = ProcessEx.RunAsync("dotnet", ["msbuild", projectPath, "/t:_ReportCurrentSdkVersion"]).Result;
                if (exitCode != 0)
                {
                    throw new Exception($"Failed to report the current SDK version:\n{stdout}\n{stderr}");
                }

                MatchCollection matches = Regex.Matches(stdout, "_CurrentSdkVersion=(?<SdkVersion>.*)$", RegexOptions.Multiline);
                if (matches.Count == 0)
                {
                    throw new Exception($"Failed to find the current SDK version in the output:\n{stdout}");
                }

                string sdkVersionString = matches.First().Groups["SdkVersion"].Value.Trim();

                // find the actual SDK directory
                string privateCoreLibPath = typeof(object).Assembly.Location; // e.g., C:\Program Files\dotnet\shared\Microsoft.NETCore.App\8.0.4\System.Private.CoreLib.dll
                string sdkDirectory = Path.Combine(Path.GetDirectoryName(privateCoreLibPath)!, "..", "..", "..", "sdk", sdkVersionString); // e.g., C:\Program Files\dotnet\sdk\8.0.204
                string bundledVersionsPropsPath = Path.Combine(sdkDirectory, "Microsoft.NETCoreSdk.BundledVersions.props");
                FileInfo normalizedPath = new(bundledVersionsPropsPath);
                return normalizedPath.FullName;
            }
            finally
            {
                projectDir.Delete(recursive: true);
            }
        });

        private static readonly Dictionary<string, MockNuGetPackage> WellKnownPackages = new();
        public static MockNuGetPackage WellKnownReferencePackage(string packageName, string targetFramework, (string Path, byte[] Content)[]? files = null)
        {
            string key = $"{packageName}/{targetFramework}";
            if (!WellKnownPackages.ContainsKey(key))
            {
                // for the current SDK, the file `Microsoft.NETCoreSdk.BundledVersions.props` contains the version of the
                // `Microsoft.WindowsDesktop.App.Ref` package that will be needed to build, so we find it by TFM
                XDocument propsDocument = XDocument.Load(BundledVersionsPropsPath.Value);
                XElement? matchingFrameworkElement = propsDocument.XPathSelectElement(
                    $"""
                    /Project/ItemGroup/KnownFrameworkReference
                        [
                            @Include='{packageName}' and
                            @TargetingPackName='{packageName}.Ref' and
                            @TargetFramework='{targetFramework}'
                        ]
                    """);
                if (matchingFrameworkElement is null)
                {
                    throw new Exception($"Unable to find {packageName}.Ref version for target framework '{targetFramework}'");
                }

                string expectedVersion = matchingFrameworkElement.Attribute("TargetingPackVersion")!.Value;
                return new(
                    $"{packageName}.Ref",
                    expectedVersion,
                    AdditionalMetadata:
                    [
                        new XElement("packageTypes",
                            new XElement("packageType",
                                new XAttribute("name", "DotnetPlatform")
                            )
                        )
                    ],
                    Files: files
                );
            }

            return WellKnownPackages[key];
        }

        public static MockNuGetPackage[] CommonPackages { get; } =
        [
            CreateSimplePackage("NETStandard.Library", "2.0.3", "netstandard2.0"),
            new MockNuGetPackage("Microsoft.NETFramework.ReferenceAssemblies", "1.0.3"),
            WellKnownReferencePackage("Microsoft.AspNetCore.App", "net6.0"),
            WellKnownReferencePackage("Microsoft.AspNetCore.App", "net7.0"),
            WellKnownReferencePackage("Microsoft.AspNetCore.App", "net8.0"),
            WellKnownReferencePackage("Microsoft.AspNetCore.App", "net9.0"),
            WellKnownReferencePackage("Microsoft.NETCore.App", "net6.0",
            [
                ("data/FrameworkList.xml", Encoding.UTF8.GetBytes("""
                    <FileList TargetFrameworkIdentifier=".NETCoreApp" TargetFrameworkVersion="6.0" FrameworkName="Microsoft.NETCore.App" Name=".NET Runtime">
                    </FileList>
                    """))
            ]),
            WellKnownReferencePackage("Microsoft.NETCore.App", "net7.0",
            [
                ("data/FrameworkList.xml", Encoding.UTF8.GetBytes("""
                    <FileList TargetFrameworkIdentifier=".NETCoreApp" TargetFrameworkVersion="7.0" FrameworkName="Microsoft.NETCore.App" Name=".NET Runtime">
                    </FileList>
                    """))
            ]),
            WellKnownReferencePackage("Microsoft.NETCore.App", "net8.0",
            [
                ("data/FrameworkList.xml", Encoding.UTF8.GetBytes("""
                    <FileList TargetFrameworkIdentifier=".NETCoreApp" TargetFrameworkVersion="8.0" FrameworkName="Microsoft.NETCore.App" Name=".NET Runtime">
                    </FileList>
                    """))
            ]),
            WellKnownReferencePackage("Microsoft.NETCore.App", "net9.0",
            [
                ("data/FrameworkList.xml", Encoding.UTF8.GetBytes("""
                    <FileList TargetFrameworkIdentifier=".NETCoreApp" TargetFrameworkVersion="9.0" FrameworkName="Microsoft.NETCore.App" Name=".NET Runtime">
                    </FileList>
                    """))
            ]),
            WellKnownReferencePackage("Microsoft.WindowsDesktop.App", "net6.0"),
            WellKnownReferencePackage("Microsoft.WindowsDesktop.App", "net7.0"),
            WellKnownReferencePackage("Microsoft.WindowsDesktop.App", "net8.0"),
            WellKnownReferencePackage("Microsoft.WindowsDesktop.App", "net9.0"),
        ];
    }
}
