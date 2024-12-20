using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class LockFile : UpdateWorkerTestBase
    {
        [Fact]
        public async Task UpdateSingleDependency()
        {
            await TestUpdateForProject("Some.Package", "1.0.0", "2.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("packages.lock.json", "{}")
                ],
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalChecks: path =>
                {
                    var lockContents = File.ReadAllText(Path.Combine(path, "packages.lock.json"));
                    Assert.Contains("\"resolved\": \"2.0.0\"", lockContents);
                }
            );
        }

        [Fact]
        public async Task UpdateSingleDependency_CentralPackageManagement()
        {
            await TestUpdateForProject("Some.Package", "1.0.0", "2.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("packages.lock.json", "{}"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                    
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                        
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="2.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                additionalChecks: path =>
                {
                    var lockContents = File.ReadAllText(Path.Combine(path, "packages.lock.json"));
                    Assert.Contains("\"resolved\": \"2.0.0\"", lockContents);
                }
            );
        }

        [Fact]
        public async Task UpdateSingleDependency_WindowsSpecific()
        {
            await TestUpdateForProject("Some.Package", "1.0.0", "2.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows</TargetFramework>
                        <UseWindowsForms>true</UseWindowsForms>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("packages.lock.json", "{}")
                ],
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows</TargetFramework>
                        <UseWindowsForms>true</UseWindowsForms>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalChecks: path =>
                {
                    var lockContents = File.ReadAllText(Path.Combine(path, "packages.lock.json"));
                    Assert.Contains("\"resolved\": \"2.0.0\"", lockContents);
                }
            );
        }

        [Fact]
        public async Task UpdateSingleDependency_CentralPackageManagement_WindowsSpecific()
        {
            await TestUpdateForProject("Some.Package", "1.0.0", "2.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows</TargetFramework>
                        <UseWindowsForms>true</UseWindowsForms>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("packages.lock.json", "{}"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                    
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows</TargetFramework>
                        <UseWindowsForms>true</UseWindowsForms>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                        
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="2.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                additionalChecks: path =>
                {
                    var lockContents = File.ReadAllText(Path.Combine(path, "packages.lock.json"));
                    Assert.Contains("\"resolved\": \"2.0.0\"", lockContents);
                }
            );
        }
    }
}
