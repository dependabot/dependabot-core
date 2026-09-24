# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/security_advisory"
require "dependabot/apm/update_checker"
require "dependabot/apm/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Apm::UpdateChecker do
  let(:dependency_name) { "microsoft/edge-ai" }
  let(:reference) { "v1.0.0" }
  let(:dependency_version) do
    return unless Dependabot::Apm::Version.correct?(reference)

    Dependabot::Apm::Version.new(reference).to_s
  end
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/#{dependency_name}",
      ref: reference,
      branch: nil
    }
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: "apm.yml",
        source: dependency_source,
        metadata: { declaration_string: "#{dependency_name}##{reference}" }
      }],
      package_manager: "apm"
    )
  end
  let(:service_pack_url) do
    "https://github.com/#{dependency_name}.git/info/refs?service=git-upload-pack"
  end
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:update_cooldown) { nil }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: github_credentials,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      update_cooldown: update_cooldown
    )
  end

  before do
    stub_request(:get, service_pack_url)
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", "apm-package"),
        headers: { "content-type" => "application/x-git-upload-pack-advertisement" }
      )
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    it "returns the highest semver tag" do
      expect(latest_version).to eq(Dependabot::Apm::Version.new("1.2.0"))
    end

    context "when the ref is a branch rather than a version" do
      let(:reference) { "main" }

      it "does not offer a version bump" do
        expect(latest_version).to be_nil
      end
    end

    context "when the latest allowed version is capped by ignored_versions" do
      let(:ignored_versions) { ["> 1.1.0"] }

      it "returns the highest non-ignored tag" do
        expect(latest_version).to eq(Dependabot::Apm::Version.new("1.1.0"))
      end
    end

    context "when the repository has non-SemVer and build-metadata tags" do
      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "apm-package-edge-tags"),
            headers: { "content-type" => "application/x-git-upload-pack-advertisement" }
          )
      end

      # The shared GitCommitChecker regex would accept `v1.2.3.4` (raising when
      # Apm::Version is built) and reject the build-metadata tag; the APM
      # subclass filters both through strict SemVer instead.
      it "ignores non-SemVer tags and selects the build-metadata release" do
        expect(latest_version).to eq(Dependabot::Apm::Version.new("1.3.0+build.5"))
      end

      context "when the current ref is itself a non-SemVer tag" do
        let(:reference) { "v1.2.3.4" }

        it "does not treat it as a version and offers no update" do
          expect(latest_version).to be_nil
        end
      end
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when the pinned tag is behind the latest" do
      let(:reference) { "v1.0.0" }

      it { is_expected.to be(true) }
    end

    context "when the pinned tag is already the latest" do
      let(:reference) { "v1.2.0" }

      it { is_expected.to be(false) }
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    it "rewrites the source ref to the latest tag" do
      expect(updated_requirements.first[:source][:ref]).to eq("v1.2.0")
    end

    it "preserves the declaration_string metadata" do
      expect(updated_requirements.first[:metadata])
        .to eq(declaration_string: "microsoft/edge-ai#v1.0.0")
    end

    context "when the ref is a branch rather than a version" do
      let(:reference) { "main" }

      it "leaves the requirements unchanged" do
        expect(updated_requirements).to eq(dependency.requirements)
      end
    end

    context "when the current ref is a package-scoped tag" do
      let(:dependency_name) { "org/mono/skills/review" }
      let(:reference) { "review--v1.0.0" }

      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "apm-package-scoped-tags"),
            headers: { "content-type" => "application/x-git-upload-pack-advertisement" }
          )
      end

      it "rewrites the requirement to the latest same-scope tag" do
        expect(updated_requirements.first[:source][:ref]).to eq("review--v1.5.0")
      end
    end

    context "when merged requirements carry different refs" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "1.0.0",
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "apm.yml",
              source: { type: "git", url: "https://github.com/#{dependency_name}", ref: "v1.0.0", branch: nil },
              metadata: { declaration_string: "#{dependency_name}#v1.0.0" }
            },
            {
              requirement: nil,
              groups: [],
              file: "apm.yml",
              source: { type: "git", url: "https://github.com/#{dependency_name}", ref: "v2.0.0", branch: nil },
              metadata: { declaration_string: "#{dependency_name}#v2.0.0" }
            }
          ],
          package_manager: "apm"
        )
      end

      # The tag is chosen from the combined (lowest) version, so the lower ref is
      # bumped while the already-higher ref must not be rewritten downward.
      it "bumps the lower ref and leaves the already-higher ref untouched" do
        refs = updated_requirements.map { |req| req[:source][:ref] }
        expect(refs).to eq(%w(v1.2.0 v2.0.0))
      end
    end

    context "when merged requirements carry different scoped-tag families" do
      let(:dependency_name) { "org/mono/skills/review" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "1.0.0",
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "apm.yml",
              source: { type: "git", url: "https://github.com/#{dependency_name}", ref: "review--v1.0.0",
                        branch: nil },
              metadata: { declaration_string: "#{dependency_name}#review--v1.0.0" }
            },
            {
              requirement: nil,
              groups: [],
              file: "apm.yml",
              source: { type: "git", url: "https://github.com/#{dependency_name}", ref: "review-v1.0.0",
                        branch: nil },
              metadata: { declaration_string: "#{dependency_name}#review-v1.0.0" }
            }
          ],
          package_manager: "apm"
        )
      end

      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "apm-package-scoped-tags"),
            headers: { "content-type" => "application/x-git-upload-pack-advertisement" }
          )
      end

      # Each declaration is resolved within its own tag family, so the `--v` pin
      # bumps to the latest `--v` tag and the `-v` pin to the latest `-v` tag,
      # rather than both collapsing into the first requirement's family.
      it "bumps each requirement within its own tag family" do
        refs = updated_requirements.map { |req| req[:source][:ref] }
        expect(refs).to eq(%w(review--v1.5.0 review-v1.4.0))
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { checker.lowest_security_fix_version }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "apm",
          vulnerable_versions: ["< 1.1.0"]
        )
      ]
    end

    it "returns the lowest non-vulnerable tag" do
      expect(lowest_security_fix_version).to eq(Dependabot::Apm::Version.new("1.1.0"))
    end

    context "when only the current version line is vulnerable" do
      let(:reference) { "v1.1.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "apm",
            vulnerable_versions: [">= 1.1.0, < 1.2.0"]
          )
        ]
      end

      it "upgrades to the fix rather than downgrading to an older unaffected tag" do
        expect(lowest_security_fix_version).to eq(Dependabot::Apm::Version.new("1.2.0"))
      end
    end
  end
end
