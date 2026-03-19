# opentofu.nix: OpenTofu ecosystem image.
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
  name = "opentofu";
  tag = "opentofu";
  toolchainPackages = [ pkgs.opentofu ];
}
