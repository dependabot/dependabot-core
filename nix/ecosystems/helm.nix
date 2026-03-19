# helm.nix: Helm ecosystem image.
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
  name = "helm";
  tag = "helm";
  toolchainPackages = [ pkgs.kubernetes-helm ];
}
