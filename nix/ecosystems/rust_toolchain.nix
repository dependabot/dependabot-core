# rust_toolchain.nix: Rust toolchain ecosystem image.
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
  name = "rust_toolchain";
  tag = "rust-toolchain";
  toolchainPackages = [
    pkgs.rustc
    pkgs.cargo
  ];
}
