# git_submodules.nix: Git Submodules ecosystem image.
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
  name = "git_submodules";
  tag = "gitsubmodule";
}
