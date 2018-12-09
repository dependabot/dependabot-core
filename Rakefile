# frozen_string_literal: true

require "fileutils"
require "English"
require "net/http"
require "uri"
require "json"
require "rubygems/package"
require "./lib/dependabot/version"

gemspecs = %w(
  dependabot-core.gemspec
  terraform/dependabot-terraform.gemspec
  docker/dependabot-docker.gemspec
  git_submodules/dependabot-git-submodules.gemspec
  python/dependabot-python.gemspec
  omnibus/dependabot-omnibus.gemspec
)

namespace :gems do
  task build: :clean do
    root_path = Dir.getwd
    pkg_path = File.join(root_path, "pkg")
    Dir.mkdir(pkg_path) unless File.directory?(pkg_path)

    gemspecs.each do |gemspec_path|
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

    gemspecs.each do |gemspec_path|
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
