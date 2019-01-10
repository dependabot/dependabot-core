# frozen_string_literal: true

require "fileutils"
require "English"
require "net/http"
require "uri"
require "json"
require "shellwords"
require "rubygems/package"
require "./lib/dependabot/version"

GEMSPECS = %w(
  dependabot-core.gemspec
  terraform/dependabot-terraform.gemspec
  elm/dependabot-elm.gemspec
  docker/dependabot-docker.gemspec
  git_submodules/dependabot-git_submodules.gemspec
  python/dependabot-python.gemspec
  nuget/dependabot-nuget.gemspec
  gradle/dependabot-gradle.gemspec
  maven/dependabot-maven.gemspec
  hex/dependabot-hex.gemspec
  cargo/dependabot-cargo.gemspec
  go_modules/dependabot-go_modules.gemspec
  composer/dependabot-composer.gemspec
  omnibus/dependabot-omnibus.gemspec
).freeze

namespace :ci do
  task :rubocop do
    packages = changed_packages
    puts "Running rubocop on: #{packages.join(', ')}"
    packages.each do |package|
      puts "> cd #{package} && bundle exec rubocop"
      system("cd #{package} && bundle exec rubocop")
    end
  end

  task :rspec do
    packages = changed_packages
    puts "Running rspec on: #{packages.join(', ')}"
    packages.each do |package|
      puts "> cd #{package} && bundle exec rspec spec"
      system("cd #{package} && bundle exec rspec spec")
    end
  end
end

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
      if rubygems_release_exists?(gem_name, Dependabot::VERSION)
        puts "- Skipping #{gem_path} as it already exists on rubygems"
      else
        puts "> Releasing #{gem_path}"
        sh "gem push #{gem_path}"
      end
    end
  end

  task :clean do
    FileUtils.rm(Dir["pkg/*.gem"])
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

def changed_packages
  all_packages = GEMSPECS.
                 select { |gs| gs.include?("/") }.
                 map { |gs| "./" + gs.split("/").first }
  return all_packages if ENV["CIRCLE_COMPARE_URL"].nil?

  range = ENV["CIRCLE_COMPARE_URL"].split("/").last
  core_paths = %w(Dockerfile Dockerfile.ci Gemfile dependabot-core.gemspec
                  config helpers lib spec)
  core_changed = commit_range_changes_paths?(range, core_paths)

  packages = all_packages.select do |package|
    next true if core_changed

    commit_range_changes_paths?(range, [package])
  end

  packages.insert(0, "./") if core_changed
  packages
end

def commit_range_changes_paths?(range, paths)
  cmd = %w(git diff --quiet) + [range, "--"] + paths
  !system(Shellwords.join(cmd))
end
