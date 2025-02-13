namespace NuGetUpdater.Core.Files
{
    internal class BasicBuildFile : BuildFile<string>
    {
        private BasicBuildFile(string repoRootPath, string path, string contents) : base(repoRootPath, path, contents)
        {
        }

        public static BasicBuildFile Open(string repoRootPath, string path)
            => new(repoRootPath, path, File.ReadAllText(path));

        protected override string GetContentsString(string contents) => Contents;
    }
}
