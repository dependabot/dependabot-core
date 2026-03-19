# fetchGitShim: Downloads the git-shim binary for the target architecture.
#
# Usage:
#   fetchGitShim { inherit pkgs system; }
#
# Returns a derivation with the extracted git-shim binary.
{ pkgs, system }:

let
  version = "1.4.0";

  archMap = {
    "x86_64-linux" = "amd64";
    "aarch64-linux" = "arm64";
  };

  arch = archMap.${system} or (throw "Unsupported system: ${system}");

  # SHA256 hashes for each architecture
  hashMap = {
    "amd64" = "0r8jxaw7b0c935pqx79f486j1xp8z6y410qamidphrq7nypwkk1k";
    "arm64" = "0wb20zkkpjf3147fjpys71k52i4bycpsk720rdyb1d0q72lffbwh";
  };

in
pkgs.stdenv.mkDerivation {
  pname = "git-shim";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/dependabot/git-shim/releases/download/v${version}/git-v${version}-linux-${arch}.tar.gz";
    sha256 = hashMap.${arch};
  };

  sourceRoot = ".";

  nativeBuildInputs = [ pkgs.gnutar ];

  installPhase = ''
    mkdir -p $out/bin
    cp git $out/bin/git
    chmod +x $out/bin/git
  '';
}
