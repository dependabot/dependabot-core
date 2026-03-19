# julia.nix: Julia ecosystem image.
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
  name = "julia";
  tag = "julia";
  toolchainPackages = [ pkgs.julia ];
}
