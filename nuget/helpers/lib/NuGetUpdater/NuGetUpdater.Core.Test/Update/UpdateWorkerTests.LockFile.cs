using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class LockFile : UpdateWorkerTestBase
    {
        [Fact]
        public async Task UpdateSingleDependency()
        {
            // update Newtonsoft.Json from 13.0.1 to 13.0.3
            await TestUpdateForProject("Newtonsoft.Json", "13.0.1", "13.0.3",
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("packages.lock.json", """
                        {
                          "version": 1,
                          "dependencies": {
                            "net8.0": {
                              "Newtonsoft.Json": {
                                "type": "Direct",
                                "requested": "[13.0.1, )",
                                "resolved": "13.0.1",
                                "contentHash": "ppPFpBcvxdsfUonNcvITKqLl3bqxWbDCZIzDWHzjpdAHRFfZe0Dw9HmA0+za13IdyrgJwpkDTDA9fHaxOrt20A=="
                              }
                            }
                          }
                        }
                        """)
                ],
                additionalFilesExpected:
                [
                    ("packages.lock.json", """
                        {
                          "version": 1,
                          "dependencies": {
                            "net8.0": {
                              "Newtonsoft.Json": {
                                "type": "Direct",
                                "requested": "[13.0.3, )",
                                "resolved": "13.0.3",
                                "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
                              }
                            }
                          }
                        }
                        """)
                ]
            );
        }
        
        [Fact]
        public async Task UpdateSingleDependency_CentralPackageManagement()
        {
            // update Newtonsoft.Json from 13.0.1 to 13.0.3
            await TestUpdateForProject("Newtonsoft.Json", "13.0.1", "13.0.3",
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("packages.lock.json", """
                        {
                          "version": 2,
                          "dependencies": {
                            "net8.0": {
                              "Newtonsoft.Json": {
                                "type": "Direct",
                                "requested": "[13.0.1, )",
                                "resolved": "13.0.1",
                                "contentHash": "ppPFpBcvxdsfUonNcvITKqLl3bqxWbDCZIzDWHzjpdAHRFfZe0Dw9HmA0+za13IdyrgJwpkDTDA9fHaxOrt20A=="
                              }
                            }
                          }
                        }
                        """),
                    ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                    
                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
                ],
                additionalFilesExpected:
                [
                    ("packages.lock.json", """
                        {
                          "version": 2,
                          "dependencies": {
                            "net8.0": {
                              "Newtonsoft.Json": {
                                "type": "Direct",
                                "requested": "[13.0.3, )",
                                "resolved": "13.0.3",
                                "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
                              }
                            }
                          }
                        }
                        """),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                        
                          <ItemGroup>
                            <PackageVersion Include="Newtonsoft.Json" Version="13.0.3" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }
        
        [Fact]
        public async Task UpdateSingleDependency_WindowsSpecific()
        {
            // update Newtonsoft.Json from 13.0.1 to 13.0.3
            await TestUpdateForProject("Newtonsoft.Json", "13.0.1", "13.0.3",
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows</TargetFramework>
                        <UseWindowsForms>true</UseWindowsForms>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows</TargetFramework>
                        <UseWindowsForms>true</UseWindowsForms>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("packages.lock.json", """
                        {
                          "version": 1,
                          "dependencies": {
                            "net8.0-windows7.0": {
                              "Newtonsoft.Json": {
                                "type": "Direct",
                                "requested": "[13.0.1, )",
                                "resolved": "13.0.1",
                                "contentHash": "ppPFpBcvxdsfUonNcvITKqLl3bqxWbDCZIzDWHzjpdAHRFfZe0Dw9HmA0+za13IdyrgJwpkDTDA9fHaxOrt20A=="
                              }
                            }
                          }
                        }
                        """)
                ],
                additionalFilesExpected:
                [
                    ("packages.lock.json", """
                        {
                          "version": 1,
                          "dependencies": {
                            "net8.0-windows7.0": {
                              "Newtonsoft.Json": {
                                "type": "Direct",
                                "requested": "[13.0.3, )",
                                "resolved": "13.0.3",
                                "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
                              }
                            }
                          }
                        }
                        """)
                ]
            );
        }
        
        [Fact]
        public async Task UpdateSingleDependency_CentralPackageManagement_WindowsSpecific()
        {
            // update Newtonsoft.Json from 13.0.1 to 13.0.3
            await TestUpdateForProject("Newtonsoft.Json", "13.0.1", "13.0.3",
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows</TargetFramework>
                        <UseWindowsForms>true</UseWindowsForms>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows</TargetFramework>
                        <UseWindowsForms>true</UseWindowsForms>
                        <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("packages.lock.json", """
                        {
                          "version": 2,
                          "dependencies": {
                            "net8.0-windows7.0": {
                              "Newtonsoft.Json": {
                                "type": "Direct",
                                "requested": "[13.0.1, )",
                                "resolved": "13.0.1",
                                "contentHash": "ppPFpBcvxdsfUonNcvITKqLl3bqxWbDCZIzDWHzjpdAHRFfZe0Dw9HmA0+za13IdyrgJwpkDTDA9fHaxOrt20A=="
                              }
                            }
                          }
                        }
                        """),
                    ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                    
                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
                ],
                additionalFilesExpected:
                [
                    ("packages.lock.json", """
                        {
                          "version": 2,
                          "dependencies": {
                            "net8.0-windows7.0": {
                              "Newtonsoft.Json": {
                                "type": "Direct",
                                "requested": "[13.0.3, )",
                                "resolved": "13.0.3",
                                "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
                              }
                            }
                          }
                        }
                        """),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                        
                          <ItemGroup>
                            <PackageVersion Include="Newtonsoft.Json" Version="13.0.3" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }
    }
}
