# typed: false
# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/bundler/file_updater/lockfile_updater"

RSpec.describe Dependabot::Bundler::FileUpdater::LockfileUpdater do
  include_context "when stubbing rubygems compact index"

  describe "#post_process_lockfile" do
    subject(:post_processed_lockfile) { updater.send(:post_process_lockfile, generated_lockfile) }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "business",
        version: "1.5.0",
        previous_version: "1.4.0",
        requirements: [],
        previous_requirements: [],
        package_manager: "bundler"
      )
    end
    let(:files) { [gemfile, lockfile] }
    let(:gemfile) do
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: "source 'https://rubygems.org'\n"
      )
    end
    let(:generated_lockfile) do
      <<~LOCKFILE
        GEM
          specs:
            business (1.5.0)

        CHECKSUMS
          business (1.5.0) sha256=123
          bundler (4.0.11) sha256=abc

        BUNDLED WITH
           4.0.11
      LOCKFILE
    end

    context "when original lockfile uses Bundler 4.0.10" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: <<~LOCKFILE
            GEM
              specs:
                business (1.4.0)

            CHECKSUMS
              business (1.4.0) sha256=456

            BUNDLED WITH
               4.0.10
          LOCKFILE
        )
      end

      it "removes newly added bundler checksums" do
        expect(post_processed_lockfile).not_to include("bundler (4.0.11)")
      end
    end

    context "when original lockfile uses Bundler 4.0.11" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: <<~LOCKFILE
            GEM
              specs:
                business (1.4.0)

            CHECKSUMS
              business (1.4.0) sha256=456

            BUNDLED WITH
               4.0.11
          LOCKFILE
        )
      end

      it "keeps bundler checksums" do
        expect(post_processed_lockfile).to include("bundler (4.0.11)")
      end
    end
  end

  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      dependency_files: files,
      options: {},
      credentials: []
    )
  end

  let(:updated_lockfile_content) { updater.updated_lockfile_content }

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
