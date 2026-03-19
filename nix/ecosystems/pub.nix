# pub.nix: Dart/Flutter ecosystem image.
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
  name = "pub";
  tag = "pub";
  toolchainPackages = [
    pkgs.flutter
    pkgs.dart
  ];
}
