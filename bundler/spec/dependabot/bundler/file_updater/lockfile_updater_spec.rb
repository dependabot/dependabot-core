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

    context "when original lockfile uses Bundler 2.7.2 with no bundler checksum" do
      let(:project_name) { "checksums_bundler_2_7_2" }
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
            bundler (2.7.2) sha256=runner272

          BUNDLED WITH
             2.7.2
        LOCKFILE
      end

      it "strips the runner-injected bundler checksum regardless of version" do
        expect(updated_lockfile_content).not_to include("bundler (2.7.2)")
      end
    end

    context "when original lockfile uses Bundler 4.0.10 with no bundler checksum" do
      let(:project_name) { "checksums_bundler_4_0_10" }

      it "removes newly added bundler checksums" do
        expect(updated_lockfile_content).not_to include("bundler (4.0.11)")
      end

      it "preserves the CHECKSUMS header after stripping the bundler entry (regression for #15193)" do
        expect(updated_lockfile_content).to match(/^CHECKSUMS\n  business \(1\.5\.0\)/)
      end
    end

    context "when original lockfile uses Bundler 4.0.11 with no bundler checksum" do
      let(:project_name) { "checksums_bundler_4_0_11" }

      it "strips the runner-injected bundler checksum, preserving the original's absence" do
        expect(updated_lockfile_content).not_to include("bundler (4.0.11)")
      end
    end

    context "when original lockfile uses Bundler 4.0.15 (>= 4.0.11) with no bundler checksum" do
      # Regression for the default-gem install case (ruby/rubygems#9512,
      # dependabot-core#15215): the runner's bundler adds an entry for its own
      # version (4.0.17) that need not match BUNDLED WITH (4.0.15). Dependabot
      # must not persist it, or the lockfile churns on the next local install.
      let(:project_name) { "checksums_bundler_4_0_15" }
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
            bundler (4.0.17) sha256=runner17

          BUNDLED WITH
             4.0.15
        LOCKFILE
      end

      it "strips the runner-injected bundler checksum" do
        expect(updated_lockfile_content).not_to include("bundler (4.0.17)")
        expect(updated_lockfile_content).not_to match(/^  bundler \(/)
      end

      it "preserves the CHECKSUMS header and other entries" do
        expect(updated_lockfile_content).to match(/^CHECKSUMS\n  business \(1\.5\.0\)/)
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

    context "when the project pins bundler but the original CHECKSUMS section omits it" do
      let(:project_name) { "checksums_bundler_dep_pinned_no_checksum" }
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
            bundler (4.0.17) sha256=runner17

          BUNDLED WITH
             4.0.17
        LOCKFILE
      end

      it "strips the checksum without touching the DEPENDENCIES entry" do
        expect(updated_lockfile_content).to include("  bundler (~> 4.0)\n")
        expect(updated_lockfile_content).not_to include("bundler (4.0.17) sha256=runner17")
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

    context "when the generated CHECKSUMS section contains only the bundler entry" do
      let(:project_name) { "checksums_bundler_4_0_15" }
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
            bundler (4.0.17) sha256=runner17

          BUNDLED WITH
             4.0.17
        LOCKFILE
      end

      it "preserves a parseable empty CHECKSUMS section after stripping" do
        expect(updated_lockfile_content).to include("CHECKSUMS\n\nBUNDLED WITH")
        expect(updated_lockfile_content).not_to include("bundler (4.0.17)")
        expect { ::Bundler::LockfileParser.new(updated_lockfile_content) }.not_to raise_error
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

      it "does not re-add the original bundler checksum" do
        original_lockfile = files.find { |file| file.name == "Gemfile.lock" }

        expect(original_lockfile&.content).to include("bundler (4.0.12) sha256=old12")
        expect(updated_lockfile_content).not_to include("bundler (4.0.12)")
        expect(updated_lockfile_content).not_to include("bundler (4.0.13)")
      end
    end

    context "when original lockfile already pins a bundler checksum (control)" do
      let(:project_name) { "checksums_bundler_4_0_12" }

      it "preserves the CHECKSUMS header" do
        expect(updated_lockfile_content).to include("CHECKSUMS")
      end
    end
  end

  describe "CHECKSUMS_SECTION" do
    let(:lockfile_body) do
      <<~LOCKFILE
        DEPENDENCIES
          business (~> 1.5)

        CHECKSUMS
          business (1.5.0) sha256=abc
          bundler (4.0.8) sha256=def

        BUNDLED WITH
           4.0.8
      LOCKFILE
    end

    # Regression: the constant used the `/m` flag, which made the greedy `.*`
    # in `entries` match newlines and swallow everything to EOF — including the
    # trailing `BUNDLED WITH` section. See #15193 / #15229.
    it "captures only the indented checksum lines, not the BUNDLED WITH section" do
      match = lockfile_body.match(described_class::CHECKSUMS_SECTION)

      expect(match[:entries]).to eq(
        "  business (1.5.0) sha256=abc\n  bundler (4.0.8) sha256=def\n"
      )
      expect(match[:entries]).not_to include("BUNDLED WITH")
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
