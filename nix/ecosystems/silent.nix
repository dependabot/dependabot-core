# silent.nix: Minimal ecosystem image — core + gem source copy only.
# Mirrors silent/Dockerfile.
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
  name = "silent";
  tag = "silent";
}
