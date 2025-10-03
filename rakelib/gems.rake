# frozen_string_literal: true

require_relative "support/helpers"

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
# rubocop:enable Metrics/BlockLength
