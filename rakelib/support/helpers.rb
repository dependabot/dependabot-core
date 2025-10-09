# typed: strict
# frozen_string_literal: true

require "fileutils"
require "English"
require "net/http"
require "uri"
require "json"
require "rubygems/package"
require "bundler"
require "sorbet-runtime"
require "./common/lib/dependabot"
require "yaml"

# Rake helper methods with strict typing
class RakeHelpers
  extend T::Sig

  # ./dependabot-core.gemspec is purposefully excluded from this list
  # because it's an empty gem as a placeholder to prevent namesquatting.
  GEMSPECS = T.let(
    %w(
      common/dependabot-common.gemspec
      bazel/dependabot-bazel.gemspec
      bun/dependabot-bun.gemspec
      bundler/dependabot-bundler.gemspec
      cargo/dependabot-cargo.gemspec
      composer/dependabot-composer.gemspec
      conda/dependabot-conda.gemspec
      devcontainers/dependabot-devcontainers.gemspec
      docker_compose/dependabot-docker_compose.gemspec
      docker/dependabot-docker.gemspec
      dotnet_sdk/dependabot-dotnet_sdk.gemspec
      elm/dependabot-elm.gemspec
      git_submodules/dependabot-git_submodules.gemspec
      github_actions/dependabot-github_actions.gemspec
      go_modules/dependabot-go_modules.gemspec
      gradle/dependabot-gradle.gemspec
      helm/dependabot-helm.gemspec
      hex/dependabot-hex.gemspec
      maven/dependabot-maven.gemspec
      npm_and_yarn/dependabot-npm_and_yarn.gemspec
      nuget/dependabot-nuget.gemspec
      omnibus/dependabot-omnibus.gemspec
      pub/dependabot-pub.gemspec
      python/dependabot-python.gemspec
      rust_toolchain/dependabot-rust_toolchain.gemspec
      silent/dependabot-silent.gemspec
      swift/dependabot-swift.gemspec
      terraform/dependabot-terraform.gemspec
      uv/dependabot-uv.gemspec
      vcpkg/dependabot-vcpkg.gemspec
    ).freeze,
    T::Array[String]
  )

  sig { params(command: String).void }
  def self.run_command(command)
    puts "> #{command}"
    exit 1 unless system(command)
  end

  sig { void }
  def self.guard_tag_match
    tag = "v#{Dependabot::VERSION}"
    tag_commit = `git rev-list -n 1 #{tag} 2> /dev/null`.strip
    abort_msg = "Can't release - tag #{tag} does not exist. " \
                "This may be due to a bug in the Actions runner resulting in a stale copy of the git repo. " \
                "Please delete the failing git tag and then recreate the GitHub release for this version. " \
                "This will retrigger the gems-release-to-rubygems.yml workflow."
    abort abort_msg unless $CHILD_STATUS == 0

    head_commit = `git rev-parse HEAD`.strip
    return if tag_commit == head_commit

    abort "Can't release - HEAD (#{head_commit[0..9]}) does not match " \
          "tag #{tag} (#{tag_commit[0..9]})"
  end

  sig { params(name: String, version: String).returns(T::Boolean) }
  def self.rubygems_release_exists?(name, version)
    uri = URI.parse("https://rubygems.org/api/v2/rubygems/#{name}/versions/#{version}.json")
    response = Net::HTTP.get_response(uri)
    response.code == "200"
  end

  sig do
    params(
      hash: T::Hash[T.untyped, T.untyped],
      recursive: T::Boolean,
      block: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(Integer))
    ).returns(T::Hash[T.untyped, T.untyped])
  end
  def self.sort_hash_by_key(hash, recursive = false, &block)
    sorted_keys = if block
                    hash.keys.sort(&block)
                  else
                    hash.keys.sort
                  end

    sorted_keys.each_with_object({}) do |key, seed|
      seed[key] = hash[key]
      if recursive && seed[key].is_a?(Hash)
        seed[key] =
          sort_hash_by_key(
            T.cast(seed[key], T::Hash[T.untyped, T.untyped]),
            true,
            &block
          )
      end
      seed
    end
  end
end

# Backward compatibility: keep GEMSPECS constant at module level
GEMSPECS = RakeHelpers::GEMSPECS

# Extension to Hash class for backward compatibility
class Hash
  extend T::Sig

  sig do
    params(
      recursive: T::Boolean,
      block: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(Integer))
    ).returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_by_key(recursive = false, &block)
    RakeHelpers.sort_hash_by_key(T.cast(self, T::Hash[T.untyped, T.untyped]), recursive, &block)
  end
end
