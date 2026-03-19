# composer.nix: PHP/Composer ecosystem image.
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
  name = "composer";
  tag = "composer";
  toolchainPackages = [
    pkgs.php
    pkgs.phpPackages.composer
  ];
}
