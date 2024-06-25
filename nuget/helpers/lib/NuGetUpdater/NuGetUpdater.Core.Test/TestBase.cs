namespace NuGetUpdater.Core.Test
{
    public abstract class TestBase
    {
        protected TestBase()
        {
            MSBuildHelper.RegisterMSBuild(Environment.CurrentDirectory, Environment.CurrentDirectory);
        }
    }
}
