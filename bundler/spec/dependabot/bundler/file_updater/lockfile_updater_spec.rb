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

  describe "with lockfiles that include checksums" do
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
    let(:files) { bundler_project_dependency_files(project_name) }
    let(:generated_lockfile) do
      <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            business (1.5.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          business (~> 1.5)

        CHECKSUMS
          business (1.5.0) sha256=123
          bundler (4.0.11) sha256=abc

        BUNDLED WITH
           4.0.11
      LOCKFILE
    end

    before do
      allow(Dependabot::Bundler::NativeHelpers)
        .to receive(:run_bundler_subprocess)
        .and_return(generated_lockfile)
    end

    context "when original lockfile uses Bundler 4.0.10" do
      let(:project_name) { "checksums_bundler_4_0_10" }

      it "removes newly added bundler checksums" do
        expect(updated_lockfile_content).not_to include("bundler (4.0.11)")
      end
    end

    context "when original lockfile uses Bundler 4.0.11" do
      let(:project_name) { "checksums_bundler_4_0_11" }

      it "keeps bundler checksums" do
        expect(updated_lockfile_content).to include("bundler (4.0.11)")
      end
    end

    context "when original lockfile already has a bundler checksum (4.0.12)" do
      let(:project_name) { "checksums_bundler_4_0_12" }
      let(:generated_lockfile) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              business (1.5.0)

          PLATFORMS
            ruby

          DEPENDENCIES
            business (~> 1.5)

          CHECKSUMS
            business (1.5.0) sha256=123
            bundler (4.0.13) sha256=new13

          BUNDLED WITH
             4.0.13
        LOCKFILE
      end

      it "restores the original bundler checksum and drops the runner's" do
        expect(updated_lockfile_content).to include("bundler (4.0.12) sha256=old12")
        expect(updated_lockfile_content).not_to include("bundler (4.0.13)")
      end
    end

    context "when the project pins bundler in DEPENDENCIES" do
      let(:project_name) { "checksums_bundler_dep_pinned" }
      let(:generated_lockfile) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              business (1.5.0)

          PLATFORMS
            ruby

          DEPENDENCIES
            bundler (~> 4.0)
            business (~> 1.5)

          CHECKSUMS
            business (1.5.0) sha256=123
            bundler (4.0.13) sha256=new13

          BUNDLED WITH
             4.0.13
        LOCKFILE
      end

      it "restores the checksum without touching the DEPENDENCIES entry" do
        expect(updated_lockfile_content).to include("bundler (4.0.12) sha256=old12")
        expect(updated_lockfile_content).to include("  bundler (~> 4.0)\n")
        expect(updated_lockfile_content).not_to include("bundler (4.0.13)")
      end
    end

    context "when the generated lockfile has no CHECKSUMS section" do
      let(:project_name) { "checksums_bundler_4_0_12" }
      let(:generated_lockfile) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              business (1.5.0)

          PLATFORMS
            ruby

          DEPENDENCIES
            business (~> 1.5)

          BUNDLED WITH
             4.0.12
        LOCKFILE
      end

      it "leaves the generated lockfile untouched without raising" do
        expect { updated_lockfile_content }.not_to raise_error
        expect(updated_lockfile_content).not_to include("CHECKSUMS")
      end
    end

    context "when the generated lockfile has CHECKSUMS but no bundler entry" do
      let(:project_name) { "checksums_bundler_4_0_12" }
      let(:generated_lockfile) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              business (1.5.0)

          PLATFORMS
            ruby

          DEPENDENCIES
            business (~> 1.5)

          CHECKSUMS
            business (1.5.0) sha256=123

          BUNDLED WITH
             4.0.12
        LOCKFILE
      end

      it "does not inject the original bundler checksum" do
        expect(updated_lockfile_content).not_to include("bundler (4.0.12)")
        expect(updated_lockfile_content).not_to include("bundler (4.0.13)")
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
