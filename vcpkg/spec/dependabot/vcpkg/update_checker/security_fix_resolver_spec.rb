# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/security_advisory"

require "dependabot/vcpkg/package/versions_database"
require "dependabot/vcpkg/update_checker/security_fix_resolver"

RSpec.describe Dependabot::Vcpkg::UpdateChecker::SecurityFixResolver do
  subject(:fix) { resolver.fix }

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      lowest_comparable_version: lowest_comparable_version,
      versions_database: versions_database
    )
  end

  let(:versions_database) { instance_double(Dependabot::Vcpkg::Package::VersionsDatabase) }
  let(:baseline_sha) { "fe1cde61e971d53c9687cf9a46308f8f55da19fa" }
  let(:port) { "zlib" }
  let(:current_version) { "1.2.11" }
  let(:constraint) { nil }
  let(:ignored_versions) { [] }
  let(:lowest_comparable_version) { nil }

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "vcpkg.json",
        content: %({ "builtin-baseline": "#{baseline_sha}", "dependencies": ["#{port}"] })
      )
    ]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: port,
      version: current_version,
      package_manager: "vcpkg",
      requirements: [{ requirement: constraint, groups: [], source: nil, file: "vcpkg.json" }]
    )
  end

  let(:security_advisories) do
    [
      Dependabot::SecurityAdvisory.new(
        dependency_name: port,
        package_manager: "vcpkg",
        vulnerable_versions: ["<= 1.2.12"]
      )
    ]
  end

  # Release tags oldest first, with the version floor each one sets for the port.
  let(:tag_baselines) do
    {
      "2021.04.30" => "1.2.11",
      "2021.05.12" => "1.2.11#10",
      "2022.01.01" => "1.2.12",
      "2023.01.09" => "1.2.13",
      "2024.01.12" => "1.3.1"
    }
  end

  let(:published_versions) { %w(1.3.1 1.2.13 1.2.12 1.2.11#10 1.2.11) }

  before do
    allow(versions_database).to receive_messages(
      release_tags: tag_baselines.keys,
      commit_sha_for: "c" * 40
    )
    allow(versions_database).to receive(:ancestor?) do |ancestor:, descendant:|
      ancestor == baseline_sha && tag_baselines.keys.index(descendant).to_i >= 1
    end
    allow(versions_database).to receive(:baseline_version_for) do |port:, ref:|
      _ = port
      text = tag_baselines[ref]
      text && Dependabot::Vcpkg::Version.new(text)
    end
    allow(versions_database).to receive(:versions_for) do
      published_versions.map do |text|
        Dependabot::Vcpkg::Package::VersionsDatabase::PortVersion.new(
          version: Dependabot::Vcpkg::Version.new(text),
          scheme: "version",
          git_tree: text
        )
      end
    end
  end

  describe "raising the baseline" do
    it "picks the oldest release tag whose floor is safe" do
      expect(fix).to have_attributes(
        kind: :baseline,
        version: Dependabot::Vcpkg::Version.new("1.2.13"),
        baseline_tag: "2023.01.09",
        baseline_commit_sha: "c" * 40
      )
    end

    it "never moves the baseline backwards" do
      resolver.fix

      expect(versions_database).not_to have_received(:baseline_version_for).with(port:, ref: "2021.04.30")
    end

    it "resolves the advisory even when a constraint is declared below the new floor" do
      allow(dependency).to receive(:requirements)
        .and_return([{ requirement: ">=1.2.11", groups: [], source: nil, file: "vcpkg.json" }])

      expect(fix.kind).to eq(:baseline)
    end

    context "when the release floors are all still vulnerable" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: ["<= 1.3.1"]
          )
        ]
      end

      it "offers no fix when nothing else is safe either" do
        expect(fix).to be_nil
      end
    end

    # Advisories enumerate affected versions rather than describing ranges, so a safe floor can sit
    # between two vulnerable ones. Bisecting the tag list would step over it.
    context "when safe floors are not contiguous" do
      let(:tag_baselines) do
        {
          "2021.04.30" => "7.50.0",
          "2021.05.12" => "7.79.0",
          "2022.01.01" => "7.80.0",
          "2023.01.09" => "7.81.0",
          "2024.01.12" => "7.84.0"
        }
      end
      let(:current_version) { "7.10.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: ["< 7.79.0"]
          ),
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: [">= 7.80.0, < 7.84.0"]
          )
        ]
      end

      it "picks the earliest safe floor rather than skipping past it" do
        expect(fix).to have_attributes(kind: :baseline, baseline_tag: "2021.05.12")
      end
    end

    context "when only the earliest candidate floor is safe" do
      let(:tag_baselines) do
        {
          "2021.04.30" => "1.9.0",
          "2021.05.12" => "2.0.0",
          "2022.01.01" => "2.1.0",
          "2023.01.09" => "2.2.0"
        }
      end
      let(:current_version) { "1.5.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: ["< 2.0.0"]
          ),
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: [">= 2.1.0"]
          )
        ]
      end

      it "still finds it" do
        expect(fix).to have_attributes(kind: :baseline, baseline_tag: "2021.05.12")
      end
    end

    context "when the manifest pins no baseline" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "vcpkg.json", content: %({ "dependencies": ["zlib"] }))]
      end

      it "falls through to pinning, because there is no baseline to raise" do
        expect(fix).to have_attributes(kind: :override, baseline_tag: nil)
      end
    end
  end

  describe "raising the version constraint" do
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: port,
          package_manager: "vcpkg",
          vulnerable_versions: ["<= 1.3.1"]
        )
      ]
    end
    let(:published_versions) { %w(1.3.2 1.3.1 1.2.13 1.2.12 1.2.11#10 1.2.11) }
    let(:lowest_comparable_version) { Dependabot::Vcpkg::Version.new("1.3.2") }

    it "falls back to the constraint when no release floor carries the fix" do
      expect(fix).to have_attributes(
        kind: :version_constraint,
        version: Dependabot::Vcpkg::Version.new("1.3.2"),
        baseline_tag: nil
      )
    end
  end

  describe "pinning with an override" do
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: port,
          package_manager: "vcpkg",
          vulnerable_versions: ["<= 1.3.1"]
        )
      ]
    end
    let(:published_versions) { %w(1.3.2 1.3.1 1.2.13 1.2.12 1.2.11#10 1.2.11) }

    it "pins the earliest safe version published after the current one" do
      expect(fix).to have_attributes(
        kind: :override,
        version: Dependabot::Vcpkg::Version.new("1.3.2")
      )
    end

    context "when several safe versions were published after the current one" do
      let(:published_versions) { %w(1.4.0 1.3.2 1.3.1 1.2.13 1.2.12 1.2.11#10 1.2.11) }

      it "chooses the smallest upgrade" do
        expect(fix.version).to eq(Dependabot::Vcpkg::Version.new("1.3.2"))
      end
    end

    context "when the only safe versions were published before the current one" do
      let(:current_version) { "1.3.1" }
      let(:published_versions) { %w(1.3.1 1.2.13 1.2.12) }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: ["= 1.3.1", "= 1.2.13"]
          )
        ]
      end

      it "offers no fix" do
        expect(fix).to be_nil
      end
    end

    context "when the current version is absent from the versions database" do
      let(:current_version) { "1.3.5" }
      let(:published_versions) { %w(1.4.0 1.3.1 1.2.13 1.0.0) }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: ["= 1.3.5", ">= 1.4.0"]
          )
        ]
      end

      it "offers no pin, rather than downgrading the port" do
        expect(fix).to be_nil
      end
    end
  end

  describe "ignore conditions" do
    let(:ignored_versions) { ["> 1.2.11#10"] }

    it "does not offer an ignored version" do
      expect(fix).to be_nil
    end
  end

  describe "when the dependency is not vulnerable data" do
    context "with no advisories" do
      let(:security_advisories) { [] }

      it { expect(fix).to be_nil }
    end

    context "with an unparseable current version" do
      let(:current_version) { nil }

      it { expect(fix).to be_nil }
    end
  end
end
