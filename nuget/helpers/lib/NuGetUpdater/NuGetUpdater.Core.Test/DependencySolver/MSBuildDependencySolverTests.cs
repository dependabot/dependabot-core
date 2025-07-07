using System.Collections.Immutable;

using NuGetUpdater.Core.DependencySolver;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.DependencySolver;

public class MSBuildDependencySolverTests : TestBase
{
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingTopLevelPackage()
    {
        // Updating root package
        // CS-Script Code to 2.0.0 requires its dependency Microsoft.CodeAnalysis.CSharp.Scripting to be 3.6.0 and its transitive dependency Microsoft.CodeAnalysis.Common to be 3.6.0
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("CS-Script.Core", "1.3.1", "net8.0", [(null, [("Microsoft.CodeAnalysis.Scripting.Common", "[3.4.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Scripting.Common", "3.4.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[3.4.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "3.4.0", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("CS-Script.Core", "2.0.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Scripting.Common", "[3.6.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Scripting.Common", "3.6.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[3.6.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "3.6.0", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "CS-Script.Core/1.3.1",
                "Microsoft.CodeAnalysis.Scripting.Common/3.4.0",
                "Microsoft.CodeAnalysis.Common/3.4.0",
            ],
            desiredDependencies: [
                "CS-Script.Core/2.0.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "CS-Script.Core/2.0.0",
                "Microsoft.CodeAnalysis.Scripting.Common/3.6.0",
                "Microsoft.CodeAnalysis.Common/3.6.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingNonExistingDependency()
    {
        // Updating a dependency (Microsoft.Bcl.AsyncInterfaces) of the root package (Azure.Core) will require the root package to also update, but since the dependency is not in the existing list, we do not include it
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Azure.Core", "1.21.0", "net8.0", [(null, [("Microsoft.Bcl.AsyncInterfaces", "[1.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.Bcl.AsyncInterfaces", "1.0.0", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Azure.Core", "1.22.0", "net8.0", [(null, [("Microsoft.Bcl.AsyncInterfaces", "[1.1.1]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.Bcl.AsyncInterfaces", "1.1.1", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Azure.Core/1.21.0",
            ],
            desiredDependencies: [
                "Microsoft.Bcl.AsyncInterfaces/1.1.1",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Azure.Core/1.22.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingNonExistentDependencyAndKeepingReference()
    {
        // Adding a reference
        // Newtonsoft.Json needs to update to 13.0.1. Although Newtonsoft.Json.Bson can use the original version of 12.0.1, for security vulnerabilities and
        // because there is no later version of Newtonsoft.Json.Bson 1.0.2, Newtonsoft.Json would be added to the existing list to prevent resolution
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Newtonsoft.Json.Bson", "1.0.2", "net8.0", [(null, [("Newtonsoft.Json", "12.0.1")])]),
                MockNuGetPackage.CreateSimplePackage("Newtonsoft.Json", "12.0.1", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Newtonsoft.Json", "13.0.1", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Newtonsoft.Json.Bson/1.0.2"
            ],
            desiredDependencies: [
                "Newtonsoft.Json/13.0.1",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Newtonsoft.Json.Bson/1.0.2",
                "Newtonsoft.Json/13.0.1",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewTransitiveDependencyNotExisting()
    {
        // Updating unreferenced dependency
        // Root package (Microsoft.CodeAnalysis.Compilers) and its dependencies (Microsoft.CodeAnalysis.CSharp), (Microsoft.CodeAnalysis.VisualBasic) are all 4.9.2
        // These packages all require the transitive dependency of the root package (Microsoft.CodeAnalysis.Common) to be 4.9.2, but it's not in the existing list
        // If Microsoft.CodeAnalysis.Common is updated to 4.10.0, everything else updates and Microsoft.CoseAnalysis.Common is not kept in the existing list
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Compilers", "4.9.2", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.9.2]"), ("Microsoft.CodeAnalysis.CSharp", "[4.9.2]"), ("Microsoft.CodeAnalysis.VisualBasic", "[4.9.2]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.VisualBasic", "4.9.2", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Compilers", "4.10.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.10.0]"), ("Microsoft.CodeAnalysis.CSharp", "[4.10.0]"), ("Microsoft.CodeAnalysis.VisualBasic", "[4.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.10.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.10.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.VisualBasic", "4.10.0", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Microsoft.CodeAnalysis.Compilers/4.9.2",
                "Microsoft.CodeAnalysis.CSharp/4.9.2",
                "Microsoft.CodeAnalysis.VisualBasic/4.9.2",
            ],
            desiredDependencies: [
                "Microsoft.CodeAnalysis.Common/4.10.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Microsoft.CodeAnalysis.Compilers/4.10.0",
                "Microsoft.CodeAnalysis.CSharp/4.10.0",
                "Microsoft.CodeAnalysis.VisualBasic/4.10.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedTransitiveDependencyExisting()
    {
        // Updating referenced dependency
        // The same as previous test, but the transitive dependency (Microsoft.CodeAnalysis.Common) is in the existing list
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Compilers", "4.9.2", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.9.2]"), ("Microsoft.CodeAnalysis.CSharp", "[4.9.2]"), ("Microsoft.CodeAnalysis.VisualBasic", "[4.9.2]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.VisualBasic", "4.9.2", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Compilers", "4.10.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.10.0]"), ("Microsoft.CodeAnalysis.CSharp", "[4.10.0]"), ("Microsoft.CodeAnalysis.VisualBasic", "[4.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.10.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.10.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.VisualBasic", "4.10.0", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Microsoft.CodeAnalysis.Compilers/4.9.2",
                "Microsoft.CodeAnalysis.Common/4.9.2",
                "Microsoft.CodeAnalysis.CSharp/4.9.2",
                "Microsoft.CodeAnalysis.VisualBasic/4.9.2",
            ],
            desiredDependencies: [
                "Microsoft.CodeAnalysis.Common/4.10.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Microsoft.CodeAnalysis.Compilers/4.10.0",
                "Microsoft.CodeAnalysis.Common/4.10.0",
                "Microsoft.CodeAnalysis.CSharp/4.10.0",
                "Microsoft.CodeAnalysis.VisualBasic/4.10.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewSelectiveAdditionPackages()
    {
        // A combination of the third and fourth test, to measure efficiency of updating separate families
        // Keeping a dependency that was not included in the original list (Newtonsoft.Json)
        // Not keeping a dependency that was not included in the original list (Microsoft.CodeAnalysis.Common)
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Compilers", "4.9.2", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.9.2]"), ("Microsoft.CodeAnalysis.CSharp", "[4.9.2]"), ("Microsoft.CodeAnalysis.VisualBasic", "[4.9.2]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.VisualBasic", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Newtonsoft.Json.Bson", "1.0.2", "net8.0", [(null, [("Newtonsoft.Json", "13.0.1")])]),
                MockNuGetPackage.CreateSimplePackage("Newtonsoft.Json", "13.0.1", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Compilers", "4.10.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.10.0]"), ("Microsoft.CodeAnalysis.CSharp", "[4.10.0]"), ("Microsoft.CodeAnalysis.VisualBasic", "[4.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.10.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.10.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.VisualBasic", "4.10.0", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Microsoft.CodeAnalysis.Compilers/4.9.2",
                "Microsoft.CodeAnalysis.CSharp/4.9.2",
                "Microsoft.CodeAnalysis.VisualBasic/4.9.2",
                "Newtonsoft.Json.Bson/1.0.2",
            ],
            desiredDependencies: [
                "Microsoft.CodeAnalysis.Common/4.10.0",
                "Newtonsoft.Json/13.0.1",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Microsoft.CodeAnalysis.Compilers/4.10.0",
                "Microsoft.CodeAnalysis.CSharp/4.10.0",
                "Microsoft.CodeAnalysis.VisualBasic/4.10.0",
                "Newtonsoft.Json.Bson/1.0.2",
                "Newtonsoft.Json/13.0.1",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewSharingDependency()
    {
        // Two top level packages (Buildalyzer), (Microsoft.CodeAnalysis.CSharp.Scripting) that share a dependency (Microsoft.CodeAnalysis.Csharp)
        // Updating ONE of the top level packages, which updates the dependencies and their other "parents"
        // First family: Buildalyzer 7.0.1 requires Microsoft.CodeAnalysis.CSharp to be = 4.0.1 and Microsoft.CodeAnalysis.Common to be 4.0.1 (@ 6.0.4, Microsoft.CodeAnalysis.Common isn't a dependency of buildalyzer)
        // Second family: Microsoft.CodeAnalysis.CSharp.Scripting 4.0.1 requires Microsoft.CodeAnalysis.CSharp 4.0.1 and Microsoft.CodeAnalysis.Common to be 4.0.1 (Specific version)
        // Updating Buildalyzer to 7.0.1 will update its transitive dependency (Microsoft.CodeAnalysis.Common) and then its transitive dependency's "family"
        await TestAsync(
            packages: [
                MockNuGetPackage.CreateSimplePackage("Buildalyzer", "6.0.4", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[3.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Buildalyzer", "7.0.1", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[4.0.1]")])]),

                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp.Scripting", "3.10.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[3.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp.Scripting", "4.0.1", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[4.0.1]")])]),

                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "3.10.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[3.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.0.1", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.0.1]")])]),

                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "3.10.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.0.1", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Buildalyzer/6.0.4",
                "Microsoft.CodeAnalysis.CSharp.Scripting/3.10.0",
                "Microsoft.CodeAnalysis.CSharp/3.10.0",
                "Microsoft.CodeAnalysis.Common/3.10.0",
            ],
            desiredDependencies: [
                "Buildalyzer/7.0.1",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Buildalyzer/7.0.1",
                "Microsoft.CodeAnalysis.CSharp.Scripting/4.0.1",
                "Microsoft.CodeAnalysis.CSharp/4.0.1",
                "Microsoft.CodeAnalysis.Common/4.0.1",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingEntireFamily()
    {
        // Updating two families at once to test efficiency
        // First family: Direct dependency (Microsoft.CodeAnalysis.Common) needs to be updated, which will then need to update in the existing list its dependency (System.Collections.Immutable) and "parent" (Microsoft.CodeAnalysis.Csharp.Scripting)
        // Second family: Updating the root package (Azure.Core) in the existing list will also need to update its dependency (Microsoft.Bcl.AsyncInterfaces)
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp.Scripting", "4.8.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[4.8.0]"), ("Microsoft.CodeAnalysis.Common", "[4.8.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.8.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.8.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.8.0", "net8.0", [(null, [("System.Collections.Immutable", "7.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("System.Collections.Immutable", "7.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Azure.Core", "1.21.0", "net8.0", [(null, [("Microsoft.Bcl.AsyncInterfaces", "1.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.Bcl.AsyncInterfaces", "1.0.0", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp.Scripting", "4.10.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[4.10.0]"), ("Microsoft.CodeAnalysis.Common", "[4.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.10.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.10.0", "net8.0", [(null, [("System.Collections.Immutable", "8.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("System.Collections.Immutable", "8.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Azure.Core", "1.22.0", "net8.0", [(null, [("Microsoft.Bcl.AsyncInterfaces", "1.1.1")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.Bcl.AsyncInterfaces", "1.1.1", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "System.Collections.Immutable/7.0.0",
                "Microsoft.CodeAnalysis.CSharp.Scripting/4.8.0",
                "Microsoft.Bcl.AsyncInterfaces/1.0.0",
                "Azure.Core/1.21.0",
            ],
            desiredDependencies: [
                "Microsoft.CodeAnalysis.Common/4.10.0",
                "Azure.Core/1.22.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "System.Collections.Immutable/8.0.0",
                "Microsoft.CodeAnalysis.CSharp.Scripting/4.10.0",
                "Microsoft.Bcl.AsyncInterfaces/1.1.1",
                "Azure.Core/1.22.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingTopLevelAndDependency()
    {
        // Similar to the last test, except Microsoft.CodeAnalysis.Common is in the existing list
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp.Scripting", "4.8.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[4.8.0]"), ("Microsoft.CodeAnalysis.Common", "[4.8.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.8.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.8.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.8.0", "net8.0", [(null, [("System.Collections.Immutable", "7.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("System.Collections.Immutable", "7.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Azure.Core", "1.21.0", "net8.0", [(null, [("Microsoft.Bcl.AsyncInterfaces", "1.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.Bcl.AsyncInterfaces", "1.0.0", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp.Scripting", "4.10.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[4.10.0]"), ("Microsoft.CodeAnalysis.Common", "[4.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.10.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.10.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.10.0", "net8.0", [(null, [("System.Collections.Immutable", "8.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("System.Collections.Immutable", "8.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Azure.Core", "1.22.0", "net8.0", [(null, [("Microsoft.Bcl.AsyncInterfaces", "1.1.1")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.Bcl.AsyncInterfaces", "1.1.1", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "System.Collections.Immutable/7.0.0",
                "Microsoft.CodeAnalysis.CSharp.Scripting/4.8.0",
                "Microsoft.CodeAnalysis.Common/4.8.0",
                "Microsoft.Bcl.AsyncInterfaces/1.0.0",
                "Azure.Core/1.21.0",
            ],
            desiredDependencies: [
                "Microsoft.CodeAnalysis.Common/4.10.0",
                "Azure.Core/1.22.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "System.Collections.Immutable/8.0.0",
                "Microsoft.CodeAnalysis.CSharp.Scripting/4.10.0",
                "Microsoft.CodeAnalysis.Common/4.10.0",
                "Microsoft.Bcl.AsyncInterfaces/1.1.1",
                "Azure.Core/1.22.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewOutOfScope()
    {
        // Out of scope test: AutoMapper.Extensions.Microsoft.DependencyInjection's versions are not yet compatible
        // To update root package (AutoMapper.Collection) to 10.0.0, its dependency (AutoMapper) needs to update to 13.0.0. 
        // However, there is no higher version of AutoMapper's other "parent" (AutoMapper.Extensions.Microsoft.DependencyInjection) that is compatible with the new version
        await TestAsync(
            packages: [
                MockNuGetPackage.CreateSimplePackage("AutoMapper.Extensions.Microsoft.DependencyInjection", "12.0.1", "net8.0", [(null, [("AutoMapper", "[12.0.1]")])]),
                MockNuGetPackage.CreateSimplePackage("AutoMapper", "12.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("AutoMapper", "13.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("AutoMapper.Collection", "9.0.0", "net8.0", [(null, [("AutoMapper", "[12.0.0, 13.0.0)")])]),
                MockNuGetPackage.CreateSimplePackage("AutoMapper.Collection", "10.0.0", "net8.0", [(null, [("AutoMapper", "[13.0.0, 14.0.0)")])]),
            ],
            existingTopLevelDependencies: [
                "AutoMapper.Extensions.Microsoft.DependencyInjection/12.0.1",
                "AutoMapper/12.0.1",
                "AutoMapper.Collection/9.0.0",
            ],
            desiredDependencies: [
                "AutoMapper.Collection/10.0.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "AutoMapper.Extensions.Microsoft.DependencyInjection/12.0.1",
                "AutoMapper/12.0.1",
                "AutoMapper.Collection/9.0.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewTwoDependenciesShareSameParent()
    {
        // Two dependencies (Microsoft.Extensions.Caching.Memory), (Microsoft.EntityFrameworkCore.Analyzers) used by the same parent (Microsoft.EntityFrameworkCore), updating one of the dependencies
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore", "7.0.11", "net8.0", [(null, [("Microsoft.EntityFrameworkCore.Analyzers", "7.0.11"), ("Microsoft.Extensions.Caching.Memory", "[7.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Analyzers", "7.0.11", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.Extensions.Caching.Memory", "7.0.0", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore", "8.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore.Analyzers", "8.0.0"), ("Microsoft.Extensions.Caching.Memory", "[8.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Analyzers", "8.0.0", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Microsoft.EntityFrameworkCore/7.0.11",
                "Microsoft.EntityFrameworkCore.Analyzers/7.0.11",
            ],
            desiredDependencies: [
                "Microsoft.Extensions.Caching.Memory/8.0.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Microsoft.EntityFrameworkCore/8.0.0",
                "Microsoft.EntityFrameworkCore.Analyzers/8.0.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewFamilyOfFourExisting()
    {
        // Updating referenced package
        // 4 dependency chain to be updated. Since the package to be updated is in the existing list, do not update its parents since we want to change as little as possible
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Design", "7.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore.Relational", "[7.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Relational", "7.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore", "[7.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore", "7.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore.Analyzers", "[7.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Analyzers", "7.0.0", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Analyzers", "8.0.0", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Microsoft.EntityFrameworkCore.Design/7.0.0",
                "Microsoft.EntityFrameworkCore.Relational/7.0.0",
                "Microsoft.EntityFrameworkCore/7.0.0",
                "Microsoft.EntityFrameworkCore.Analyzers/7.0.0",
            ],
            desiredDependencies: [
                "Microsoft.EntityFrameworkCore.Analyzers/8.0.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Microsoft.EntityFrameworkCore.Design/7.0.0",
                "Microsoft.EntityFrameworkCore.Relational/7.0.0",
                "Microsoft.EntityFrameworkCore/7.0.0",
                "Microsoft.EntityFrameworkCore.Analyzers/8.0.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewFamilyOfFourNotInExisting()
    {
        // Updating unreferenced package
        // 4 dependency chain to be updated, dependency to be updated is not in the existing list, so its family will all be updated
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Design", "7.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore.Relational", "[7.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Relational", "7.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore", "[7.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore", "7.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore.Analyzers", "[7.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Analyzers", "7.0.0", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Design", "8.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore.Relational", "[8.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Relational", "8.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore", "[8.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore", "8.0.0", "net8.0", [(null, [("Microsoft.EntityFrameworkCore.Analyzers", "[8.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.EntityFrameworkCore.Analyzers", "8.0.0", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Microsoft.EntityFrameworkCore.Design/7.0.0",
                "Microsoft.EntityFrameworkCore.Relational/7.0.0",
                "Microsoft.EntityFrameworkCore/7.0.0",
            ],
            desiredDependencies: [
                "Microsoft.EntityFrameworkCore.Analyzers/8.0.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Microsoft.EntityFrameworkCore.Design/8.0.0",
                "Microsoft.EntityFrameworkCore.Relational/8.0.0",
                "Microsoft.EntityFrameworkCore/8.0.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewFamilyOfFourSpecificExisting()
    {

        // Updating a referenced transitive dependency
        // Updating a transtitive dependency (System.Collections.Immutable) to 8.0.0, which will update its "parent" (Microsoft.CodeAnalysis.CSharp) and its "grandparent" (Microsoft.CodeAnalysis.CSharp.Workspaces) to update
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("System.Collections.Immutable", "7.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp.Workspaces", "4.8.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[4.8.0]"), ("Microsoft.CodeAnalysis.Common", "[4.8.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.8.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.8.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.8.0", "net8.0", [(null, [("System.Collections.Immutable", "7.0.0")])]),
                // available packages
                MockNuGetPackage.CreateSimplePackage("System.Collections.Immutable", "8.0.0", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "System.Collections.Immutable/7.0.0",
                "Microsoft.CodeAnalysis.CSharp.Workspaces/4.8.0",
                "Microsoft.CodeAnalysis.CSharp/4.8.0",
                "Microsoft.CodeAnalysis.Common/4.8.0",
            ],
            desiredDependencies: [
                "System.Collections.Immutable/8.0.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "System.Collections.Immutable/8.0.0",
                "Microsoft.CodeAnalysis.CSharp.Workspaces/4.8.0",
                "Microsoft.CodeAnalysis.CSharp/4.8.0",
                "Microsoft.CodeAnalysis.Common/4.8.0",
            ]
        );
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewFamilyOfFourSpecificNotInExisting()
    {
        // Similar to the last test, with the "grandchild" (System.Collections.Immutable) not in the existing list
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp.Workspaces", "4.8.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[4.8.0]"), ("Microsoft.CodeAnalysis.Common", "[4.8.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.8.0", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.8.0]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.8.0", "net8.0", [(null, [("System.Collections.Immutable", "[7.0.0]")])]),
                MockNuGetPackage.CreateSimplePackage("System.Collections.Immutable", "7.0.0", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("System.Collections.Immutable", "8.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp.Workspaces", "4.9.2", "net8.0", [(null, [("Microsoft.CodeAnalysis.CSharp", "[4.9.2]"), ("Microsoft.CodeAnalysis.Common", "[4.9.2]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.CSharp", "4.9.2", "net8.0", [(null, [("Microsoft.CodeAnalysis.Common", "[4.9.2]")])]),
                MockNuGetPackage.CreateSimplePackage("Microsoft.CodeAnalysis.Common", "4.9.2", "net8.0", [(null, [("System.Collections.Immutable", "[8.0.0]")])]),
            ],
            existingTopLevelDependencies: [
                "Microsoft.CodeAnalysis.CSharp.Workspaces/4.8.0",
                "Microsoft.CodeAnalysis.CSharp/4.8.0",
                "Microsoft.CodeAnalysis.Common/4.8.0",
            ],
            desiredDependencies: [
                "System.Collections.Immutable/8.0.0",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Microsoft.CodeAnalysis.CSharp.Workspaces/4.9.2",
                "Microsoft.CodeAnalysis.CSharp/4.9.2",
                "Microsoft.CodeAnalysis.Common/4.9.2",
            ]
        );
    }

    [Fact(Timeout = 120_000)] // 2m
    public async Task DependencyConflictsCanBeResolved_TopLevelDependencyHasNewerVersionsThatDoNotPullUpTransitive()
    {
        await TestAsync(
            packages: [
                // initial packages
                MockNuGetPackage.CreateSimplePackage("Top.Level.Package", "1.41.0", "net8.0", [(null, [("Transitive.Package", "6.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("Transitive.Package", "6.0.0", "net8.0"),
                // available packages
                MockNuGetPackage.CreateSimplePackage("Top.Level.Package", "1.45.0", "net8.0", [(null, [("Transitive.Package", "6.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("Transitive.Package", "8.0.5", "net8.0"),
            ],
            existingTopLevelDependencies: [
                "Top.Level.Package/1.41.0",
            ],
            desiredDependencies: [
                "Transitive.Package/8.0.5",
            ],
            targetFramework: "net8.0",
            expectedResolvedDependencies: [
                "Top.Level.Package/1.41.0",
                "Transitive.Package/8.0.5",
            ]
        );
    }

    private static async Task TestAsync(
        ImmutableArray<string> existingTopLevelDependencies,
        ImmutableArray<string> desiredDependencies,
        string targetFramework,
        ImmutableArray<string> expectedResolvedDependencies,
        MockNuGetPackage[]? packages = null
    )
    {
        // arrange
        var projectName = "project.csproj";
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            (projectName, $"""
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>{targetFramework}</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    {string.Join("\n    ", existingTopLevelDependencies.Select(d => $@"<PackageReference Include=""{d.Split('/')[0]}"" Version=""{d.Split('/')[1]}"" />"))}
                  </ItemGroup>
                </Project>
                """)
        );
        await Update.UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, tempDir.DirectoryPath);
        var repoContentsPath = new DirectoryInfo(tempDir.DirectoryPath);
        var projectPath = new FileInfo(Path.Combine(repoContentsPath.FullName, projectName));
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = true };
        var logger = new TestLogger();
        var msbuildDepSolver = new MSBuildDependencySolver(repoContentsPath, projectPath, experimentsManager, logger);

        // act
        var resolvedDependencies = await msbuildDepSolver.SolveAsync(
            [.. existingTopLevelDependencies.Select(d => new Dependency(d.Split('/')[0], d.Split('/')[1], DependencyType.PackageReference))],
            [.. desiredDependencies.Select(d => new Dependency(d.Split('/')[0], d.Split('/')[1], DependencyType.PackageReference))],
            targetFramework
        );

        // assert
        Assert.NotNull(resolvedDependencies);
        var actualResolvedDependencyStrings = resolvedDependencies.Value.Select(d => $"{d.Name}/{d.Version}");
        AssertEx.Equal(expectedResolvedDependencies, actualResolvedDependencyStrings);
    }
}
