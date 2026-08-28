variable "DEPENDABOT_UPDATER_VERSION" {
  default = "development"
}

variable "UPDATER_CORE_IMAGE" {
  default = "ghcr.io/dependabot/dependabot-updater-core"
}

variable "UPDATER_CORE_VERSION_TAG" {
  default = ""
}

variable "UPDATER_IMAGE_PREFIX" {
  default = "ghcr.io/dependabot/dependabot-updater-"
}

variable "ECOSYSTEMS" {
  default = [
    { name = "bazel", image = "bazel", dockerfile = "bazel/Dockerfile" },
    { name = "bun", image = "bun", dockerfile = "bun/Dockerfile" },
    { name = "bundler", image = "bundler", dockerfile = "bundler/Dockerfile" },
    { name = "cargo", image = "cargo", dockerfile = "cargo/Dockerfile" },
    { name = "composer", image = "composer", dockerfile = "composer/Dockerfile" },
    { name = "conda", image = "conda", dockerfile = "conda/Dockerfile" },
    { name = "deno", image = "deno", dockerfile = "deno/Dockerfile" },
    { name = "devcontainers", image = "devcontainers", dockerfile = "devcontainers/Dockerfile" },
    { name = "docker_compose", image = "docker-compose", dockerfile = "docker/Dockerfile" },
    { name = "docker", image = "docker", dockerfile = "docker/Dockerfile" },
    { name = "dotnet_sdk", image = "dotnet-sdk", dockerfile = "dotnet_sdk/Dockerfile" },
    { name = "elm", image = "elm", dockerfile = "elm/Dockerfile" },
    { name = "git_submodules", image = "gitsubmodule", dockerfile = "git_submodules/Dockerfile" },
    { name = "github_actions", image = "github-actions", dockerfile = "github_actions/Dockerfile" },
    { name = "go_modules", image = "gomod", dockerfile = "go_modules/Dockerfile" },
    { name = "gradle", image = "gradle", dockerfile = "gradle/Dockerfile" },
    { name = "helm", image = "helm", dockerfile = "helm/Dockerfile" },
    { name = "hex", image = "mix", dockerfile = "hex/Dockerfile" },
    { name = "julia", image = "julia", dockerfile = "julia/Dockerfile" },
    { name = "maven", image = "maven", dockerfile = "maven/Dockerfile" },
    { name = "nix", image = "nix", dockerfile = "nix/Dockerfile" },
    { name = "npm_and_yarn", image = "npm", dockerfile = "npm_and_yarn/Dockerfile" },
    { name = "nub", image = "nub", dockerfile = "nub/Dockerfile" },
    { name = "nuget", image = "nuget", dockerfile = "nuget/Dockerfile" },
    { name = "pre_commit", image = "pre-commit", dockerfile = "pre_commit/Dockerfile" },
    { name = "pub", image = "pub", dockerfile = "pub/Dockerfile" },
    { name = "python", image = "pip", dockerfile = "python/Dockerfile" },
    { name = "rust_toolchain", image = "rust-toolchain", dockerfile = "rust_toolchain/Dockerfile" },
    { name = "sbt", image = "sbt", dockerfile = "sbt/Dockerfile" },
    { name = "swift", image = "swift", dockerfile = "swift/Dockerfile" },
    { name = "terraform", image = "terraform", dockerfile = "terraform/Dockerfile" },
    { name = "opentofu", image = "opentofu", dockerfile = "opentofu/Dockerfile" },
    { name = "uv", image = "uv", dockerfile = "uv/Dockerfile" },
    { name = "vcpkg", image = "vcpkg", dockerfile = "vcpkg/Dockerfile" },
  ]
}

target "_updater-core" {
  context    = "."
  dockerfile = "Dockerfile.updater-core"
  args = {
    USER_UID                    = "1000"
    USER_GID                    = "1000"
    DEPENDABOT_UPDATER_VERSION = DEPENDABOT_UPDATER_VERSION
  }
}

target "updater-core" {
  inherits    = ["_updater-core"]
  description = "Updater-core base for ecosystem images"
  cache-from = [
    { type = "gha", scope = "updater-core" },
    { type = "registry", ref = "${UPDATER_CORE_IMAGE}:latest" },
  ]
  cache-to = [
    { type = "gha", mode = "max", scope = "updater-core" },
  ]
}

target "updater-core-publish" {
  inherits    = ["_updater-core"]
  description = "Published updater-core image"
  args = {
    BUILDKIT_INLINE_CACHE = "1"
  }
  cache-from = [
    { type = "registry", ref = "${UPDATER_CORE_IMAGE}:latest" },
  ]
  cache-to = [
    { type = "inline" },
  ]
  tags = [
    "${UPDATER_CORE_IMAGE}:latest",
    notequal("", UPDATER_CORE_VERSION_TAG) ? "${UPDATER_CORE_IMAGE}:${UPDATER_CORE_VERSION_TAG}" : "",
  ]
  output = [
    { type = "registry" },
  ]
}

target "ecosystem" {
  name = item.image
  matrix = {
    item = ECOSYSTEMS
  }

  description = "Published ${item.name} ecosystem image"
  context     = "."
  dockerfile  = item.dockerfile
  contexts = merge(
    {
      (UPDATER_CORE_IMAGE) = "target:updater-core"
    },
    item.name == "pre_commit" ? {
      "${UPDATER_IMAGE_PREFIX}gomod:latest"   = "target:gomod"
      "${UPDATER_IMAGE_PREFIX}bundler:latest" = "target:bundler"
      "${UPDATER_IMAGE_PREFIX}pub:latest"     = "target:pub"
    } : {}
  )
  cache-from = [
    { type = "gha", scope = item.name },
    { type = "registry", ref = "${UPDATER_IMAGE_PREFIX}${item.image}:latest" },
  ]
  cache-to = [
    { type = "gha", mode = "max", scope = item.name },
  ]
}
