# swift.nix: Swift ecosystem image — core + Swift via fixed-output derivation.
# Mirrors swift/Dockerfile — downloads official Swift tarball.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
  system ? "x86_64-linux",
}:

let
  swiftVersion = "6.2.3";

  archMap = {
    "x86_64-linux" = {
      ubuntuArch = "ubuntu24.04";
    };
    "aarch64-linux" = {
      ubuntuArch = "ubuntu24.04-aarch64";
    };
  };

  archInfo = archMap.${system};

  # Download and extract Swift tarball (mirrors the Dockerfile approach)
  swiftInstall = pkgs.stdenv.mkDerivation {
    pname = "swift";
    version = swiftVersion;

    src = pkgs.fetchurl {
      url = "https://download.swift.org/swift-${swiftVersion}-release/${
        builtins.replaceStrings [ "." ] [ "" ] archInfo.ubuntuArch
      }/swift-${swiftVersion}-RELEASE/swift-${swiftVersion}-RELEASE-${archInfo.ubuntuArch}.tar.gz";
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # TODO: prefetch
    };

    nativeBuildInputs = [
      pkgs.gnutar
      pkgs.gzip
    ];

    installPhase = ''
      mkdir -p $out/opt/swift
      tar -C $out/opt/swift -xzf $src --strip-components 1
    '';
  };

  # Swift runtime dependencies (from swift/Dockerfile)
  swiftDeps = with pkgs; [
    binutils
    glibc.dev
    curl.dev
    libedit
    libxml2
    ncurses.dev
    sqlite
    pkg-config
    tzdata
    libuuid.dev
  ];

in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "swift";
  tag = "swift";
  toolchainPackages = swiftDeps;
  extraCopyToRoot = [ swiftInstall ];
  envVars = [
    "PATH=/opt/swift/usr/bin:/home/dependabot/bin:$PATH"
  ];
}
