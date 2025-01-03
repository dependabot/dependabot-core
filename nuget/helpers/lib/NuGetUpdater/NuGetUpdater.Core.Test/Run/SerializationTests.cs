using NuGet.Versioning;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class SerializationTests
{
    [Fact]
    public void DeserializeJob()
    {
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "debug": false,
                "dependency-groups": [],
                "dependencies": null,
                "dependency-group-to-refresh": null,
                "existing-pull-requests": [],
                "existing-group-pull-requests": [],
                "experiments": null,
                "ignore-conditions": [],
                "lockfile-only": false,
                "requirements-update-strategy": null,
                "security-advisories": [],
                "security-updates-only": false,
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "specific-sdk",
                  "hostname": null,
                  "api-endpoint": null
                },
                "update-subdependencies": false,
                "updating-a-pull-request": false,
                "vendor-dependencies": false,
                "reject-external-code": false,
                "repo-private": false,
                "commit-message-options": null,
                "credentials-metadata": [
                  {
                    "host": "github.com",
                    "type": "git_source"
                  }
                ],
                "max-updater-run-time": 0
              }
            }
            """);
        Assert.Equal("github", jobWrapper.Job.Source.Provider);
        Assert.Equal("some-org/some-repo", jobWrapper.Job.Source.Repo);
        Assert.Equal("specific-sdk", jobWrapper.Job.Source.Directory);
    }

    [Fact]
    public void DeserializeJob_DebugIsNull()
    {
        // the `debug` field is defined as a `bool`, but can appear as `null` in the wild
        var jobContent = """
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "specific-sdk",
                  "hostname": null,
                  "api-endpoint": null
                },
                "debug": null
              }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jobContent);
        Assert.False(jobWrapper.Job.Debug);
    }

    [Fact]
    public void DeserializeJob_FieldsNotYetSupported()
    {
        // the `source` field is required in the C# model; the remaining fields might exist in the JSON file, but are
        // not yet supported in the C# model (some keys missing, others deserialize to `object?`; deserialization
        // should not fail
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "specific-sdk",
                  "hostname": null,
                  "api-endpoint": null
                },
                "id": "some-id",
                "allowed-updates": [
                  {
                    "dependency-type": "direct",
                    "update-type": "all"
                  }
                ],
                "credentials": [
                  {
                    "name": "some-cred",
                    "token": "abc123"
                  }
                ],
                "existing-pull-requests": [
                  [
                    {
                      "dependency-name": "Some.Package",
                      "dependency-version": "1.2.3"
                    }
                  ]
                ],
                "repo-contents-path": "/path/to/repo",
                "token": "abc123"
              }
            }
            """);
        Assert.Equal("github", jobWrapper.Job.Source.Provider);
        Assert.Equal("some-org/some-repo", jobWrapper.Job.Source.Repo);
        Assert.Equal("specific-sdk", jobWrapper.Job.Source.Directory);
    }

    [Fact]
    public void DeserializeExperimentsManager()
    {
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "some-dir"
                },
                "experiments": {
                  "nuget_legacy_dependency_solver": true,
                  "nuget_use_direct_discovery": true,
                  "unexpected_bool": true,
                  "unexpected_number": 42,
                  "unexpected_null": null,
                  "unexpected_string": "abc",
                  "unexpected_array": [1, "two", 3.0],
                  "unexpected_object": {
                    "a": 1,
                    "b": "two"
                  }
                }
              }
            }
            """);
        var experimentsManager = ExperimentsManager.GetExperimentsManager(jobWrapper.Job.Experiments);
        Assert.True(experimentsManager.UseLegacyDependencySolver);
        Assert.True(experimentsManager.UseDirectDiscovery);
    }

    [Fact]
    public void DeserializeExperimentsManager_EmptyExperiments()
    {
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "some-dir"
                },
                "experiments": {
                }
              }
            }
            """);
        var experimentsManager = ExperimentsManager.GetExperimentsManager(jobWrapper.Job.Experiments);
        Assert.False(experimentsManager.UseLegacyDependencySolver);
        Assert.False(experimentsManager.UseDirectDiscovery);
    }

    [Fact]
    public void DeserializeExperimentsManager_NoExperiments()
    {
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "some-dir"
                }
              }
            }
            """);
        var experimentsManager = ExperimentsManager.GetExperimentsManager(jobWrapper.Job.Experiments);
        Assert.False(experimentsManager.UseLegacyDependencySolver);
        Assert.False(experimentsManager.UseDirectDiscovery);
    }

    [Theory]
    [MemberData(nameof(DeserializeErrorTypesData))]
    public void SerializeError(JobErrorBase error, string expectedSerialization)
    {
        if (error is UnknownError unknown)
        {
            // special case the exception's call stack to make it testable
            unknown.Details["error-backtrace"] = "TEST-BACKTRACE";
        }

        var actual = HttpApiHandler.Serialize(error);
        Assert.Equal(expectedSerialization, actual);
    }

    [Fact]
    public void SerializeError_AllErrorTypesHaveSerializationTests()
    {
        var untestedTypes = typeof(JobErrorBase).Assembly.GetTypes()
            .Where(t => t.IsSubclassOf(typeof(JobErrorBase)))
            .ToHashSet();
        foreach (object?[] data in DeserializeErrorTypesData())
        {
            var testedErrorType = data[0]!.GetType();
            untestedTypes.Remove(testedErrorType);
        }

        Assert.Empty(untestedTypes.Select(t => t.Name));
    }

    [Fact]
    public void DeserializeJobIgnoreConditions()
    {
        var jobContent = """
            {
              "job": {
                "package-manager": "nuget",
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "specific-sdk"
                },
                "ignore-conditions": [
                  {
                    "dependency-name": "Package.1",
                    "source": "some-file",
                    "update-types": [
                      "version-update:semver-major"
                    ],
                    "version-requirement": "> 1.2.3"
                  },
                  {
                    "dependency-name": "Package.2",
                    "updated-at": "2024-12-05T15:47:12Z"
                  }
                ]
              }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jobContent)!;
        Assert.Equal(2, jobWrapper.Job.IgnoreConditions.Length);

        Assert.Equal("Package.1", jobWrapper.Job.IgnoreConditions[0].DependencyName);
        Assert.Equal("some-file", jobWrapper.Job.IgnoreConditions[0].Source);
        Assert.Equal("version-update:semver-major", jobWrapper.Job.IgnoreConditions[0].UpdateTypes.Single());
        Assert.Null(jobWrapper.Job.IgnoreConditions[0].UpdatedAt);
        Assert.Equal("> 1.2.3", jobWrapper.Job.IgnoreConditions[0].VersionRequirement?.ToString());

        Assert.Equal("Package.2", jobWrapper.Job.IgnoreConditions[1].DependencyName);
        Assert.Null(jobWrapper.Job.IgnoreConditions[1].Source);
        Assert.Empty(jobWrapper.Job.IgnoreConditions[1].UpdateTypes);
        Assert.Equal(new DateTime(2024, 12, 5, 15, 47, 12), jobWrapper.Job.IgnoreConditions[1].UpdatedAt);
        Assert.Null(jobWrapper.Job.IgnoreConditions[1].VersionRequirement);
    }

    [Theory]
    [MemberData(nameof(DeserializeAllowedUpdatesData))]
    public void DeserializeAllowedUpdates(string? allowedUpdatesJsonBody, AllowedUpdate[] expectedAllowedUpdates)
    {
        string? allowedUpdatesJson = allowedUpdatesJsonBody is null
            ? null
            : $$"""
                ,
                "allowed-updates": {{allowedUpdatesJsonBody}}
                """;
        var jobWrapperJson = $$"""
            {
                "job": {
                    "source": {
                        "provider": "github",
                        "repo": "some/repo"
                    }
                    {{allowedUpdatesJson}}
                }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jobWrapperJson)!;
        AssertEx.Equal(expectedAllowedUpdates, jobWrapper.Job.AllowedUpdates);
    }

    [Fact]
    public void DeserializeDependencyGroups()
    {
        var jsonWrapperJson = """
            {
                "job": {
                    "source": {
                        "provider": "github",
                        "repo": "some/repo"
                    },
                    "dependency-groups": [
                        {
                            "name": "Some.Dependency",
                            "rules": {
                                "patterns": ["1.2.3", "4.5.6"]
                            }
                        },
                        {
                            "name": "Some.Other.Dependency",
                            "applies-to": "something"
                        }
                    ]
                }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jsonWrapperJson)!;
        Assert.Equal(2, jobWrapper.Job.DependencyGroups.Length);

        Assert.Equal("Some.Dependency", jobWrapper.Job.DependencyGroups[0].Name);
        Assert.Null(jobWrapper.Job.DependencyGroups[0].AppliesTo);
        Assert.Single(jobWrapper.Job.DependencyGroups[0].Rules);
        Assert.Equal("[\"1.2.3\", \"4.5.6\"]", jobWrapper.Job.DependencyGroups[0].Rules["patterns"].ToString());

        Assert.Equal("Some.Other.Dependency", jobWrapper.Job.DependencyGroups[1].Name);
        Assert.Equal("something", jobWrapper.Job.DependencyGroups[1].AppliesTo);
        Assert.Empty(jobWrapper.Job.DependencyGroups[1].Rules);
    }

    [Fact]
    public void DeserializeExistingPullRequests()
    {
        var jsonWrapperJson = """
            {
                "job": {
                    "source": {
                        "provider": "github",
                        "repo": "some/repo"
                    },
                    "existing-pull-requests": [
                        [
                            {
                                "dependency-name": "Some.Package",
                                "dependency-version": "1.2.3"
                            }
                        ]
                    ]
                }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jsonWrapperJson)!;
        Assert.Single(jobWrapper.Job.ExistingPullRequests);
        Assert.Single(jobWrapper.Job.ExistingPullRequests[0]);
        Assert.Equal("Some.Package", jobWrapper.Job.ExistingPullRequests[0][0].DependencyName);
        Assert.Equal(NuGetVersion.Parse("1.2.3"), jobWrapper.Job.ExistingPullRequests[0][0].DependencyVersion);
        Assert.False(jobWrapper.Job.ExistingPullRequests[0][0].DependencyRemoved);
        Assert.Null(jobWrapper.Job.ExistingPullRequests[0][0].Directory);
    }

    [Fact]
    public void DeserializeExistingGroupPullRequests()
    {
        var jsonWrapperJson = """
            {
                "job": {
                    "source": {
                        "provider": "github",
                        "repo": "some/repo"
                    },
                    "existing-group-pull-requests": [
                        {
                            "dependency-group-name": "Some-Group-Name",
                            "dependencies": [
                                {
                                    "dependency-name": "Some.Package",
                                    "dependency-version": "1.2.3"
                                },
                                {
                                    "dependency-name": "Some.Other.Package",
                                    "dependency-version": "4.5.6",
                                    "directory": "/some-dir"
                                }
                            ]
                        }
                    ]
                }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jsonWrapperJson)!;
        Assert.Single(jobWrapper.Job.ExistingGroupPullRequests);
        Assert.Equal("Some-Group-Name", jobWrapper.Job.ExistingGroupPullRequests[0].DependencyGroupName);
        Assert.Equal(2, jobWrapper.Job.ExistingGroupPullRequests[0].Dependencies.Length);
        Assert.Equal("Some.Package", jobWrapper.Job.ExistingGroupPullRequests[0].Dependencies[0].DependencyName);
        Assert.Equal("1.2.3", jobWrapper.Job.ExistingGroupPullRequests[0].Dependencies[0].DependencyVersion.ToString());
        Assert.Null(jobWrapper.Job.ExistingGroupPullRequests[0].Dependencies[0].Directory);
        Assert.Equal("Some.Other.Package", jobWrapper.Job.ExistingGroupPullRequests[0].Dependencies[1].DependencyName);
        Assert.Equal("4.5.6", jobWrapper.Job.ExistingGroupPullRequests[0].Dependencies[1].DependencyVersion.ToString());
        Assert.Equal("/some-dir", jobWrapper.Job.ExistingGroupPullRequests[0].Dependencies[1].Directory);
    }

    [Theory]
    [InlineData("null", null)]
    [InlineData("\"bump_versions\"", RequirementsUpdateStrategy.BumpVersions)]
    [InlineData("\"lockfile_only\"", RequirementsUpdateStrategy.LockfileOnly)]
    public void DeserializeRequirementsUpdateStrategy(string requirementsUpdateStrategyStringJson, RequirementsUpdateStrategy? expectedRequirementsUpdateStrategy)
    {
        var jsonWrapperJson = $$"""
            {
                "job": {
                    "source": {
                        "provider": "github",
                        "repo": "some/repo"
                    },
                    "requirements-update-strategy": {{requirementsUpdateStrategyStringJson}}
                }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jsonWrapperJson)!;
        var actualRequirementsUpdateStrategy = jobWrapper.Job.RequirementsUpdateStrategy;
        Assert.Equal(expectedRequirementsUpdateStrategy, actualRequirementsUpdateStrategy);
    }

    [Fact]
    public void DeserializeSecurityAdvisories()
    {
        var jsonWrapperJson = """
            {
                "job": {
                    "source": {
                        "provider": "github",
                        "repo": "some/repo"
                    },
                    "security-advisories": [
                        {
                            "dependency-name": "Some.Package",
                            "affected-versions": [
                                ">= 1.0.0, < 1.2.0"
                            ],
                            "patched-versions": null
                        }
                    ]
                }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jsonWrapperJson)!;
        Assert.Single(jobWrapper.Job.SecurityAdvisories);
        Assert.Equal("Some.Package", jobWrapper.Job.SecurityAdvisories[0].DependencyName);
        Assert.Equal(">= 1.0.0, < 1.2.0", jobWrapper.Job.SecurityAdvisories[0].AffectedVersions!.Value.Single().ToString());
        Assert.Null(jobWrapper.Job.SecurityAdvisories[0].PatchedVersions);
        Assert.Null(jobWrapper.Job.SecurityAdvisories[0].PatchedVersions);
    }

    [Fact]
    public void DeserializeCommitOptions()
    {
        var jsonWrapperJson = """
            {
                "job": {
                    "source": {
                        "provider": "github",
                        "repo": "some/repo"
                    },
                    "commit-message-options": {
                        "prefix": "[SECURITY] "
                    }
                }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jsonWrapperJson)!;
        Assert.Equal("[SECURITY] ", jobWrapper.Job.CommitMessageOptions!.Prefix);
        Assert.Null(jobWrapper.Job.CommitMessageOptions!.PrefixDevelopment);
        Assert.Null(jobWrapper.Job.CommitMessageOptions!.IncludeScope);
    }

    public static IEnumerable<object?[]> DeserializeErrorTypesData()
    {
        yield return
        [
            new BadRequirement("some message"),
            """
            {"data":{"error-type":"illformed_requirement","error-details":{"message":"some message"}}}
            """
        ];

        yield return
        [
            new DependencyFileNotFound("some message", "/some/file"),
            """
            {"data":{"error-type":"dependency_file_not_found","error-details":{"message":"some message","file-path":"/some/file"}}}
            """
        ];

        yield return
        [
            new JobRepoNotFound("some message"),
            """
            {"data":{"error-type":"job_repo_not_found","error-details":{"message":"some message"}}}
            """
        ];

        yield return
        [
            new PrivateSourceAuthenticationFailure(["url1", "url2"]),
            """
            {"data":{"error-type":"private_source_authentication_failure","error-details":{"source":"(url1|url2)"}}}
            """
        ];

        yield return
        [
            new UnknownError(new Exception("some message"), "JOB-ID"),
            """
            {"data":{"error-type":"unknown_error","error-details":{"error-class":"Exception","error-message":"some message","error-backtrace":"TEST-BACKTRACE","package-manager":"nuget","job-id":"JOB-ID"}}}
            """
        ];

        yield return
        [
            new UpdateNotPossible(["dep1", "dep2"]),
            """
            {"data":{"error-type":"update_not_possible","error-details":{"dependencies":["dep1","dep2"]}}}
            """
        ];
    }

    public static IEnumerable<object?[]> DeserializeAllowedUpdatesData()
    {
        // common default value - most job files look like this
        yield return
        [
            // allowedUpdatesJsonBody
            """
            [
                {
                    "update-type": "all"
                }
            ]
            """,
            // expectedAllowedUpdates
            new[]
            {
                new AllowedUpdate()
                {
                    DependencyType = Core.Run.ApiModel.DependencyType.All,
                    DependencyName = null,
                    UpdateType = UpdateType.All
                }
            }
        ];

        // allowed updates is missing - ensure proper defaults
        yield return
        [
            // allowedUpdatesJsonBody
            null,
            // expectedAllowedUpdates
            new[]
            {
                new AllowedUpdate()
            }
        ];

        // multiple non-default values
        yield return
        [
            // allowedUpdatesJsonBody
            """
            [
                {
                    "dependency-type": "indirect",
                    "dependency-name": "Dependency.One",
                    "update-type": "security"
                },
                {
                    "dependency-type": "production",
                    "dependency-name": "Dependency.Two",
                    "update-type": "all"
                },
                {
                    "dependency-type": "indirect",
                    "update-type": "security"
                }
            ]
            """,
            new[]
            {
                new AllowedUpdate()
                {
                    DependencyType = Core.Run.ApiModel.DependencyType.Indirect,
                    DependencyName = "Dependency.One",
                    UpdateType = UpdateType.Security
                },
                new AllowedUpdate()
                {
                    DependencyType = Core.Run.ApiModel.DependencyType.Production,
                    DependencyName = "Dependency.Two",
                    UpdateType = UpdateType.All
                },
                new AllowedUpdate()
                {
                    DependencyType = Core.Run.ApiModel.DependencyType.Indirect,
                    DependencyName = null,
                    UpdateType = UpdateType.Security
                }
            }
        ];
    }
}
