using System.Text.Json;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run;

using Xunit;

namespace NuGetUpdater.Core.Test
{
    public abstract class TestBase
    {
        protected TestBase()
        {
            MSBuildHelper.RegisterMSBuild(Environment.CurrentDirectory, Environment.CurrentDirectory);
        }

        protected static void ValidateError(JobErrorBase expected, JobErrorBase? actual)
        {
            var expectedErrorString = JsonSerializer.Serialize(expected, RunWorker.SerializerOptions);
            var actualErrorString = actual is null
                ? null
                : JsonSerializer.Serialize(actual, RunWorker.SerializerOptions);
            Assert.Equal(expectedErrorString, actualErrorString);
        }

        protected static void ValidateErrorRegex(string expectedErrorRegex, JobErrorBase? actual)
        {
            var actualErrorString = actual is null
                ? null
                : JsonSerializer.Serialize(actual, RunWorker.SerializerOptions);
            Assert.Matches(expectedErrorRegex, actualErrorString);
        }
    }
}
