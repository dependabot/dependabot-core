# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/security_advisory"
require "dependabot/package/release_cooldown_options"
require "dependabot/nimble/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Nimble::UpdateChecker do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "chronos",
      version: "4.0.4",
      package_manager: "nimble",
      requirements: [{ requirement: ">= 4.0.4", file: "example.nimble", groups: ["dependencies"], source: nil }]
    )
  end
  let(:dependency_files) do
    [Dependabot::DependencyFile.new(name: "example.nimble", content: 'requires "chronos >= 4.0.4"')]
  end
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:update_cooldown) { nil }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      update_cooldown: update_cooldown
    )
  end
  let(:now) { Time.now.utc }
  let(:release_dates) do
    { "v4.0.4" => now - (60 * 86_400), "v4.1.0" => now - (30 * 86_400), "v4.2.0" => now - (2 * 86_400),
      "v5.0.0-rc1" => now - 86_400 }
  end

  before do
    releases = release_dates.map do |tag, date|
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::Nimble::Version.new(tag), tag: tag, released_at: date
      )
    end
    fetcher = instance_double(
      Dependabot::Nimble::Package::PackageDetailsFetcher,
      fetch: Dependabot::Package::PackageDetails.new(dependency: dependency, releases: releases)
    )
    allow(Dependabot::Nimble::Package::PackageDetailsFetcher).to receive(:new).and_return(fetcher)
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    it "is the highest release, leaving out pre-releases" do
      expect(checker.latest_version).to eq(Dependabot::Nimble::Version.new("4.2.0"))
    end

    context "with a version ignored" do
      let(:ignored_versions) { [">= 4.2.0"] }

      it "skips it" do
        expect(checker.latest_version).to eq(Dependabot::Nimble::Version.new("4.1.0"))
      end
    end

    context "with a cooldown" do
      let(:update_cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }

      it "skips a release newer than the cooldown" do
        expect(checker.latest_version).to eq(Dependabot::Nimble::Version.new("4.1.0"))
      end
    end
  end

  describe "#up_to_date?" do
    it "is false when a newer release exists" do
      expect(checker).not_to be_up_to_date
    end

    context "when the dependency is at the latest release" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "chronos",
          version: "4.2.0",
          package_manager: "nimble",
          requirements: [{ requirement: ">= 4.2.0", file: "example.nimble", groups: ["dependencies"], source: nil }]
        )
      end

      it "is true" do
        expect(checker).to be_up_to_date
      end
    end
  end

  describe "#updated_requirements" do
    it "raises the lower bound to the latest release" do
      expect(checker.updated_requirements.map(&:requirement)).to eq([">= 4.2.0"])
    end

    context "with a range that excludes the latest release" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "chronos",
          version: "4.0.4",
          package_manager: "nimble",
          requirements: [{ requirement: ">= 4.0.4 & < 4.2", file: "example.nimble", groups: ["dependencies"],
                           source: nil }]
        )
      end

      it "leaves it alone" do
        expect(checker.updated_requirements.map(&:requirement)).to eq([">= 4.0.4 & < 4.2"])
      end
    end
  end

  describe "#updated_dependencies" do
    it "updates the version and the requirement" do
      updated = checker.updated_dependencies(requirements_to_unlock: :own).first
      expect([updated.version, updated.requirements.first[:requirement]]).to eq(["4.2.0", ">= 4.2.0"])
    end
  end

  context "with a security advisory" do
    let(:security_advisories) do
      [Dependabot::SecurityAdvisory.new(
        dependency_name: "chronos", package_manager: "nimble", vulnerable_versions: ["< 4.1.0"]
      )]
    end

    it "targets the lowest release that fixes it" do
      expect(checker.lowest_security_fix_version).to eq(Dependabot::Nimble::Version.new("4.1.0"))
    end
  end
end
