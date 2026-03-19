# nuget.nix: NuGet/.NET ecosystem image.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "nuget";
  tag = "nuget";
  toolchainPackages = [ pkgs.dotnetCorePackages.sdk_9_0 ];
}
