# hex.nix: Elixir/Hex ecosystem image — core + Erlang + Elixir.
# Mirrors hex/Dockerfile.
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
  name = "hex";
  tag = "mix";
  toolchainPackages = [
    pkgs.beam26Packages.erlang
    pkgs.elixir
  ];
}
