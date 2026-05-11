# typed: false
# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/bundler/file_updater/lockfile_updater"

RSpec.describe Dependabot::Bundler::FileUpdater::LockfileUpdater do
  include_context "when stubbing rubygems compact index"

  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      dependency_files: files,
      options: {},
      credentials: []
    )
  end

  let(:updated_lockfile_content) { updater.updated_lockfile_content }

  describe "lockfile ending handling" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "byebug",
        version: "13.0.0",
        previous_version: "11.1.3",
        requirements: [],
        previous_requirements: [],
        package_manager: "bundler"
      )
    end

    let(:files) { [gemfile, lockfile] }
    let(:gemfile) do
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: "source \"https://rubygems.org\"\n\ngem \"byebug\"\n"
      )
    end
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              byebug (11.1.3)

          PLATFORMS
            ruby

          DEPENDENCIES
            byebug (= 11.1.3)

          CHECKSUMS
            bundler (4.0.11) sha256=5bcec0fb78302e48d02ee46f10ee6e6942be647ba5b44a6d1ddfda9a240ce785
            byebug (11.1.3) sha256=abc

          BUNDLED WITH
            4.0.11
        LOCKFILE
      )
    end

    it "keeps checksum entries when removing RUBY VERSION" do
      new_lockfile_content = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            byebug (13.0.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          byebug (= 13.0.0)

        RUBY VERSION
          ruby 3.4.2p0

        CHECKSUMS
          bundler (4.0.11) sha256=5bcec0fb78302e48d02ee46f10ee6e6942be647ba5b44a6d1ddfda9a240ce785
          byebug (13.0.0) sha256=d2263efe751941ca520fa29744b71972d39cbc41839496706f5d9b22e92ae05d

        BUNDLED WITH
          4.0.12
      LOCKFILE

      updated_content = updater.send(:replace_lockfile_ending, new_lockfile_content)

      expect(updated_content).not_to include("RUBY VERSION")
      expect(updated_content).to include(
        "bundler (4.0.11) sha256=5bcec0fb78302e48d02ee46f10ee6e6942be647ba5b44a6d1ddfda9a240ce785"
      )
      expect(updated_content).to include("BUNDLED WITH\n  4.0.11")
      expect(updated_content).not_to include("BUNDLED WITH\n  4.0.12")
    end

    it "preserves checksums while sanitizing lockfiles" do
      sanitized_content = updater.send(:sanitized_lockfile_body)

      expect(sanitized_content).to include("CHECKSUMS")
      expect(sanitized_content).to include(
        "bundler (4.0.11) sha256=5bcec0fb78302e48d02ee46f10ee6e6942be647ba5b44a6d1ddfda9a240ce785"
      )
      expect(sanitized_content).not_to include("BUNDLED WITH")
    end

    context "when previous lockfile has RUBY VERSION" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: <<~LOCKFILE
            GEM
              remote: https://rubygems.org/
              specs:
                byebug (11.1.3)

            PLATFORMS
              ruby

            DEPENDENCIES
              byebug (= 11.1.3)

            RUBY VERSION
              ruby 3.4.2p0

            CHECKSUMS
              bundler (4.0.11) sha256=5bcec0fb78302e48d02ee46f10ee6e6942be647ba5b44a6d1ddfda9a240ce785
              byebug (11.1.3) sha256=abc

            BUNDLED WITH
              4.0.11
          LOCKFILE
        )
      end

      it "re-inserts RUBY VERSION before BUNDLED WITH when missing" do
        new_lockfile_content = <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              byebug (13.0.0)

          PLATFORMS
            ruby

          DEPENDENCIES
            byebug (= 13.0.0)

          CHECKSUMS
            bundler (4.0.11) sha256=5bcec0fb78302e48d02ee46f10ee6e6942be647ba5b44a6d1ddfda9a240ce785
            byebug (13.0.0) sha256=d2263efe751941ca520fa29744b71972d39cbc41839496706f5d9b22e92ae05d

          BUNDLED WITH
            4.0.12
        LOCKFILE

        updated_content = updater.send(:replace_lockfile_ending, new_lockfile_content)

        expect(updated_content).to include("RUBY VERSION\n  ruby 3.4.2p0")
        expect(updated_content).to include("RUBY VERSION\n  ruby 3.4.2p0\n\nBUNDLED WITH\n  4.0.11")
      end
    end
  end

  describe "with multiple path gems" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "ice_nine",
        version: "0.11.2",
        previous_version: "0.11.1",
        requirements: [],
        previous_requirements: [],
        package_manager: "bundler"
      )
    end

    let(:files) { [gemspec, other_gemspec, gemfile, lockfile] }
    let(:gemspec) do
      bundler_project_dependency_file("multiple_path_gems", filename: "vendor/net-imap/net-imap.gemspec")
    end
    let(:other_gemspec) do
      bundler_project_dependency_file("multiple_path_gems", filename: "vendor/couchrb/couchrb.gemspec")
    end
    let(:gemfile) do
      bundler_project_dependency_file("multiple_path_gems", filename: "Gemfile")
    end
    let(:lockfile) do
      bundler_project_dependency_file("multiple_path_gems", filename: "Gemfile.lock")
    end

    it "upgrades dependency" do
      expect(updated_lockfile_content).to  include("ice_nine (0.11.2)")
    end

    it "keeps correct versions of path dependencies" do
      expect(updated_lockfile_content).to  include("couchrb (0.9.0)")
      expect(updated_lockfile_content).to  include("net-imap (0.3.3)")
    end
  end

  context "when having vendored gemspecs with ruby version requirements" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "activesupport",
        version: "6.0.3",
        previous_version: "6.0.2",
        requirements: [],
        previous_requirements: [],
        package_manager: "bundler"
      )
    end

    let(:files) { [gemspec, gemfile, lockfile] }
    let(:gemspec) do
      bundler_project_dependency_file("path_gem_with_ruby_requirement", filename: "vendor/couchrb/couchrb.gemspec")
    end
    let(:gemfile) do
      bundler_project_dependency_file("path_gem_with_ruby_requirement", filename: "Gemfile")
    end
    let(:lockfile) do
      bundler_project_dependency_file("path_gem_with_ruby_requirement", filename: "Gemfile.lock")
    end

    it "upgrades dependency" do
      expect(updated_lockfile_content).to include("activesupport (6.0.3)")
    end
  end

  context "with local gemspecs that require updates" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "docker_registry2",
        version: "1.15.0",
        previous_version: "1.14.0",
        requirements: [
          { requirement: "~> 1.15.0", file: "common/dependabot-common.gemspec", groups: [], source: nil }
        ],
        previous_requirements: [
          { requirement: "~> 1.14.0", file: "common/dependabot-common.gemspec", groups: [], source: nil }
        ],
        package_manager: "bundler"
      )
    end

    let(:files) { [gemspec, gemfile, lockfile] }
    let(:gemspec) do
      bundler_project_dependency_file("local_gemspec_needs_updates", filename: "common/dependabot-common.gemspec")
    end
    let(:gemfile) do
      bundler_project_dependency_file("local_gemspec_needs_updates", filename: "Gemfile")
    end
    let(:lockfile) do
      bundler_project_dependency_file("local_gemspec_needs_updates", filename: "Gemfile.lock")
    end

    it "upgrades dependency" do
      expect(updated_lockfile_content).to include("docker_registry2 (1.15.0)")
    end
  end
end
