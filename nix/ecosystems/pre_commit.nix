# pre_commit.nix: Pre-commit ecosystem image.
# Note: pre_commit depends on go_modules and bundler tooling.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

let
  go = pkgs.go_1_26;
  ruby = pkgs.ruby;
in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "pre_commit";
  tag = "pre-commit";
  toolchainPackages = [
    go
    ruby
    pkgs.python313
  ];
  envVars = [
    "PATH=/opt/go/bin:/home/dependabot/bin:$PATH"
  ];
}
