# dotnet_sdk.nix: .NET SDK ecosystem image.
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
  name = "dotnet_sdk";
  tag = "dotnet-sdk";
  toolchainPackages = [ pkgs.dotnetCorePackages.sdk_9_0 ];
}
