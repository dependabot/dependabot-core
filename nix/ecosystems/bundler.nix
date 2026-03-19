# bundler.nix: Bundler ecosystem image — core + bundler native helpers.
# Mirrors bundler/Dockerfile.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

let
  ruby = pkgs.ruby;

  # Build bundler helpers as a Nix derivation (mirrors: RUN bash /opt/bundler/helpers/v2/build)
  bundlerHelpers =
    pkgs.runCommand "bundler-helpers"
      {
        nativeBuildInputs = [
          ruby
          pkgs.git
          pkgs.gcc
          pkgs.gnumake
          pkgs.pkg-config
          pkgs.zlib
          pkgs.zlib.dev
          pkgs.libyaml
          pkgs.libyaml.dev
        ];
      }
      ''
        mkdir -p $out/opt/bundler/helpers

        # Copy helper source to writable location
        cp -rL ${src}/bundler/helpers/. $TMPDIR/helpers/
        chmod -R u+w $TMPDIR/helpers

        # Build v2 helpers
        export HOME=$TMPDIR
        export GEM_HOME=$out/opt/bundler/helpers/v2
        mkdir -p $GEM_HOME

        cd $TMPDIR/helpers/v2
        if [ -f build ]; then
          bash build || true
        fi

        # Copy built helpers to output
        cp -rL $TMPDIR/helpers/. $out/opt/bundler/helpers/
        chmod -R u+w $out/opt/bundler/helpers
      '';

in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "bundler";
  tag = "bundler";
  helperDerivation = bundlerHelpers;
}
