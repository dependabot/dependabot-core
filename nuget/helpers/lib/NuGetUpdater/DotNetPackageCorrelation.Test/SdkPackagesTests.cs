using Semver;

using Xunit;

namespace DotNetPackageCorrelation;

public class SdkPackagesTests
{
    [Theory]
    [MemberData(nameof(CorrelatedPackageCanBeFoundData))]
    public void CorrelatedPackageCanBeFound(SdkPackages packages, string sdkVersionString, string packageName, string? expectedPackageVersionString)
    {
        var sdkVersion = SemVersion.Parse(sdkVersionString);
        var actualReplacementPackageVersion = packages.GetReplacementPackageVersion(sdkVersion, packageName);
        var expectedPackageVersion = expectedPackageVersionString is not null
            ? SemVersion.Parse(expectedPackageVersionString)
            : null;
        Assert.Equal(expectedPackageVersion, actualReplacementPackageVersion);
    }

    public static IEnumerable<object?[]> CorrelatedPackageCanBeFoundData()
    {
        // package not found in current sdk, but is in parent; more recent sdk has package, but that's not returned
        yield return
        [
            // packages
            new SdkPackages()
            {
                Packages = new SortedDictionary<SemVersion, PackageSet>(SemVerComparer.Instance)
                {
                    {
                        SemVersion.Parse("1.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
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
                                // empty
                            }
                        }
                    },
                    {
                        SemVersion.Parse("1.0.102"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "Some.Package", SemVersion.Parse("1.0.2") }
                            }
                        }
                    },
                }
            },
            // sdkVersionString
            "1.0.101",
            // packageName
            "Some.Package",
            // expectedPackageVersionString
            "1.0.1"
        ];

        // package differing in case is found
        yield return
        [
            // packages
            new SdkPackages()
            {
                Packages = new SortedDictionary<SemVersion, PackageSet>(SemVerComparer.Instance)
                {
                    {
                        SemVersion.Parse("1.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "some.package", SemVersion.Parse("1.0.1") }
                            }
                        }
                    },
                    {
                        SemVersion.Parse("1.0.101"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                // empty
                            }
                        }
                    },
                }
            },
            // sdkVersionString
            "1.0.101",
            // packageName
            "Some.Package",
            // expectedPackageVersionString
            "1.0.1"
        ];

        // package not found results in null version
        yield return
        [
            // packages
            new SdkPackages()
            {
                Packages = new SortedDictionary<SemVersion, PackageSet>(SemVerComparer.Instance)
                {
                    {
                        SemVersion.Parse("1.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
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
                                // empty
                            }
                        }
                    },
                }
            },
            // sdkVersionString
            "1.0.101",
            // packageName
            "UnrelatedPackage",
            // expectedPackageVersionString
            null
        ];

        // only SDKs with matching major version are considered
        yield return
        [
            // packages
            new SdkPackages()
            {
                Packages = new SortedDictionary<SemVersion, PackageSet>(SemVerComparer.Instance)
                {
                    {
                        SemVersion.Parse("1.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "Some.Package", SemVersion.Parse("1.0.0") }
                            }
                        }
                    },
                    {
                        SemVersion.Parse("2.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "Some.Package", SemVersion.Parse("2.0.1") }
                            }
                        }
                    },
                    {
                        SemVersion.Parse("2.0.200"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                // empty
                            }
                        }
                    },
                    {
                        SemVersion.Parse("3.0.100"),
                        new PackageSet()
                        {
                            Packages = new SortedDictionary<string, SemVersion>(StringComparer.OrdinalIgnoreCase)
                            {
                                { "Some.Package", SemVersion.Parse("3.0.1") }
                            }
                        }
                    },
                }
            },
            // sdkVersionString
            "2.0.200",
            // packageName
            "Some.Package",
            // expectedPackageVersionString
            "2.0.1"
        ];
    }
}
