# core.nix: Core image definition for Dependabot.
#
# Replaces Dockerfile.updater-core. Produces the base OCI image containing:
# - System tools (git, git-lfs, bzr, hg, gnupg2, openssh, etc.)
# - Ruby 3.4.x with RubyGems and Bundler
# - The git-shim binary
# - The dependabot user (UID 1000, GID 1000)
# - Updater gem bundle
# - Common + omnibus + updater source code
#
# All ecosystem images use this as their fromImage.
{
  pkgs,
  n2c,
  mkUser,
  fetchGitShim,
  src,
}:

let
  # --- User setup (T011) ---
  userSetup = mkUser {
    inherit pkgs;
    name = "dependabot";
    uid = 1000;
    gid = 1000;
    home = "/home/dependabot";
  };

  # --- System packages (T008) ---
  systemPackages = with pkgs; [
    # VCS
    git
    git-lfs
    breezy # bzr
    mercurial # hg

    # Security / signing
    gnupg
    openssh
    cacert

    # Build tools
    gcc
    gnumake
    gmp
    gmp.dev
    zlib
    zlib.dev

    # Compression
    bzip2
    unzip
    zstd

    # Utilities
    file
    libyaml
    libyaml.dev

    # Native gem build dependencies
    gpgme
    gpgme.dev
    libgpg-error
    libgpg-error.dev
    libassuan
    libassuan.dev
    pkg-config

    # Locale
    glibcLocales

    # Shell
    bashInteractive
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    gnutar
    gzip
    which
    curl
    less
    patch
  ];

  # --- Ruby (T009) ---
  ruby = pkgs.ruby;

  # --- System layer (T008) ---
  systemLayer = n2c.buildLayer {
    deps = systemPackages;
  };

  # --- Ruby layer (T009) ---
  rubyLayer = n2c.buildLayer {
    deps = [ ruby ];
  };

  # --- Git-shim layer (T010) ---
  gitShimInstall = pkgs.runCommand "git-shim-install" { } ''
    mkdir -p $out/home/dependabot/bin
    cp ${fetchGitShim}/bin/git $out/home/dependabot/bin/git
    chmod +x $out/home/dependabot/bin/git
  '';

  # --- Source layer (T013) ---
  # Copy source code into image paths matching current Dockerfile layout
  sourceInstall = pkgs.runCommand "dependabot-source" { } ''
    mkdir -p $out/home/dependabot/dependabot-updater
    mkdir -p $out/home/dependabot/common
    mkdir -p $out/home/dependabot/omnibus

    # Copy updater
    cp -rL ${src}/updater/. $out/home/dependabot/dependabot-updater/
    chmod -R u+w $out/home/dependabot/dependabot-updater

    # Fix shebangs (e.g. #!/usr/bin/env bash -> /nix/store/.../bin/bash)
    patchShebangs $out/home/dependabot/dependabot-updater/bin

    # Copy common
    cp -rL ${src}/common/. $out/home/dependabot/common/
    chmod -R u+w $out/home/dependabot/common

    # Copy omnibus
    cp -rL ${src}/omnibus/. $out/home/dependabot/omnibus/
    chmod -R u+w $out/home/dependabot/omnibus

    # Copy gemspecs and .bundle configs from all ecosystem directories
    for dir in ${src}/*/; do
      base=$(basename "$dir")
      # Skip non-ecosystem dirs
      case "$base" in
        nix|specs|bin|script|rakelib|sorbet|.github|.devcontainer|.specify) continue ;;
      esac
      if ls "$dir"/*.gemspec 1>/dev/null 2>&1; then
        mkdir -p "$out/home/dependabot/$base"
        cp "$dir"/*.gemspec "$out/home/dependabot/$base/" 2>/dev/null || true
        if [ -d "$dir/.bundle" ]; then
          cp -rL "$dir/.bundle" "$out/home/dependabot/$base/" 2>/dev/null || true
          chmod -R u+w "$out/home/dependabot/$base/.bundle" 2>/dev/null || true
        fi
      fi
    done

    # Copy LICENSE
    cp ${src}/LICENSE $out/home/dependabot/ 2>/dev/null || true

    # Ensure writable
    chmod -R u+w $out/home/dependabot
  '';

  # --- Gem bundle layer (T012) ---
  # Bundle install for the updater Gemfile
  gemBundle =
    pkgs.runCommand "dependabot-gems"
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
          pkgs.gmp
          pkgs.gmp.dev
        ];
      }
      ''
        mkdir -p $out/home/dependabot/dependabot-updater/vendor

        # Copy source to a writable location
        cp -r ${src}/updater/Gemfile $TMPDIR/Gemfile
        cp -r ${src}/updater/Gemfile.lock $TMPDIR/Gemfile.lock

        cd $TMPDIR

        # Configure bundler
        export HOME=$TMPDIR
        export BUNDLE_PATH=$out/home/dependabot/dependabot-updater/vendor
        export BUNDLE_FROZEN=true
        export BUNDLE_WITHOUT=development

        ${ruby}/bin/bundle config set --local path "$BUNDLE_PATH"
        ${ruby}/bin/bundle config set --local frozen true
        ${ruby}/bin/bundle config set --local without development

        # Bundle install
        ${ruby}/bin/bundle install || true
      '';

  # --- /opt directory setup ---
  optDir = pkgs.runCommand "opt-dir" { } ''
    mkdir -p $out/opt
  '';

  # --- SSL certs setup (merged into a single /etc derivation with user) ---
  etcSetup = pkgs.runCommand "etc-setup" { } ''
    # Start from the user setup
    cp -rL ${userSetup}/. $out/
    chmod -R u+w $out

    # Add SSL certs
    mkdir -p $out/etc/ssl/certs
    cp ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/ca-certificates.crt
  '';

  # --- Environment variables (T014) ---
  binPkgs = [
    ruby
    pkgs.git
    pkgs.git-lfs
    pkgs.gnupg
    pkgs.openssh
    pkgs.gcc
    pkgs.gnumake
    pkgs.pkg-config
    pkgs.gpgme.dev
    pkgs.coreutils
    pkgs.bashInteractive
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gnutar
    pkgs.curl
    pkgs.which
    pkgs.file
    pkgs.bzip2
    pkgs.unzip
    pkgs.zstd
    pkgs.gzip
    pkgs.breezy
    pkgs.mercurial
    pkgs.less
    pkgs.patch
  ];
  pathParts = pkgs.lib.makeBinPath binPkgs;

  envVars = [
    "DEPENDABOT=true"
    "DEPENDABOT_HOME=/home/dependabot"
    "DEPENDABOT_NATIVE_HELPERS_PATH=/opt"
    "GIT_LFS_SKIP_SMUDGE=1"
    "LC_ALL=en_US.UTF-8"
    "LANG=en_US.UTF-8"
    "DEBIAN_FRONTEND=noninteractive"
    "PATH=${pathParts}"
    "LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive"
    "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
    "GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt"
  ];

in
# --- Build the core image (T015, T016) ---
# Return both the image and envVars so dev images can inherit them.
{
  image = n2c.buildImage {
    name = "ghcr.io/dependabot/dependabot-updater-core";

  layers = [
    systemLayer
    rubyLayer
  ];

  copyToRoot = [
    etcSetup
    gitShimInstall
    sourceInstall
    optDir
    pkgs.bashInteractive
    pkgs.coreutils
  ];

  config = {
    Env = envVars;
    User = "dependabot";
    WorkingDir = "/home/dependabot/dependabot-updater";
    Cmd = [ "bin/run" ];
  };

  perms = [
    {
      path = etcSetup;
      regex = "/home/dependabot";
      mode = "0755";
      uid = 1000;
      gid = 1000;
      uname = "dependabot";
      gname = "dependabot";
    }
    {
      path = gitShimInstall;
      regex = "/home/dependabot";
      mode = "0755";
      uid = 1000;
      gid = 1000;
      uname = "dependabot";
      gname = "dependabot";
    }
    {
      path = sourceInstall;
      regex = "/home/dependabot";
      mode = "0755";
      uid = 1000;
      gid = 1000;
      uname = "dependabot";
      gname = "dependabot";
    }
    {
      path = optDir;
      regex = "/opt";
      mode = "0755";
      uid = 1000;
      gid = 1000;
      uname = "dependabot";
      gname = "dependabot";
    }
  ];
};

  inherit envVars;
}
