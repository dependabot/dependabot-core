# cargo.nix: Rust/Cargo ecosystem image — core + Rust toolchain.
# Mirrors cargo/Dockerfile.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

let
  rustInstall = pkgs.runCommand "rust-install" { } ''
    mkdir -p $out/opt/rust/bin
    ln -s ${pkgs.rustc}/bin/rustc $out/opt/rust/bin/rustc
    ln -s ${pkgs.cargo}/bin/cargo $out/opt/rust/bin/cargo
    ln -s ${pkgs.rustfmt}/bin/rustfmt $out/opt/rust/bin/rustfmt 2>/dev/null || true

    # Cargo config for git CLI (so git-shim works)
    mkdir -p $out/opt/rust
    cat > $out/opt/rust/config.toml <<EOF
    [net]
    git-fetch-with-cli = true
    EOF
  '';

in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "cargo";
  tag = "cargo";
  toolchainPackages = [
    pkgs.rustc
    pkgs.cargo
  ];
  extraCopyToRoot = [ rustInstall ];
  envVars = [
    "RUSTUP_HOME=/opt/rust"
    "CARGO_HOME=/opt/rust"
    "CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse"
    "PATH=/opt/rust/bin:/home/dependabot/bin:$PATH"
  ];
}
