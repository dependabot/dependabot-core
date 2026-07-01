using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class RunWorkerTests
{
    public class AddInsecureConnectionsAttribute
    {
        [Theory]
        [MemberData(nameof(TestData))]
        public void CorrectlyPatchesNuGetConfig(string testName, string input, string expected)
        {
            _ = testName; // used for test display only

            var result = RunWorker.AddInsecureConnectionsAttribute(input);

            Assert.Equal(expected, result);
        }

        public static TheoryData<string, string, string> TestData => new()
        {
            {
                // testName
                "adds attribute to http source",
                // input
                """
                <configuration>
                  <packageSources>
                    <add key="local" value="http://localhost:8080/index.json" />
                  </packageSources>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <packageSources>
                    <add key="local" value="http://localhost:8080/index.json" allowInsecureConnections="true" />
                  </packageSources>
                </configuration>
                """
            },
            {
                // testName
                "does not add attribute to https source",
                // input
                """
                <configuration>
                  <packageSources>
                    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
                  </packageSources>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <packageSources>
                    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
                  </packageSources>
                </configuration>
                """
            },
            {
                // testName
                "does not add attribute to local path source",
                // input
                """
                <configuration>
                  <packageSources>
                    <add key="local" value="../local-feed" />
                  </packageSources>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <packageSources>
                    <add key="local" value="../local-feed" />
                  </packageSources>
                </configuration>
                """
            },
            {
                // testName
                "does not duplicate existing attribute on http source",
                // input
                """
                <configuration>
                  <packageSources>
                    <add key="local" value="http://internal-server/nuget" allowInsecureConnections="false" />
                  </packageSources>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <packageSources>
                    <add key="local" value="http://internal-server/nuget" allowInsecureConnections="false" />
                  </packageSources>
                </configuration>
                """
            },
            {
                // testName
                "handles multiple sources with mixed protocols",
                // input
                """
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
                    <add key="private" value="https://pkgs.dev.azure.com/org/_packaging/feed/nuget/v3/index.json" />
                    <add key="local" value="http://internal-server/nuget" />
                    <add key="disk" value="C:\packages" />
                  </packageSources>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
                    <add key="private" value="https://pkgs.dev.azure.com/org/_packaging/feed/nuget/v3/index.json" />
                    <add key="local" value="http://internal-server/nuget" allowInsecureConnections="true" />
                    <add key="disk" value="C:\packages" />
                  </packageSources>
                </configuration>
                """
            },
            {
                // testName
                "preserves package source mappings",
                // input
                """
                <configuration>
                  <packageSources>
                    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
                    <add key="private" value="http://internal-server/nuget/v3/index.json" />
                  </packageSources>
                  <packageSourceMapping>
                    <packageSource key="nuget.org">
                      <package pattern="*" />
                    </packageSource>
                    <packageSource key="private">
                      <package pattern="Contoso.*" />
                    </packageSource>
                  </packageSourceMapping>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <packageSources>
                    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
                    <add key="private" value="http://internal-server/nuget/v3/index.json" allowInsecureConnections="true" />
                  </packageSources>
                  <packageSourceMapping>
                    <packageSource key="nuget.org">
                      <package pattern="*" />
                    </packageSource>
                    <packageSource key="private">
                      <package pattern="Contoso.*" />
                    </packageSource>
                  </packageSourceMapping>
                </configuration>
                """
            },
            {
                // testName
                "preserves other config sections",
                // input
                """
                <configuration>
                  <packageSources>
                    <add key="local" value="http://internal-server/nuget" />
                  </packageSources>
                  <disabledPackageSources>
                    <add key="private" value="true" />
                  </disabledPackageSources>
                  <config>
                    <add key="globalPackagesFolder" value=".\packages" />
                  </config>
                  <packageRestore>
                    <add key="enabled" value="True" />
                  </packageRestore>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <packageSources>
                    <add key="local" value="http://internal-server/nuget" allowInsecureConnections="true" />
                  </packageSources>
                  <disabledPackageSources>
                    <add key="private" value="true" />
                  </disabledPackageSources>
                  <config>
                    <add key="globalPackagesFolder" value=".\packages" />
                  </config>
                  <packageRestore>
                    <add key="enabled" value="True" />
                  </packageRestore>
                </configuration>
                """
            },
            {
                // testName
                "handles no packageSources element",
                // input
                """
                <configuration>
                  <config>
                    <add key="globalPackagesFolder" value=".\packages" />
                  </config>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <config>
                    <add key="globalPackagesFolder" value=".\packages" />
                  </config>
                </configuration>
                """
            },
            {
                // testName
                "handles empty packageSources",
                // input
                """
                <configuration>
                  <packageSources>
                    <clear />
                  </packageSources>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <packageSources>
                    <clear />
                  </packageSources>
                </configuration>
                """
            },
            {
                // testName
                "preserves package source credentials",
                // input
                """
                <configuration>
                  <packageSources>
                    <add key="private" value="http://internal-server/nuget/v3/index.json" />
                  </packageSources>
                  <packageSourceCredentials>
                    <private>
                      <add key="Username" value="user" />
                      <add key="ClearTextPassword" value="token" />
                    </private>
                  </packageSourceCredentials>
                </configuration>
                """,
                // expected
                """
                <configuration>
                  <packageSources>
                    <add key="private" value="http://internal-server/nuget/v3/index.json" allowInsecureConnections="true" />
                  </packageSources>
                  <packageSourceCredentials>
                    <private>
                      <add key="Username" value="user" />
                      <add key="ClearTextPassword" value="token" />
                    </private>
                  </packageSourceCredentials>
                </configuration>
                """
            },
            {
                // testName
                "handles config with XML declaration",
                // input
                """
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <add key="local" value="http://internal-server/nuget" />
                  </packageSources>
                </configuration>
                """,
                // expected
                """
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <add key="local" value="http://internal-server/nuget" allowInsecureConnections="true" />
                  </packageSources>
                </configuration>
                """
            },
        };
    }

    public class GetDependencyInfoTests
    {
        [Fact]
        public void AllowPrerelease_MatchingDependencyName_SetsAllowPrereleaseTrue()
        {
            var job = new Job()
            {
                AllowedUpdates =
                [
                    new AllowedUpdate() { DependencyName = "Some.Package", Prerelease = true },
                    new AllowedUpdate() { UpdateType = UpdateType.All },
                ],
                Source = new() { Provider = "github", Repo = "test/repo" },
            };
            var dependency = new Dependency("Some.Package", "1.0.0", DependencyType.PackageReference, IsTopLevel: true);

            var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency, groupMatchers: [], allowCooldown: false);

            Assert.True(dependencyInfo.AllowPrerelease);
        }

        [Fact]
        public void AllowPrerelease_WildcardMatchingDependencyName_SetsAllowPrereleaseTrue()
        {
            var job = new Job()
            {
                AllowedUpdates =
                [
                    new AllowedUpdate() { DependencyName = "MyCompany.*", Prerelease = true },
                    new AllowedUpdate() { UpdateType = UpdateType.All },
                ],
                Source = new() { Provider = "github", Repo = "test/repo" },
            };
            var dependency = new Dependency("MyCompany.Utils", "1.0.0", DependencyType.PackageReference, IsTopLevel: true);

            var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency, groupMatchers: [], allowCooldown: false);

            Assert.True(dependencyInfo.AllowPrerelease);
        }

        [Fact]
        public void AllowPrerelease_NonMatchingDependencyName_SetsAllowPrereleaseFalse()
        {
            var job = new Job()
            {
                AllowedUpdates =
                [
                    new AllowedUpdate() { DependencyName = "Some.Package", Prerelease = true },
                    new AllowedUpdate() { UpdateType = UpdateType.All },
                ],
                Source = new() { Provider = "github", Repo = "test/repo" },
            };
            var dependency = new Dependency("Other.Package", "1.0.0", DependencyType.PackageReference, IsTopLevel: true);

            var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency, groupMatchers: [], allowCooldown: false);

            Assert.False(dependencyInfo.AllowPrerelease);
        }

        [Fact]
        public void AllowPrerelease_NoPrereleaseRule_SetsAllowPrereleaseFalse()
        {
            var job = new Job()
            {
                AllowedUpdates =
                [
                    new AllowedUpdate() { UpdateType = UpdateType.All },
                ],
                Source = new() { Provider = "github", Repo = "test/repo" },
            };
            var dependency = new Dependency("Some.Package", "1.0.0", DependencyType.PackageReference, IsTopLevel: true);

            var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency, groupMatchers: [], allowCooldown: false);

            Assert.False(dependencyInfo.AllowPrerelease);
        }

        [Fact]
        public void AllowPrerelease_NullDependencyName_AppliesToAllDependencies()
        {
            // An allowed update with no dependency-name and prerelease: true applies to all dependencies
            var job = new Job()
            {
                AllowedUpdates =
                [
                    new AllowedUpdate() { Prerelease = true },
                ],
                Source = new() { Provider = "github", Repo = "test/repo" },
            };
            var dependency = new Dependency("Any.Package", "1.0.0", DependencyType.PackageReference, IsTopLevel: true);

            var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency, groupMatchers: [], allowCooldown: false);

            Assert.True(dependencyInfo.AllowPrerelease);
        }
    }
}

