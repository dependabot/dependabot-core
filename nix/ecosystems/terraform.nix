# terraform.nix: Terraform ecosystem image.
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
  name = "terraform";
  tag = "terraform";
  toolchainPackages = [ pkgs.terraform ];
}
