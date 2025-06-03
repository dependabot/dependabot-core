using NuGet.Versioning;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class SerializationTests : TestBase
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
                    "type": "git_source",
                    "replaces-base": false
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
                    "token": "abc123",
                    "replaces-base": false
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

    [Fact]
    public void DeserializeExperimentsManager_AlternateNames()
    {
        // experiment names can be either snake case or kebab case
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
                  "nuget-legacy-dependency-solver": true,
                  "nuget-use-direct-discovery": true
                }
              }
            }
            """);
        var experimentsManager = ExperimentsManager.GetExperimentsManager(jobWrapper.Job.Experiments);
        Assert.True(experimentsManager.UseLegacyDependencySolver);
        Assert.True(experimentsManager.UseDirectDiscovery);
    }

    [Theory]
    [MemberData(nameof(SerializeErrorTypesData))]
    public void SerializeError(JobErrorBase error, string expectedSerialization)
    {
        var actual = HttpApiHandler.Serialize(error);
        Assert.Equal(expectedSerialization, actual);
    }

    [Fact]
    public void SerializeError_AllErrorTypesHaveSerializationTests()
    {
        var untestedTypes = typeof(JobErrorBase).Assembly.GetTypes()
            .Where(t => t.IsSubclassOf(typeof(JobErrorBase)))
            .ToHashSet();
        foreach (object?[] data in SerializeErrorTypesData())
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
        Assert.Single(jobWrapper.Job.ExistingPullRequests[0].Dependencies);
        Assert.Equal("Some.Package", jobWrapper.Job.ExistingPullRequests[0].Dependencies[0].DependencyName);
        Assert.Equal(NuGetVersion.Parse("1.2.3"), jobWrapper.Job.ExistingPullRequests[0].Dependencies[0].DependencyVersion);
        Assert.False(jobWrapper.Job.ExistingPullRequests[0].Dependencies[0].DependencyRemoved);
        Assert.Null(jobWrapper.Job.ExistingPullRequests[0].Dependencies[0].Directory);
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

    [Theory]
    [InlineData("true", true)] // bool
    [InlineData("false", false)]
    [InlineData("\"true\"", true)] // stringified bool
    [InlineData("\"false\"", false)]
    [InlineData("null", false)]
    public void DeserializeCommitOptions(string includeScopeJsonValue, bool expectedIncludeScopeValue)
    {
        var jsonWrapperJson = $$"""
            {
                "job": {
                    "source": {
                        "provider": "github",
                        "repo": "some/repo"
                    },
                    "commit-message-options": {
                        "prefix": "[SECURITY] ",
                        "prefix-development": null,
                        "include-scope": {{includeScopeJsonValue}}
                    }
                }
            }
            """;
        var jobWrapper = RunWorker.Deserialize(jsonWrapperJson)!;
        Assert.Equal("[SECURITY] ", jobWrapper.Job.CommitMessageOptions!.Prefix);
        Assert.Null(jobWrapper.Job.CommitMessageOptions!.PrefixDevelopment);
        Assert.Equal(expectedIncludeScopeValue, jobWrapper.Job.CommitMessageOptions!.IncludeScope);
    }

    [Fact]
    public void SerializeClosePullRequest()
    {
        var close = new ClosePullRequest()
        {
            DependencyNames = ["dep"],
        };
        var actual = HttpApiHandler.Serialize(close);
        var expected = """
            {"data":{"dependency-names":["dep"],"reason":"up_to_date"}}
            """;
        Assert.Equal(expected, actual);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void SerializeCreatePullRequest(bool withDependencyGroupName)
    {
        var dependencyGroupName = withDependencyGroupName
            ? "test-group"
            : null;
        var create = new CreatePullRequest()
        {
            Dependencies = [new() { Name = "dep", Version = "ver2", PreviousVersion = "ver1", Requirements = [new() { Requirement = "ver2", File = "project.csproj" }], PreviousRequirements = [new() { Requirement = "ver1", File = "project.csproj" }] }],
            UpdatedDependencyFiles = [new() { Name = "project.csproj", Directory = "/", Content = "updated content" }],
            BaseCommitSha = "TEST-COMMIT-SHA",
            CommitMessage = "commit message",
            PrTitle = "pr title",
            PrBody = "pr body",
            DependencyGroup = dependencyGroupName,
        };
        var actual = HttpApiHandler.Serialize(create);

        var expectedDependencyGroupValue = withDependencyGroupName
            ? """{"name":"test-group"}"""
            : "null";
        var expected = $$$"""
            {"data":{"dependencies":[{"name":"dep","version":"ver2","requirements":[{"requirement":"ver2","file":"project.csproj","groups":[],"source":null}],"previous-version":"ver1","previous-requirements":[{"requirement":"ver1","file":"project.csproj","groups":[],"source":null}]}],"updated-dependency-files":[{"name":"project.csproj","content":"updated content","directory":"/","type":"file","support_file":false,"content_encoding":"utf-8","deleted":false,"operation":"update","mode":null}],"base-commit-sha":"TEST-COMMIT-SHA","commit-message":"commit message","pr-title":"pr title","pr-body":"pr body","dependency-group":{{{expectedDependencyGroupValue}}}}}
            """;
        Assert.Equal(expected, actual);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void SerializeUpdatePullRequest(bool withDependencyGroupName)
    {
        var dependencyGroupName = withDependencyGroupName
            ? "test-group"
            : null;
        var update = new UpdatePullRequest()
        {
            BaseCommitSha = "TEST-COMMIT-SHA",
            DependencyNames = ["dep"],
            UpdatedDependencyFiles = [new() { Name = "project.csproj", Directory = "/", Content = "updated content" }],
            PrTitle = "pr title",
            PrBody = "pr body",
            CommitMessage = "commit message",
            DependencyGroup = dependencyGroupName,
        };
        var actual = HttpApiHandler.Serialize(update);

        var expectedDependencyGroupValue = withDependencyGroupName
            ? """{"name":"test-group"}"""
            : "null";
        var expected = $$$"""
            {"data":{"base-commit-sha":"TEST-COMMIT-SHA","dependency-names":["dep"],"updated-dependency-files":[{"name":"project.csproj","content":"updated content","directory":"/","type":"file","support_file":false,"content_encoding":"utf-8","deleted":false,"operation":"update","mode":null}],"pr-title":"pr title","pr-body":"pr body","commit-message":"commit message","dependency-group":{{{expectedDependencyGroupValue}}}}}
            """;
        Assert.Equal(expected, actual);
    }

    [Fact]
    public void SerializeRealUnknownErrorWithInnerException()
    {
        // arrange
        using var tempDir = new TemporaryDirectory();
        var action = new Action(() =>
        {
            try
            {
                throw new NotImplementedException("inner message");
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException("outer message", ex);
            }
        });
        var ex = Assert.Throws<InvalidOperationException>(action);

        // act
        var error = JobErrorBase.ErrorFromException(ex, "TEST-JOB-ID", tempDir.DirectoryPath);

        // assert
        // real exception message should look like this:
        // System.InvalidOperationException: outer message
        //  ---> System.NotImplementedException: inner message
        //    at Namespace.Class.Method() in file.cs:line 123
        //    --- End of inner exception stack trace ---
        //    at Namespace.Class.Method() in file.cs:line 456
        var errorMessage = Assert.IsType<string>(error.Details["error-message"]);
        var lines = errorMessage.Split('\n').Select(l => l.TrimEnd('\r')).ToArray();
        Assert.Equal("System.InvalidOperationException: outer message", lines[0]);
        Assert.Equal(" ---> System.NotImplementedException: inner message", lines[1]);
        Assert.Contains("   --- End of inner exception stack trace ---", lines[2..]);
    }

    public static IEnumerable<object?[]> SerializeErrorTypesData()
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
            new DependencyFileNotFound("/some/file", "some message"),
            """
            {"data":{"error-type":"dependency_file_not_found","error-details":{"message":"some message","file-path":"/some/file"}}}
            """
        ];

        yield return
        [
            new DependencyFileNotParseable("/some/file", "some message"),
            """
            {"data":{"error-type":"dependency_file_not_parseable","error-details":{"message":"some message","file-path":"/some/file"}}}
            """
        ];

        yield return
        [
            new DependencyNotFound("some source"),
            """
            {"data":{"error-type":"dependency_not_found","error-details":{"source":"some source"}}}
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
            new PrivateSourceBadResponse(["url1", "url2"]),
            """
            {"data":{"error-type":"private_source_bad_response","error-details":{"source":"(url1|url2)"}}}
            """
        ];

        yield return
        [
            new PullRequestExistsForLatestVersion("dep", "ver"),
            """
            {"data":{"error-type":"pull_request_exists_for_latest_version","error-details":{"dependency-name":"dep","dependency-version":"ver"}}}
            """
        ];

        yield return
        [
            new PullRequestExistsForSecurityUpdate([new("dep", "ver", DependencyType.PackageReference)]),
            """
            {"data":{"error-type":"pull_request_exists_for_security_update","error-details":{"updated-dependencies":[{"dependency-name":"dep","dependency-version":"ver","dependency-removed":false}]}}}
            """
        ];

        yield return
        [
            new SecurityUpdateDependencyNotFound(),
            """
            {"data":{"error-type":"security_update_dependency_not_found","error-details":{}}}
            """
        ];

        yield return
        [
            new SecurityUpdateIgnored("dep"),
            """
            {"data":{"error-type":"all_versions_ignored","error-details":{"dependency-name":"dep"}}}
            """
        ];

        yield return
        [
            new SecurityUpdateNotFound("dep", "ver"),
            """
            {"data":{"error-type":"security_update_not_found","error-details":{"dependency-name":"dep","dependency-version":"ver"}}}
            """
        ];

        yield return
        [
            new SecurityUpdateNotNeeded("dep"),
            """
            {"data":{"error-type":"security_update_not_needed","error-details":{"dependency-name":"dep"}}}
            """
        ];

        yield return
        [
            new SecurityUpdateNotPossible("dep", "ver1", "ver2", []),
            """
            {"data":{"error-type":"security_update_not_possible","error-details":{"dependency-name":"dep","latest-resolvable-version":"ver1","lowest-non-vulnerable-version":"ver2","conflicting-dependencies":[]}}}
            """
        ];

        yield return
        [
            new UnknownError(new Exception("some message"), "JOB-ID"),
            """
            {"data":{"error-type":"unknown_error","error-details":{"error-class":"Exception","error-message":"System.Exception: some message","error-backtrace":"","package-manager":"nuget","job-id":"JOB-ID"}}}
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
