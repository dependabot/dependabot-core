using System;
using System.Collections.Generic;

using NuGetUpdater.Core.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class JsonHelperTests
{
    [Theory]
    [MemberData(nameof(JsonUpdaterTestData))]
    public void UpdateJsonPreservingComments(string json, string[] propertyPath, string newValue, string expectedJson)
    {
        var updatedJson = JsonHelper.UpdateJsonProperty(json, propertyPath, newValue, StringComparison.OrdinalIgnoreCase).Replace("\r", string.Empty);
        expectedJson = expectedJson.Replace("\r", string.Empty);
        Assert.Equal(expectedJson, updatedJson);
    }

    public static IEnumerable<object[]> JsonUpdaterTestData()
    {
        yield return
        [
            // json
            """
            {
              // this is a comment
              "version": 1,
              "isRoot": true,
              "tools": {
                "microsoft.botsay": {
                  // this is a deep comment
                  "version": "1.0.0",
                  "commands": [
                    "botsay"
                  ]
                },
                "dotnetsay": {
                  "version": "2.1.3",
                  "commands": [ // end of line comment
                    "dotnetsay"
                  ]
                }
              }
            }
            """,
            // property path
            new[]
            {
                "tools",
                "microsoft.botsay",
                "version"
            },
            // new value
            "1.1.0",
            // expected json
            """
            {
              // this is a comment
              "version": 1,
              "isRoot": true,
              "tools": {
                "microsoft.botsay": {
                  // this is a deep comment
                  "version": "1.1.0",
                  "commands": [
                    "botsay"
                  ]
                },
                "dotnetsay": {
                  "version": "2.1.3",
                  "commands": [ // end of line comment
                    "dotnetsay"
                  ]
                }
              }
            }
            """
        ];

        yield return
        [
            // json
            """
            {
              // Defines version of MSBuild project SDKs to use
              // https://docs.microsoft.com/en-us/visualstudio/msbuild/how-to-use-project-sdk?view=vs-2017#how-project-sdks-are-resolved
              // https://docs.microsoft.com/en-us/dotnet/core/tools/global-json#globaljson-schema
              "msbuild-sdks": {
                "Microsoft.Build.Traversal": "4.1.0",
                "Microsoft.Build.NoTargets": "3.6.0"
              },
              "sdk": {
                "version": "6.0.400",
                "rollForward": "latestMajor"
              }
            }
            """,
            // property path
            new[]
            {
                "msbuild-sdks",
                "Microsoft.Build.NoTargets"
            },
            // new value
            "3.7.0",
            // expected json
            """
            {
              // Defines version of MSBuild project SDKs to use
              // https://docs.microsoft.com/en-us/visualstudio/msbuild/how-to-use-project-sdk?view=vs-2017#how-project-sdks-are-resolved
              // https://docs.microsoft.com/en-us/dotnet/core/tools/global-json#globaljson-schema
              "msbuild-sdks": {
                "Microsoft.Build.Traversal": "4.1.0",
                "Microsoft.Build.NoTargets": "3.7.0"
              },
              "sdk": {
                "version": "6.0.400",
                "rollForward": "latestMajor"
              }
            }
            """
        ];

        // differing case between `propertyPath` and the actual property values
        yield return
        [
            // json
            """
            {
              "version": 1,
              "isRoot": true,
              "tools": {
                "microsoft.botsay": {
                  // some comment
                  "version": "1.0.0",
                  "commands": [
                    "botsay"
                  ]
                },
                "dotnetsay": {
                  "version": "2.1.3",
                  "commands": [
                    "dotnetsay"
                  ]
                }
              }
            }
            """,
            // property path
            new[]
            {
                "tools",
                "Microsoft.BotSay",
                "version"
            },
            // new value
            "1.1.0",
            // expected json
            """
            {
              "version": 1,
              "isRoot": true,
              "tools": {
                "microsoft.botsay": {
                  // some comment
                  "version": "1.1.0",
                  "commands": [
                    "botsay"
                  ]
                },
                "dotnetsay": {
                  "version": "2.1.3",
                  "commands": [
                    "dotnetsay"
                  ]
                }
              }
            }
            """
        ];

        // shallow property path
        yield return
        [
            // original json
            """
            {
              "path1": {
                "subpath1": "value1",
                "subpath2": "value2"
              },
              "path2": "old-value"
            }
            """,
            // property path
            new[]
            {
                "path2"
            },
            // new value
            "new-value",
            // expected json
            """
            {
              "path1": {
                "subpath1": "value1",
                "subpath2": "value2"
              },
              "path2": "new-value"
            }
            """
        ];

        // line comment after comma
        yield return
        [
            // original json
            """
            {
              "property1": "value1",
              // some comment
              "property2": "value2"
            }
            """,
            // property path
            new[] { "property2" },
            // new value
            "updated-value",
            // expected json
            """
            {
              "property1": "value1",
              // some comment
              "property2": "updated-value"
            }
            """
        ];
    }
}
