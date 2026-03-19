# mkEcosystemImage: Builds an ecosystem container image layered on the core image.
#
# Usage:
#   mkEcosystemImage {
#     inherit pkgs n2c;
#     name = "go_modules";
#     tag = "gomod";
#     coreImage = <core image>;
#     toolchainPackages = [ pkgs.go_1_26 ];
#     helperDerivation = <helper build derivation>;  # optional
#     envVars = [ "PATH=/opt/go/bin:$PATH" ];        # optional, additive
#     extraCopyToRoot = [ <derivation> ];             # optional
#     src = ./..; # repo root
#   }
#
# Returns a nix2container image with:
#   - Core image as base (fromImage)
#   - Toolchain layer (language runtimes, package managers)
#   - Helper layer (built native helpers, if provided)
#   - Source layer (ecosystem gem + common + updater code)
#   - Environment variables (core + ecosystem-specific)
{
  pkgs,
  n2c,
  name,
  tag ? name,
  coreImage,
  toolchainPackages ? [ ],
  helperDerivation ? null,
  envVars ? [ ],
  extraCopyToRoot ? [ ],
  src,
}:

let
  # Build the ecosystem source layer
  ecosystemSource = pkgs.runCommand "ecosystem-source-${name}" { } ''
    mkdir -p $out/home/dependabot/${name}
    mkdir -p $out/home/dependabot/common
    mkdir -p $out/home/dependabot/dependabot-updater

    # Copy ecosystem gem source
    cp -r ${src}/${name}/. $out/home/dependabot/${name}/

    # Copy common
    cp -r ${src}/common/. $out/home/dependabot/common/

    # Copy updater
    cp -r ${src}/updater/. $out/home/dependabot/dependabot-updater/
  '';

  # Build layers list
  toolchainLayer = n2c.buildLayer {
    deps = toolchainPackages;
  };

  layers = [
    toolchainLayer
  ]
  ++ (
    if helperDerivation != null then
      [
        (n2c.buildLayer { deps = [ helperDerivation ]; })
      ]
    else
      [ ]
  );

in
n2c.buildImage {
  name = "ghcr.io/dependabot/dependabot-updater-${tag}";
  fromImage = coreImage;
  inherit layers;

  copyToRoot = [ ecosystemSource ] ++ extraCopyToRoot;

  config = {
    Env = envVars;
    User = "dependabot";
    WorkingDir = "/home/dependabot/dependabot-updater";
    Cmd = [ "bin/run" ];
  };

  perms = [
    {
      path = ecosystemSource;
      regex = "/home/dependabot";
      mode = "0755";
      uid = 1000;
      gid = 1000;
      uname = "dependabot";
      gname = "dependabot";
    }
  ];
}
