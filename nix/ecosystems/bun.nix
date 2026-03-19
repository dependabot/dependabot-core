# bun.nix: Bun ecosystem image.
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
  name = "bun";
  tag = "bun";
  toolchainPackages = [ pkgs.bun ];
}
