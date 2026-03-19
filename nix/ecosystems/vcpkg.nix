# vcpkg.nix: vcpkg ecosystem image.
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
  name = "vcpkg";
  tag = "vcpkg";
}
