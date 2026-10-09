# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/apm/update_checker"
require "dependabot/apm/version"
require "dependabot/git_metadata_fetcher"
require "dependabot/git_tag_with_detail"
require "dependabot/package/release_cooldown_options"
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

    context "when only a non-first requirement family has a newer tag" do
      let(:dependency_name) { "org/mono/skills/review" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "1.4.0",
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "apm.yml",
              # `-v` family, already at its latest tag (review-v1.4.0).
              source: { type: "git", url: "https://github.com/#{dependency_name}", ref: "review-v1.4.0",
                        branch: nil },
              metadata: { declaration_string: "#{dependency_name}#review-v1.4.0" }
            },
            {
              requirement: nil,
              groups: [],
              file: "apm.yml",
              # `--v` family, behind its latest tag (review--v1.5.0).
              source: { type: "git", url: "https://github.com/#{dependency_name}", ref: "review--v1.0.0",
                        branch: nil },
              metadata: { declaration_string: "#{dependency_name}#review--v1.0.0" }
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

      # The first family is already at its latest tag; resolving only through it
      # would report no update and stop the base can_update? from ever consulting
      # updated_requirements for the second family.
      it "reports the newer tag from the non-first family as the latest version" do
        expect(latest_version).to eq(Dependabot::Apm::Version.new("1.5.0"))
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

    context "when merged declarations span different version lines under cooldown" do
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
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 0,
          semver_major_days: 90,
          semver_minor_days: 0,
          semver_patch_days: 0,
          include: [dependency_name]
        )
      end
      let(:tag_details) do
        today = Time.now.strftime("%Y-%m-%d")
        [
          Dependabot::GitTagWithDetail.new(tag: "v1.0.0", release_date: "2020-01-01"),
          Dependabot::GitTagWithDetail.new(tag: "v1.1.0", release_date: "2020-06-01"),
          Dependabot::GitTagWithDetail.new(tag: "v1.2.0", release_date: "2020-09-01"),
          Dependabot::GitTagWithDetail.new(tag: "v2.0.0", release_date: today),
          Dependabot::GitTagWithDetail.new(tag: "v2.1.0", release_date: today)
        ]
      end
      let(:shared_metadata_fetcher) do
        Dependabot::GitMetadataFetcher.new(
          url: "https://github.com/#{dependency_name}",
          credentials: github_credentials
        )
      end

      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "apm-package-two-lines"),
            headers: { "content-type" => "application/x-git-upload-pack-advertisement" }
          )
        allow(Dependabot::GitMetadataFetcher).to receive(:new).and_return(shared_metadata_fetcher)
        allow(shared_metadata_fetcher).to receive(:refs_for_tag_with_detail).and_return(tag_details)
      end

      # v2.1.0 is still inside the 90-day MAJOR cooldown but outside the 0-day
      # MINOR one. The v2.0.0 declaration must be scoped to its own pin so the
      # candidate reads as a minor bump (2.0 -> 2.1) and is allowed, instead of a
      # major bump from the merged dependency's lowest pin (1.0 -> 2.1) that
      # cooldown would hold back -- which would leave the declaration on v2.0.0.
      it "classifies cooldown per declaration, not the merged lowest pin" do
        refs = updated_requirements.map { |req| req[:source][:ref] }
        expect(refs).to eq(%w(v1.2.0 v2.1.0))
      end
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

  describe "#updated_dependencies" do
    subject(:updated_dependency) do
      checker.updated_dependencies(requirements_to_unlock: :own).first
    end

    context "when merged families resolve to different post-update tags" do
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
              source: { type: "git", url: "https://github.com/#{dependency_name}", ref: "review-v1.4.0",
                        branch: nil },
              metadata: { declaration_string: "#{dependency_name}#review-v1.4.0" }
            },
            {
              requirement: nil,
              groups: [],
              file: "apm.yml",
              source: { type: "git", url: "https://github.com/#{dependency_name}", ref: "review--v1.0.0",
                        branch: nil },
              metadata: { declaration_string: "#{dependency_name}#review--v1.0.0" }
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

      # latest_version reports 1.5.0 so the base can_update? gate fires for the
      # `--v` family, but DependencySet defines the merged version as the LOWEST
      # pin. After the update the pins are review-v1.4.0 and review--v1.5.0, so
      # the reported version must be 1.4.0 (consistent with the rewritten
      # requirements), not the 1.5.0 used only to gate the update.
      it "reports the lowest post-update pin as the merged version" do
        expect(updated_dependency.version).to eq("1.4.0")
      end

      it "still rewrites each family to its own latest tag" do
        refs = updated_dependency.requirements.map { |req| req[:source][:ref] }
        expect(refs).to eq(%w(review-v1.4.0 review--v1.5.0))
      end
    end
  end

  describe "#lowest_security_fix_version" do
    # APM packages have no advisory-database coverage, so Dependabot never runs
    # security updates for them; the method is a nil stub satisfying the base
    # contract rather than carrying unreachable resolution logic.
    it "returns nil because APM has no security updates" do
      expect(checker.lowest_security_fix_version).to be_nil
    end
  end

  context "with a full SHA pin" do
    let(:reference) { "a" * 40 }
    let(:dependency_version) { reference }

    before do
      stub_request(:get, service_pack_url)
        .to_return(
          status: 200,
          body: fixture("git", "upload_packs", "apm-package-annotated-tags"),
          headers: { "content-type" => "application/x-git-upload-pack-advertisement" }
        )
    end

    it "moves to the commit of the latest annotated, non-prerelease release" do
      expect(checker.latest_version).to eq("c" * 40)
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
    end

    it "rewrites the SHA and records the release tag" do
      expect(checker.updated_requirements.first.source_string("ref")).to eq("c" * 40)
      expect(checker.updated_requirements.first.metadata_string("release_tag")).to eq("v1.2.0")
    end

    it "reports the release commit as the new version" do
      updated = checker.updated_dependencies(requirements_to_unlock: :own).first
      expect(updated.version).to eq("c" * 40)
      expect(updated.previous_version).to eq("a" * 40)
    end

    context "when the SHA is pinned in upper case" do
      let(:reference) { "C" * 40 }
      let(:dependency_version) { reference.downcase }

      it "treats the release commit as already pinned" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(checker.updated_requirements).to eq(dependency.requirements)
      end
    end

    context "when the pinned commit is a newer tagged release" do
      let(:reference) { "e" * 40 }

      it "does not downgrade to the latest annotated release" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(checker.updated_requirements).to eq(dependency.requirements)
      end
    end

    context "when the pinned commit is untagged" do
      let(:reference) { "9" * 40 }

      it "moves to the latest annotated release, as apm update does" do
        expect(checker.latest_version).to eq("c" * 40)
      end
    end
  end

  context "with a branch pin" do
    let(:reference) { "main" }
    let(:dependency_version) { "0" * 40 }
    let(:dependency_source) do
      { type: "git", url: "https://github.com/#{dependency_name}", ref: "main", branch: "main" }
    end

    it "moves to the branch's head commit without changing the manifest requirement" do
      expect(checker.latest_version).to eq("1" * 40)
      expect(checker.latest_resolvable_version_with_no_unlock).to eq("1" * 40)
      expect(checker.updated_requirements).to eq(dependency.requirements)
      expect(checker.can_update?(requirements_to_unlock: :none)).to be(true)
    end

    context "when the branch is already at its head commit" do
      let(:dependency_version) { "1" * 40 }

      it "is up to date" do
        expect(checker.can_update?(requirements_to_unlock: :none)).to be(false)
      end
    end

    context "when the branch no longer exists" do
      let(:dependency_source) do
        { type: "git", url: "https://github.com/#{dependency_name}", ref: "gone", branch: "gone" }
      end

      it "raises a GitDependencyReferenceNotFound error" do
        expect { checker.latest_version }.to raise_error(Dependabot::GitDependencyReferenceNotFound)
      end
    end
  end
end
