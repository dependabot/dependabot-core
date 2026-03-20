# mkDevImage: Overlays development/debugging tools onto any ecosystem image.
#
# Usage:
#   mkDevImage {
#     inherit pkgs n2c;
#     ecosystemImage = <ecosystem image>;
#     name = "go_modules";
#     tag = "gomod";
#     coreEnvVars = [ "DEPENDABOT=true" ... ];
#   }
#
# Returns a nix2container image with the ecosystem image as base
# plus vim, strace, ltrace, gdb, shellcheck, libgit2, cmake, pkg-config,
# a custom PS1 prompt, and .vimrc.
{
  pkgs,
  n2c,
  ecosystemImage,
  name,
  tag ? name,
  coreEnvVars ? [],
}:

let
  devToolsPackages = with pkgs; [
    vim
    strace
    ltrace
    gdb
    shellcheck
    libgit2
    cmake
    pkg-config
    openssh
    rubyPackages_4_0.rspec-core
  ];

  # Create .vimrc and .bashrc customizations
  devConfig = pkgs.runCommand "dev-config-${name}" { } ''
    mkdir -p $out/home/dependabot

    # Minimal .vimrc (can't curl in sandbox)
    cat > $out/home/dependabot/.vimrc <<'VIMRC'
    set nocompatible
    syntax on
    set number
    set ruler
    set hlsearch
    set incsearch
    VIMRC

    # .bashrc PS1 prompt
    cat > $out/home/dependabot/.bashrc <<'BASHRC'
    export PS1="[dependabot-core-dev] \w \[$(tput setaf 4)\]$ \[$(tput sgr 0)\]"
    BASHRC
  '';

  devToolsLayer = n2c.buildLayer {
    deps = devToolsPackages;
  };

  # Augment PATH from coreEnvVars with dev tool bin paths
  devToolPaths = builtins.concatStringsSep ":" (map (p: "${p}/bin") devToolsPackages);
  devEnvVars = map (v:
    if pkgs.lib.hasPrefix "PATH=" v
    then "${v}:${devToolPaths}"
    else v
  ) coreEnvVars;

in
n2c.buildImage {
  name = "ghcr.io/dependabot/dependabot-dev-${tag}";
  fromImage = ecosystemImage;

  layers = [ devToolsLayer ];
  copyToRoot = [ devConfig ];

  config = {
    Env = devEnvVars;
    User = "dependabot";
    WorkingDir = "/home/dependabot";
    Cmd = [ "${pkgs.bashInteractive}/bin/bash" ];
  };

  perms = [
    {
      path = devConfig;
      regex = "/home/dependabot";
      mode = "0777";
      uid = 1000;
      gid = 1000;
      uname = "dependabot";
      gname = "dependabot";
    }
  ];
}
