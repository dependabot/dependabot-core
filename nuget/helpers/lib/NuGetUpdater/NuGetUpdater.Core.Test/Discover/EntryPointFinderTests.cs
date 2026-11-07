using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test;

using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public class EntryPointFinderTests : TestBase
{
    [Fact]
    public async Task SlnReferencingCsproj_MapsChildToParent()
    {
        // a .sln referencing a .csproj creates a child-to-parent mapping
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("app.sln", """
                Microsoft Visual Studio Solution File, Format Version 12.00
                Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MyApp", "src\MyApp\MyApp.csproj", "{00000000-0000-0000-0000-000000000000}"
                EndProject
                """),
            ("src/MyApp/MyApp.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var entryPoints = EntryPointFinder.ScanForEntryPointFiles(temp.DirectoryPath);
        Assert.Single(entryPoints);

        var map = await EntryPointFinder.BuildChildToParentMapAsync(entryPoints, new TestLogger());
        var csprojPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "MyApp", "MyApp.csproj"));
        Assert.True(map.ContainsKey(csprojPath), $"Expected map to contain {csprojPath}");
        var parents = map[csprojPath];
        Assert.Single(parents);
        Assert.EndsWith("app.sln", parents.First());
    }

    [Fact]
    public async Task ProjWithProjectFile_MapsChildToParent()
    {
        // a .proj file using <ProjectFile> references maps children back to parent
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("dirs.proj", """
                <Project>
                  <ItemGroup>
                    <ProjectFile Include="src\MyApp\MyApp.csproj" />
                  </ItemGroup>
                </Project>
                """),
            ("src/MyApp/MyApp.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var entryPoints = EntryPointFinder.ScanForEntryPointFiles(temp.DirectoryPath);
        Assert.Single(entryPoints);

        var map = await EntryPointFinder.BuildChildToParentMapAsync(entryPoints, new TestLogger());
        var csprojPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "MyApp", "MyApp.csproj"));
        Assert.True(map.ContainsKey(csprojPath));
        Assert.EndsWith("dirs.proj", map[csprojPath].First());
    }

    [Fact]
    public async Task TransitiveChain_CollapsesToTopLevel()
    {
        // dirs.proj -> src/dirs.proj -> src/client/client.csproj
        // walking from client.csproj should reach dirs.proj at the root
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("dirs.proj", """
                <Project>
                  <ItemGroup>
                    <ProjectFile Include="src\dirs.proj" />
                  </ItemGroup>
                </Project>
                """),
            ("src/dirs.proj", """
                <Project>
                  <ItemGroup>
                    <ProjectFile Include="client\client.csproj" />
                  </ItemGroup>
                </Project>
                """),
            ("src/client/client.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var entryPoints = EntryPointFinder.ScanForEntryPointFiles(temp.DirectoryPath);
        Assert.Equal(2, entryPoints.Length);

        var map = await EntryPointFinder.BuildChildToParentMapAsync(entryPoints, new TestLogger());

        var clientPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "client", "client.csproj"));
        var roots = EntryPointFinder.WalkToRoots(clientPath, map);
        Assert.Single(roots);
        Assert.EndsWith("dirs.proj", roots.First());
        // the root should be at the repo root, not src/dirs.proj
        var rootDir = Path.GetDirectoryName(roots.First())!.NormalizePathToUnix();
        Assert.False(rootDir.EndsWith("/src"), $"Expected root directory to not be under 'src', but was: {rootDir}");
    }

    [Fact]
    public async Task NoParentFound_KeepsOriginalDirectory()
    {
        // a .csproj with no parent entry point keeps its directory
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("src/MyApp/MyApp.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var entryPoints = EntryPointFinder.ScanForEntryPointFiles(temp.DirectoryPath);
        Assert.Empty(entryPoints);

        var result = await EntryPointFinder.FindRootDirectoriesAsync(
            ["/src/MyApp"],
            temp.DirectoryPath,
            new TestLogger());

        Assert.Single(result);
        Assert.Equal("/src/MyApp", result[0]);
    }

    [Fact]
    public async Task MultipleDirectoriesConvergingToSameRoot()
    {
        // two directories both parented by the same .sln -> single root
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("app.sln", """
                Microsoft Visual Studio Solution File, Format Version 12.00
                Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Client", "src\client\client.csproj", "{00000000-0000-0000-0000-000000000001}"
                EndProject
                Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Server", "src\server\server.csproj", "{00000000-0000-0000-0000-000000000002}"
                EndProject
                """),
            ("src/client/client.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"),
            ("src/server/server.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var result = await EntryPointFinder.FindRootDirectoriesAsync(
            ["/src/client", "/src/server"],
            temp.DirectoryPath,
            new TestLogger());

        Assert.Single(result);
        Assert.Equal("/", result[0]);
    }

    [Fact]
    public async Task MixedDirectories_SomeWithParentsSomeWithout()
    {
        // /src/client has a parent .sln, /standalone does not
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("app.sln", """
                Microsoft Visual Studio Solution File, Format Version 12.00
                Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Client", "src\client\client.csproj", "{00000000-0000-0000-0000-000000000001}"
                EndProject
                """),
            ("src/client/client.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"),
            ("standalone/standalone.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var result = await EntryPointFinder.FindRootDirectoriesAsync(
            ["/src/client", "/standalone"],
            temp.DirectoryPath,
            new TestLogger());

        Assert.Equal(2, result.Length);
        Assert.Contains("/", result);
        Assert.Contains("/standalone", result);
    }

    [Fact]
    public async Task AlreadyRootDirectory_RemainsUnchanged()
    {
        // job directory is already "/" and a .sln is at root
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("app.sln", """
                Microsoft Visual Studio Solution File, Format Version 12.00
                Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MyApp", "src\MyApp\MyApp.csproj", "{00000000-0000-0000-0000-000000000000}"
                EndProject
                """),
            ("src/MyApp/MyApp.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var result = await EntryPointFinder.FindRootDirectoriesAsync(
            ["/"],
            temp.DirectoryPath,
            new TestLogger());

        Assert.Single(result);
        Assert.Equal("/", result[0]);
    }

    [Fact]
    public async Task DuplicateDirectories_AreDeduplicated()
    {
        // two projects in the same directory both parented by same .sln
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("app.sln", """
                Microsoft Visual Studio Solution File, Format Version 12.00
                Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Lib1", "src\Lib1.csproj", "{00000000-0000-0000-0000-000000000001}"
                EndProject
                Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Lib2", "src\Lib2.csproj", "{00000000-0000-0000-0000-000000000002}"
                EndProject
                """),
            ("src/Lib1.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"),
            ("src/Lib2.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var result = await EntryPointFinder.FindRootDirectoriesAsync(
            ["/src"],
            temp.DirectoryPath,
            new TestLogger());

        Assert.Single(result);
        Assert.Equal("/", result[0]);
    }

    [Fact]
    public void WalkToRoots_NoCycle_WithMultipleParents()
    {
        // file has two parents, both are roots
        var map = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase)
        {
            ["/repo/src/app.csproj"] = new(StringComparer.OrdinalIgnoreCase) { "/repo/a.sln", "/repo/b.sln" },
        };

        var roots = EntryPointFinder.WalkToRoots("/repo/src/app.csproj", map);
        Assert.Equal(2, roots.Count);
        Assert.Contains("/repo/a.sln", roots);
        Assert.Contains("/repo/b.sln", roots);
    }

    [Fact]
    public void WalkToRoots_HandlesCycles()
    {
        // circular reference shouldn't infinite loop
        var map = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase)
        {
            ["/repo/a.proj"] = new(StringComparer.OrdinalIgnoreCase) { "/repo/b.proj" },
            ["/repo/b.proj"] = new(StringComparer.OrdinalIgnoreCase) { "/repo/a.proj" },
        };

        // should terminate without hanging; both files reference each other so neither is a "root"
        // but the visited check prevents infinite loop, and neither has a non-cyclic parent
        var roots = EntryPointFinder.WalkToRoots("/repo/a.proj", map);
        Assert.Empty(roots);
    }

    [Fact]
    public void WalkToRoots_FileNotInMap_ReturnsSelf()
    {
        var map = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        var roots = EntryPointFinder.WalkToRoots("/repo/orphan.csproj", map);
        Assert.Single(roots);
        Assert.Contains("/repo/orphan.csproj", roots);
    }

    [Fact]
    public async Task ProjWithRecursiveGlob_ExpandsAllMatchingProjects()
    {
        // a .proj file using a recursive glob should find all matching .csproj files
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("dirs.proj", """
                <Project>
                  <ItemGroup>
                    <ProjectFile Include="**\*.csproj" />
                  </ItemGroup>
                </Project>
                """),
            ("src/app/app.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"),
            ("src/lib/lib.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"),
            ("test/app.test/app.test.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var entryPoints = EntryPointFinder.ScanForEntryPointFiles(temp.DirectoryPath);
        Assert.Single(entryPoints);

        var map = await EntryPointFinder.BuildChildToParentMapAsync(entryPoints, new TestLogger());
        Assert.Equal(3, map.Count);

        var appPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "app", "app.csproj"));
        var libPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "lib", "lib.csproj"));
        var testPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "test", "app.test", "app.test.csproj"));

        Assert.True(map.ContainsKey(appPath));
        Assert.True(map.ContainsKey(libPath));
        Assert.True(map.ContainsKey(testPath));

        // all should map back to dirs.proj
        foreach (var key in new[] { appPath, libPath, testPath })
        {
            Assert.Single(map[key]);
            Assert.EndsWith("dirs.proj", map[key].First());
        }
    }

    [Fact]
    public async Task ProjWithSingleLevelGlob_ExpandsOnlyImmediateChildren()
    {
        // a .proj file using a single-level glob should only match files in the immediate subdirectory
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("dirs.proj", """
                <Project>
                  <ItemGroup>
                    <ProjectFile Include="src\*\*.csproj" />
                  </ItemGroup>
                </Project>
                """),
            ("src/app/app.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"),
            ("src/lib/lib.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"),
            ("test/other/other.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var entryPoints = EntryPointFinder.ScanForEntryPointFiles(temp.DirectoryPath);
        Assert.Single(entryPoints);

        var map = await EntryPointFinder.BuildChildToParentMapAsync(entryPoints, new TestLogger());
        // only the two under src/ should match, not the one under test/
        Assert.Equal(2, map.Count);

        var appPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "app", "app.csproj"));
        var libPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "lib", "lib.csproj"));
        var testPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "test", "other", "other.csproj"));

        Assert.True(map.ContainsKey(appPath));
        Assert.True(map.ContainsKey(libPath));
        Assert.False(map.ContainsKey(testPath));
    }

    [Fact]
    public async Task ProjWithGlob_WalksToRoot()
    {
        // end-to-end: a recursive glob .proj is the root, and a job directory should resolve to it
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("dirs.proj", """
                <Project>
                  <ItemGroup>
                    <ProjectFile Include="**\*.csproj" />
                  </ItemGroup>
                </Project>
                """),
            ("src/app/app.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var result = await EntryPointFinder.FindRootDirectoriesAsync(
            ["/src/app"],
            temp.DirectoryPath,
            new TestLogger());

        Assert.Single(result);
        Assert.Equal("/", result[0]);
    }

    [Fact]
    public async Task ProjWithGlobAndExplicitRef_BothExpanded()
    {
        // a .proj file mixing a glob with an explicit reference should map both
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("dirs.proj", """
                <Project>
                  <ItemGroup>
                    <ProjectFile Include="src\**\*.csproj" />
                    <ProjectFile Include="standalone\standalone.csproj" />
                  </ItemGroup>
                </Project>
                """),
            ("src/app/app.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"),
            ("standalone/standalone.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var entryPoints = EntryPointFinder.ScanForEntryPointFiles(temp.DirectoryPath);
        Assert.Single(entryPoints);

        var map = await EntryPointFinder.BuildChildToParentMapAsync(entryPoints, new TestLogger());
        Assert.Equal(2, map.Count);

        var appPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "app", "app.csproj"));
        var standalonePath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "standalone", "standalone.csproj"));

        Assert.True(map.ContainsKey(appPath));
        Assert.True(map.ContainsKey(standalonePath));
    }

    [Fact]
    public async Task ProjWithMSBuildProperty_ExpandsPropertyInPath()
    {
        // $(MSBuildThisFileDirectory) resolves to the directory containing the .proj file
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("dirs.proj", """
                <Project>
                  <ItemGroup>
                    <ProjectFile Include="$(MSBuildThisFileDirectory)src\app\app.csproj" />
                  </ItemGroup>
                </Project>
                """),
            ("src/app/app.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var entryPoints = EntryPointFinder.ScanForEntryPointFiles(temp.DirectoryPath);
        Assert.Single(entryPoints);

        var map = await EntryPointFinder.BuildChildToParentMapAsync(entryPoints, new TestLogger());
        var appPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "app", "app.csproj"));
        Assert.True(map.ContainsKey(appPath), $"Expected map to contain {appPath}");
        Assert.EndsWith("dirs.proj", map[appPath].First());
    }

    [Fact]
    public async Task ProjWithMSBuildPropertyAndGlob_ExpandsBoth()
    {
        // $(MSBuildThisFileDirectory) combined with a glob should expand both the property and the glob
        using var temp = await TemporaryDirectory.CreateWithContentsAsync(
            ("dirs.proj", """
                <Project>
                  <ItemGroup>
                    <ProjectFile Include="$(MSBuildThisFileDirectory)src\**\*.csproj" />
                  </ItemGroup>
                </Project>
                """),
            ("src/app/app.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"),
            ("src/lib/lib.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />")
        );

        var entryPoints = EntryPointFinder.ScanForEntryPointFiles(temp.DirectoryPath);
        Assert.Single(entryPoints);

        var map = await EntryPointFinder.BuildChildToParentMapAsync(entryPoints, new TestLogger());
        Assert.Equal(2, map.Count);

        var appPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "app", "app.csproj"));
        var libPath = Path.GetFullPath(Path.Combine(temp.DirectoryPath, "src", "lib", "lib.csproj"));
        Assert.True(map.ContainsKey(appPath));
        Assert.True(map.ContainsKey(libPath));
    }
}
