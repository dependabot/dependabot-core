namespace NuGetUpdater.Core.Discover;

public enum PackageManagementKind
{
    /// <summary>
    /// The default for SDK-style projects, e.g., <code>&lt;PackageReference Include="Some.Package" Version="1.0.0" /&gt;</code>
    /// </summary>
    Default,

    /// <summary>
    /// Separate <code>&lt;PackageReference&gt;</code> and <code>&lt;PackageVersion&gt;</code> elements.  Set by the
    /// user by adding the property <code>&lt;ManagePackageVersionsCentrally&gt;true&lt;/ManagePackageVersionsCentrally&gt;</code>
    /// and commonly using the file <code>Directory.Packages.props</code>
    /// </summary>
    CentralPackageManagement,

    /// <summary>
    /// Similar to <see cref="CentralPackageManagement"/> but with the additional property
    /// <code>&lt;CentralPackageTransitivePinningEnabled&gt;true&lt;/CentralPackageTransitivePinningEnabled&gt;</code> which applies
    /// <code>&lt;PackageVersion&gt;</code> elements for all transitive dependencies as well.
    /// </summary>
    CentralPackageManagementWithTransitivePinning,
}
