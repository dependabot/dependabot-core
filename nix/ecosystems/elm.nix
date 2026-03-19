# elm.nix: Elm ecosystem image.
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
  name = "elm";
  tag = "elm";
  toolchainPackages = [ pkgs.elmPackages.elm ];
}
