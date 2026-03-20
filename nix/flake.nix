{
  description = "Dependabot Core container images built with Nix + nix2container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix2container,
    }:
    let
      # Systems we build images for
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Helper to generate per-system outputs
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Import shared helpers
      mkUser = import ./lib/mkUser.nix;
      mkEcosystemImage = import ./lib/mkEcosystemImage.nix;
      mkDevImage = import ./lib/mkDevImage.nix;

      # Ecosystem-to-tag mapping (mirrors script/_common set_tag)
      ecosystemTag = {
        docker_compose = "docker-compose";
        dotnet_sdk = "dotnet-sdk";
        go_modules = "gomod";
        hex = "mix";
        npm_and_yarn = "npm";
        pre_commit = "pre-commit";
        python = "pip";
        git_submodules = "gitsubmodule";
        github_actions = "github-actions";
        rust_toolchain = "rust-toolchain";
      };

      tagFor = name: ecosystemTag.${name} or name;

    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          n2c = nix2container.packages.${system}.nix2container;
          fetchGitShim = import ./packages/git-shim.nix { inherit pkgs system; };
          coreResult = import ./core.nix {
            inherit
              pkgs
              n2c
              mkUser
              fetchGitShim
              ;
            src = ./..;
          };
          coreImage = coreResult.image;
          coreEnvVars = coreResult.envVars;
        in
        {
          core = coreImage;

          # Ecosystem images
          ecosystems =
            let
              callEcosystem =
                file:
                import file {
                  inherit pkgs n2c mkEcosystemImage;
                  coreImage = coreImage;
                  src = ./..;
                };
              callEcosystemWithSystem =
                file:
                import file {
                  inherit
                    pkgs
                    n2c
                    mkEcosystemImage
                    system
                    ;
                  coreImage = coreImage;
                  src = ./..;
                };
            in
            {
              # Pilot ecosystems
              silent = callEcosystem ./ecosystems/silent.nix;
              docker = callEcosystem ./ecosystems/docker.nix;
              bundler = callEcosystem ./ecosystems/bundler.nix;
              go_modules = callEcosystem ./ecosystems/go_modules.nix;
              npm_and_yarn = callEcosystem ./ecosystems/npm_and_yarn.nix;

              # Complex ecosystems
              python = callEcosystem ./ecosystems/python.nix;
              cargo = callEcosystem ./ecosystems/cargo.nix;
              hex = callEcosystem ./ecosystems/hex.nix;
              maven = callEcosystem ./ecosystems/maven.nix;
              swift = callEcosystemWithSystem ./ecosystems/swift.nix;
              composer = callEcosystem ./ecosystems/composer.nix;
              pub = callEcosystem ./ecosystems/pub.nix;
              terraform = callEcosystem ./ecosystems/terraform.nix;
              opentofu = callEcosystem ./ecosystems/opentofu.nix;
              gradle = callEcosystem ./ecosystems/gradle.nix;
              nuget = callEcosystem ./ecosystems/nuget.nix;

              # Remaining ecosystems
              bazel = callEcosystem ./ecosystems/bazel.nix;
              bun = callEcosystem ./ecosystems/bun.nix;
              conda = callEcosystem ./ecosystems/conda.nix;
              devcontainers = callEcosystem ./ecosystems/devcontainers.nix;
              docker_compose = callEcosystem ./ecosystems/docker_compose.nix;
              dotnet_sdk = callEcosystem ./ecosystems/dotnet_sdk.nix;
              elm = callEcosystem ./ecosystems/elm.nix;
              git_submodules = callEcosystem ./ecosystems/git_submodules.nix;
              github_actions = callEcosystem ./ecosystems/github_actions.nix;
              helm = callEcosystem ./ecosystems/helm.nix;
              julia = callEcosystem ./ecosystems/julia.nix;
              pre_commit = callEcosystem ./ecosystems/pre_commit.nix;
              rust_toolchain = callEcosystem ./ecosystems/rust_toolchain.nix;
              uv = callEcosystem ./ecosystems/uv.nix;
              vcpkg = callEcosystem ./ecosystems/vcpkg.nix;
            };

          # Development images — one per ecosystem, overlays dev tools
          dev =
            let
              ecosystems' = self.packages.${system}.ecosystems;
              mkDev = name: tag: ecosystemImage: mkDevImage {
                inherit pkgs n2c ecosystemImage name tag coreEnvVars;
              };
            in
            builtins.mapAttrs (name: ecosystemImage:
              mkDev name (tagFor name) ecosystemImage
            ) ecosystems';
        }
      );
    };
}
