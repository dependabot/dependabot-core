# dotnet_sdk.nix: .NET SDK ecosystem image.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

let
  dotnet = pkgs.dotnetCorePackages.sdk_9_0;
in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "dotnet_sdk";
  tag = "dotnet-sdk";
  toolchainPackages = [ dotnet ];
  envVars = [
    "PATH=${dotnet}/bin:/home/dependabot/bin:$PATH"
    "DOTNET_ROOT=${dotnet}"
    "DOTNET_CLI_TELEMETRY_OPTOUT=1"
  ];
}
