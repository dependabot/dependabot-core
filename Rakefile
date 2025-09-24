# frozen_string_literal: true

require "fileutils"
require "English"
require "net/http"
require "uri"
require "json"
require "rubygems/package"
require "bundler"
require "./common/lib/dependabot"
require "yaml"

# ./dependabot-core.gemspec is purposefully excluded from this list
# because it's an empty gem as a placeholder to prevent namesquatting.
GEMSPECS = %w(
  common/dependabot-common.gemspec
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
).freeze

def run_command(command)
  puts "> #{command}"
  exit 1 unless system(command)
end

# rubocop:disable Metrics/BlockLength
namespace :gems do
  task build: :clean do
    root_path = Dir.getwd
    pkg_path = File.join(root_path, "pkg")
    Dir.mkdir(pkg_path) unless File.directory?(pkg_path)

    GEMSPECS.each do |gemspec_path|
      puts "> Building #{gemspec_path}"
      Dir.chdir(File.dirname(gemspec_path)) do
        gemspec = Bundler.load_gemspec_uncached(File.basename(gemspec_path))
        pkg = ::Gem::Package.build(gemspec)
        FileUtils.mv(pkg, File.join(pkg_path, pkg))
      end
    end
  end

  task release: [:build] do
    guard_tag_match

    GEMSPECS.each do |gemspec_path|
      gem_name = File.basename(gemspec_path).sub(/\.gemspec$/, "")
      gem_name_and_version = "#{gem_name}-#{Dependabot::VERSION}"
      gem_path = "pkg/#{gem_name_and_version}.gem"
      gem_attestation_path = "pkg/#{gem_name_and_version}.sigstore.json"

      attempts = 0
      loop do
        if rubygems_release_exists?(gem_name, Dependabot::VERSION)
          puts "- Skipping #{gem_path} as it already exists on rubygems"
          break
        else
          puts "> Releasing #{gem_path}"
          attempts += 1
          begin
            if ENV["GITHUB_ACTIONS"] == "true"
              sh "gem exec sigstore-cli:0.2.1 sign #{gem_path} --bundle #{gem_attestation_path}"
              sh "gem push #{gem_path} --attestation #{gem_attestation_path}"
            else
              puts "- Skipping sigstore signing (not in GitHub Actions environment, so no OIDC token available)"
              sh "gem push #{gem_path}"
            end
            break
          rescue StandardError => e
            puts "! `gem push` failed with error: #{e}"
            raise if attempts >= 3

            sleep(2)
          end
        end
      end
    end
  end

  task :clean do
    FileUtils.rm(Dir["pkg/*.gem", "pkg/*.sigstore.json"])
  end
end

class Hash
  def sort_by_key(recursive = false, &block)
    keys.sort(&block).each_with_object({}) do |key, seed|
      seed[key] = self[key]
      seed[key] = seed[key].sort_by_key(true, &block) if recursive && seed[key].is_a?(Hash)
      seed
    end
  end
end

namespace :rubocop do
  task :sort do
    File.write(
      "omnibus/.rubocop.yml",
      YAML.load_file("omnibus/.rubocop.yml").sort_by_key(true).to_yaml
    )
  end
end

def guard_tag_match
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

def rubygems_release_exists?(name, version)
  uri = URI.parse("https://rubygems.org/api/v2/rubygems/#{name}/versions/#{version}.json")
  response = Net::HTTP.get_response(uri)
  response.code == "200"
end
# rubocop:enable Metrics/BlockLength
