using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Linq;

using Microsoft.Language.Xml;

using Xunit;

namespace NuGetUpdater.Core.Test.Files;

public class PackagesConfigBuildFileTests
{
    [StringSyntax(StringSyntaxAttribute.Xml)]
    const string PackagesConfig = """
        <?xml version="1.0" encoding="utf-8"?>
        <packages>
          <package id="Microsoft.CodeDom.Providers.DotNetCompilerPlatform" version="1.0.0" targetFramework="net46" />
          <package id="Microsoft.Net.Compilers" version="1.0.0" targetFramework="net46" developmentDependency="true" />
          <package id="Newtonsoft.Json" version="8.0.3" allowedVersions="[8,10)" targetFramework="net46" />
        </packages>
        """;

    [StringSyntax(StringSyntaxAttribute.Xml)]
    const string EmptyPackagesConfig = """
        <?xml version="1.0" encoding="utf-8"?>
        <packages>
        </packages>
        """;

    private static PackagesConfigBuildFile GetBuildFile(string contents) => new(
        repoRootPath: "/",
        path: "/packages.config",
        contents: Parser.ParseText(contents));

    [Fact]
    public void PackagesConfig_GetDependencies_ReturnsDependencies()
    {
        var expectedDependencies = new List<Dependency>
        {
            new("Microsoft.CodeDom.Providers.DotNetCompilerPlatform", "1.0.0", DependencyType.PackageConfig),
            new("Microsoft.Net.Compilers", "1.0.0", DependencyType.PackageConfig, IsDevDependency: true),
            new("Newtonsoft.Json", "8.0.3", DependencyType.PackageConfig)
        };

        var buildFile = GetBuildFile(PackagesConfig);

        var dependencies = buildFile.GetDependencies();

        Assert.Equal(expectedDependencies, dependencies);
    }

    [Fact]
    public void EmptyPackagesConfig_GetDependencies_ReturnsNoDependencies()
    {
        var expectedDependencies = Enumerable.Empty<Dependency>();

        var buildFile = GetBuildFile(EmptyPackagesConfig);

        var dependencies = buildFile.GetDependencies();

        Assert.Equal(expectedDependencies, dependencies);
    }
}
