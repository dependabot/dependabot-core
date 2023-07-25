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
  go_modules/dependabot-go_modules.gemspec
  terraform/dependabot-terraform.gemspec
  docker/dependabot-docker.gemspec
  git_submodules/dependabot-git_submodules.gemspec
  github_actions/dependabot-github_actions.gemspec
  nuget/dependabot-nuget.gemspec
  gradle/dependabot-gradle.gemspec
  maven/dependabot-maven.gemspec
  bundler/dependabot-bundler.gemspec
  elm/dependabot-elm.gemspec
  cargo/dependabot-cargo.gemspec
  npm_and_yarn/dependabot-npm_and_yarn.gemspec
  composer/dependabot-composer.gemspec
  hex/dependabot-hex.gemspec
  python/dependabot-python.gemspec
  pub/dependabot-pub.gemspec
  omnibus/dependabot-omnibus.gemspec
  swift/dependabot-swift.gemspec
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
      gem_path = "pkg/#{gem_name}-#{Dependabot::VERSION}.gem"

      attempts = 0
      loop do
        if rubygems_release_exists?(gem_name, Dependabot::VERSION)
          puts "- Skipping #{gem_path} as it already exists on rubygems"
          break
        else
          puts "> Releasing #{gem_path}"
          attempts += 1
          sleep(2)
          begin
            sh "gem push #{gem_path}"
            break
          rescue StandardError => e
            puts "! `gem push` failed with error: #{e}"
            raise if attempts >= 3
          end
        end
      end
    end
  end

  task :clean do
    FileUtils.rm(Dir["pkg/*.gem"])
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
  abort "Can't release - tag #{tag} does not exist" unless $CHILD_STATUS == 0

  head_commit = `git rev-parse HEAD`.strip
  return if tag_commit == head_commit

  abort "Can't release - HEAD (#{head_commit[0..9]}) does not match " \
        "tag #{tag} (#{tag_commit[0..9]})"
end

def rubygems_release_exists?(name, version)
  uri = URI.parse("https://rubygems.org/api/v1/versions/#{name}.json")
  response = Net::HTTP.get_response(uri)
  abort "Gem #{name} doesn't exist on rubygems" if response.code != "200"

  body = JSON.parse(response.body)
  existing_versions = body.map { |b| b["number"] }
  existing_versions.include?(version)
end
# rubocop:enable Metrics/BlockLength
