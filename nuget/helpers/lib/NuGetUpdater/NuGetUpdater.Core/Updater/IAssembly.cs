namespace NuGetUpdater.Core.Updater;

internal interface IAssembly
{
    string Name { get; }
    Version Version { get; }
    string PublicKeyToken { get; }
    string Culture { get; }
    IEnumerable<IAssembly> ReferencedAssemblies { get; }
}
