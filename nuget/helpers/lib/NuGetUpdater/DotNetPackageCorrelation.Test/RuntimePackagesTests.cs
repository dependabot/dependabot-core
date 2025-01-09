using Semver;

using Xunit;

namespace DotNetPackageCorrelation;

public class RuntimePackagesTests
{
    [Theory]
    [MemberData(nameof(CorrelatedPackageCanBeFoundData))]
    public void CorrelatedPackageCanBeFound(RuntimePackages runtimePackages, string runtimePackageName, string runtimePackageVersion, string candidatePackageName, string? expectedPackageVersion)
    {
        var packageMapper = PackageMapper.Load(runtimePackages);
        var actualPackageVersion = packageMapper.GetPackageVersionThatShippedWithOtherPackage(runtimePackageName, SemVersion.Parse(runtimePackageVersion), candidatePackageName);
        if (expectedPackageVersion is null)
        {
            Assert.Null(actualPackageVersion);
        }
        else
        {
            Assert.NotNull(actualPackageVersion);
            Assert.Equal(expectedPackageVersion, actualPackageVersion.ToString());
        }
    }

    public static IEnumerable<object?[]> CorrelatedPackageCanBeFoundData()
    {
        // package not found in specified runtime, but it is in earlier runtime; more recent runtime has that package, but that's not returned
        yield return
        [
            // runtimePackages
            new RuntimePackages()
            {
                Runtimes = new SortedDictionary<SemVersion, PackageSet>(SemVerComparer.Instance)
                {
                    {
                        SemVersion.Parse("1.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "Runtime.Package", SemVersion.Parse("1.0.0") },
                                { "Some.Package", SemVersion.Parse("1.0.1") }
                            }
                        }
                    },
                    {
                        SemVersion.Parse("1.0.101"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                // this runtime didn't ship with a new version of "Some.Package", but the earlier release did
                                { "Runtime.Package", SemVersion.Parse("1.0.1") }
                            }
                        }
                    },
                    {
                        SemVersion.Parse("1.0.200"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                // the requested package shipped with this runtime, but this runtime isn't the correct version so it's not returned
                                { "Runtime.Package", SemVersion.Parse("1.0.2") },
                                { "Some.Package", SemVersion.Parse("1.0.2") }
                            }
                        }
                    },
                }
            },
            // runtimePackageName
            "Runtime.Package",
            // runtimePackageVersion
            "1.0.1",
            // candidatePackageName
            "Some.Package",
            // expectedPackageVersion
            "1.0.1"
        ];

        // package differing in case is found
        yield return
        [
            // runtimePackages
            new RuntimePackages()
            {
                Runtimes = new SortedDictionary<SemVersion, PackageSet>(SemVerComparer.Instance)
                {
                    {
                        SemVersion.Parse("1.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "runtime.package", SemVersion.Parse("1.0.0") },
                                { "some.package", SemVersion.Parse("1.0.1") }
                            }
                        }
                    }
                }
            },
            // runtimePackageName
            "Runtime.Package",
            // runtimePackageVersion
            "1.0.0",
            // candidatePackageName
            "Some.Package",
            // expectedPackageVersion
            "1.0.1"
        ];

        // runtime package not found by name
        yield return
        [
            // runtimePackages
            new RuntimePackages()
            {
                Runtimes = new SortedDictionary<SemVersion, PackageSet>(SemVerComparer.Instance)
                {
                    {
                        SemVersion.Parse("1.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "runtime.package", SemVersion.Parse("1.0.0") },
                                { "some.package", SemVersion.Parse("1.0.1") }
                            }
                        }
                    }
                }
            },
            // runtimePackageName
            "Different.Runtime.Package",
            // runtimePackageVersion
            "1.0.0",
            // candidatePackageName
            "Some.Package",
            // expectedPackageVersion
            null
        ];

        // runtime package not found by version
        yield return
        [
            // runtimePackages
            new RuntimePackages()
            {
                Runtimes = new SortedDictionary<SemVersion, PackageSet>(SemVerComparer.Instance)
                {
                    {
                        SemVersion.Parse("1.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "runtime.package", SemVersion.Parse("1.0.0") },
                                { "some.package", SemVersion.Parse("1.0.1") }
                            }
                        }
                    }
                }
            },
            // runtimePackageName
            "Runtime.Package",
            // runtimePackageVersion
            "9.9.9",
            // candidatePackageName
            "Some.Package",
            // expectedPackageVersion
            null
        ];

        // candidate package not found
        yield return
        [
            // runtimePackages
            new RuntimePackages()
            {
                Runtimes = new SortedDictionary<SemVersion, PackageSet>(SemVerComparer.Instance)
                {
                    {
                        SemVersion.Parse("1.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "runtime.package", SemVersion.Parse("1.0.0") },
                                { "some.package", SemVersion.Parse("1.0.1") }
                            }
                        }
                    }
                }
            },
            // runtimePackageName
            "Runtime.Package",
            // runtimePackageVersion
            "1.0.0",
            // candidatePackageName
            "Package.Not.In.This.Runtime",
            // expectedPackageVersion
            null
        ];
    }
}
