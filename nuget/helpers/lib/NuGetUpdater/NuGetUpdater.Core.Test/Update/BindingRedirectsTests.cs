using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class BindingRedirectsTests
{
    [Fact]
    public async Task SimpleBindingRedirectIsPerformed()
    {
        await VerifyBindingRedirectsAsync(
            projectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=2.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.2.0.0\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            configContents: """
                <configuration>
                  <runtime>
                    <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                      <dependentAssembly>
                        <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                        <bindingRedirect oldVersion="0.0.0.0-1.0.0.0" newVersion="1.0.0.0" />
                      </dependentAssembly>
                    </assemblyBinding>
                  </runtime>
                </configuration>
                """,
            expectedConfigContents: """
                <configuration>
                  <runtime>
                    <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                      <dependentAssembly>
                        <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                        <bindingRedirect oldVersion="0.0.0.0-2.0.0.0" newVersion="2.0.0.0" />
                      </dependentAssembly>
                    </assemblyBinding>
                  </runtime>
                </configuration>
                """
        );
    }

    [Fact]
    public async Task ConfigFileIndentationIsPreserved()
    {
        await VerifyBindingRedirectsAsync(
            projectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=2.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.2.0.0\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            configContents: """
                    <configuration>
                   <runtime>
                  <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                 <dependentAssembly>
                <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                <bindingRedirect oldVersion="0.0.0.0-1.0.0.0" newVersion="1.0.0.0" />
                 </dependentAssembly>
                  </assemblyBinding>
                   </runtime>
                    </configuration>
                """,
            expectedConfigContents: """
                    <configuration>
                   <runtime>
                  <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                 <dependentAssembly>
                <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                <bindingRedirect oldVersion="0.0.0.0-2.0.0.0" newVersion="2.0.0.0" />
                 </dependentAssembly>
                  </assemblyBinding>
                   </runtime>
                    </configuration>
                """
        );
    }

    private static async Task VerifyBindingRedirectsAsync(string projectContents, string configContents, string expectedConfigContents, string configFileName = "app.config")
    {
        using var tempDir = new TemporaryDirectory();
        var projectFileName = "project.csproj";
        var projectFilePath = Path.Combine(tempDir.DirectoryPath, projectFileName);
        var configFilePath = Path.Combine(tempDir.DirectoryPath, configFileName);

        await File.WriteAllTextAsync(projectFilePath, projectContents);
        await File.WriteAllTextAsync(configFilePath, configContents);

        var projectBuildFile = ProjectBuildFile.Open(tempDir.DirectoryPath, projectFilePath);
        await BindingRedirectManager.UpdateBindingRedirectsAsync(projectBuildFile);

        var actualConfigContents = (await File.ReadAllTextAsync(configFilePath)).Replace("\r", "");
        expectedConfigContents = expectedConfigContents.Replace("\r", "");
        Assert.Equal(expectedConfigContents, actualConfigContents);
    }
}
