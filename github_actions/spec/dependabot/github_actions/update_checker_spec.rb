# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/github_actions/update_checker"
require "dependabot/github_actions/metadata_finder"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::GithubActions::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: github_credentials,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end
  let(:security_advisories) { [] }
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        source: dependency_source,
        metadata: { declaration_string: "#{dependency_name}@master" }
      }],
      package_manager: "github_actions"
    )
  end
  let(:dependency_name) { "actions/setup-node" }
  let(:dependency_version) do
    return unless Dependabot::GithubActions::Version.correct?(reference)

    Dependabot::GithubActions::Version.new(reference).to_s
  end
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/#{dependency_name}",
      ref: reference,
      branch: nil
    }
  end
  let(:reference) { "master" }
  let(:service_pack_url) do
    "https://github.com/#{dependency_name}.git/info/refs" \
      "?service=git-upload-pack"
  end
  let(:git_commit_checker) do
    Dependabot::GitCommitChecker.new(
      dependency: dependency,
      credentials: github_credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end
  before do
    stub_request(:get, service_pack_url).
      to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end
  let(:upload_pack_fixture) { "setup-node" }

  shared_context "with multiple git sources" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "actions/checkout",
        version: nil,
        package_manager: "github_actions",
        requirements: [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@v2.1.0" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.1.0",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@master" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "master",
            branch: nil
          }
        }]
      )
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "given a dependency with a branch reference" do
      let(:reference) { "master" }
      it { is_expected.to be_falsey }
    end

    context "given a dependency with a tag reference" do
      let(:reference) { "v1.0.1" }
      it { is_expected.to be_truthy }

      context "that is up-to-date" do
        let(:reference) { "v1.1.0" }
        it { is_expected.to be_falsey }
      end

      context "that is different but up-to-date" do
        let(:upload_pack_fixture) { "checkout" }
        let(:reference) { "v2" }
        it { is_expected.to be_falsey }
      end

      context "that is not version-like" do
        let(:upload_pack_fixture) { "reactive" }
        let(:reference) { "refassm-blog-post" }
        it { is_expected.to be_falsey }
      end

      context "that is a git commit SHA pointing to the tip of a branch not named like a version" do
        let(:upload_pack_fixture) { "setup-node" }
        let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }
        let(:reference) { tip_of_master }

        it { is_expected.to be_falsey }
      end

      context "that is a git commit SHA pointing to the tip of a branch named like a version" do
        let(:upload_pack_fixture) { "run-vcpkg" }

        context "and there's a branch named like a higher version" do
          let(:tip_of_v6) { "205a4bde2b6ddf941a102fb50320ea1aa9338233" }

          let(:reference) { tip_of_v6 }

          it { is_expected.to be_truthy }
        end

        context "and there's no branch named like a higher version" do
          let(:tip_of_v10) { "34684effe7451ea95f60397e56ba34c06daced68" }

          let(:reference) { tip_of_v10 }

          it { is_expected.to be_falsey }
        end
      end

      context "that is a git commit SHA pointing to the tip of a version tag" do
        let(:upload_pack_fixture) { "setup-node" }
        let(:v1_0_0_tag_sha) { "0d7d2ca66539aca4af6c5102e29a33757e2c2d2c" }
        let(:v1_1_0_tag_sha) { "5273d0df9c603edc4284ac8402cf650b4f1f6686" }

        context "and there's a higher version tag" do
          let(:reference) { v1_0_0_tag_sha }

          it { is_expected.to be_truthy }
        end

        context "and there's no higher version tag" do
          let(:reference) { v1_1_0_tag_sha }

          it { is_expected.to be_falsey }
        end
      end

      context "with a dependency that has a latest requirement and a valid version", vcr: true do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "actions/create-release",
            version: "1",
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/create-release",
                ref: "latest",
                branch: nil
              },
              metadata: { declaration_string: "actions/create-release@latest" }
            }, {
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/create-release",
                ref: "v1",
                branch: nil
              },
              metadata: { declaration_string: "actions/create-release@v1" }
            }],
            package_manager: "github_actions"
          )
        end

        it "returns the expected value" do
          expect(subject).to be_falsey
        end
      end
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }

    context "given a dependency with a branch reference" do
      let(:reference) { "master" }
      it { is_expected.to eq(tip_of_master) }
    end

    context "given a dependency with a tag reference" do
      let(:reference) { "v1.0.1" }
      it { is_expected.to eq(Dependabot::GithubActions::Version.new("1.1.0")) }

      context "and the latest version is being ignored" do
        let(:ignored_versions) { [">= 1.1.0"] }
        it { is_expected.to eq(Dependabot::GithubActions::Version.new("1.0.4")) }
      end

      context "and all versions are being ignored" do
        let(:ignored_versions) { [">= 0"] }
        it "returns current version" do
          expect(subject).to be_nil
        end

        context "raise_on_ignored" do
          let(:raise_on_ignored) { true }
          it "raises an error" do
            expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
          end
        end
      end

      context "and the latest version being also a branch" do
        let(:upload_pack_fixture) { "msbuild" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("1.1.3")) }
      end

      context "that is a major-only tag of the the latest version" do
        let(:reference) { "v1" }
        it { is_expected.to eq(Dependabot::GithubActions::Version.new("v1")) }
      end

      context "that is a major-minor tag of the the latest version" do
        let(:reference) { "v1.1" }
        it { is_expected.to eq(Dependabot::GithubActions::Version.new("v1.1")) }
      end

      context "that is a major-minor tag of a previous version" do
        let(:reference) { "v1.0" }
        it { is_expected.to eq(Dependabot::GithubActions::Version.new("v1.1")) }
      end
    end

    context "given a dependency with a tag reference with a major version upgrade available" do
      let(:upload_pack_fixture) { "setup-node-v2" }

      context "using the major version" do
        let(:reference) { "v1" }
        it { is_expected.to eq(Dependabot::GithubActions::Version.new("2")) }
      end

      context "using the major minor version" do
        let(:reference) { "v1.0" }
        it { is_expected.to eq(Dependabot::GithubActions::Version.new("2.1")) }
      end

      context "using the full version" do
        let(:reference) { "v1.0.0" }
        it { is_expected.to eq(Dependabot::GithubActions::Version.new("2.1.3")) }
      end
    end

    context "given a repo when the latest major does not point to the latest patch" do
      let(:upload_pack_fixture) { "cache" }

      context "and pinned to patch" do
        let(:reference) { "v2.1.3" }

        it "updates to the latest patch" do
          expect(subject).to eq(Dependabot::GithubActions::Version.new("3.0.11"))
        end
      end

      context "and pinned to major" do
        let(:reference) { "v2" }

        it "updates to the latest major" do
          expect(subject).to eq(Dependabot::GithubActions::Version.new("3"))
        end
      end
    end

    context "given a dependency that uses branches to track major releases" do
      let(:upload_pack_fixture) { "run-vcpkg" }

      context "using the major version" do
        let(:reference) { "v7" }
        it { is_expected.to eq(Dependabot::GithubActions::Version.new("10")) }
      end
    end

    context "given a dependency with a tag reference and a branch similar to the tag" do
      let(:upload_pack_fixture) { "download-artifact" }
      let(:reference) { "v2" }

      it { is_expected.to eq(Dependabot::GithubActions::Version.new("3")) }
    end

    context "given a git commit SHA pointing to the tip of a branch not named like a version" do
      let(:upload_pack_fixture) { "setup-node" }
      let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }
      let(:reference) { tip_of_master }

      it "considers the commit itself as the latest version" do
        expect(subject).to eq(tip_of_master)
      end
    end

    context "given a git commit SHA pointing to the tip of a branch named like a version" do
      let(:upload_pack_fixture) { "run-vcpkg" }

      context "and there's a branch named like a higher version" do
        let(:tip_of_v6) { "205a4bde2b6ddf941a102fb50320ea1aa9338233" }

        let(:reference) { tip_of_v6 }

        it { is_expected.to eq(Gem::Version.new("10.5")) }
      end

      context "and there's no branch named like a higher version" do
        let(:tip_of_v10) { "34684effe7451ea95f60397e56ba34c06daced68" }

        let(:reference) { tip_of_v10 }

        it { is_expected.to eq(Gem::Version.new("10.5")) }
      end
    end

    context "given a git commit SHA pointing to the tip of a version tag" do
      let(:upload_pack_fixture) { "setup-node" }
      let(:v1_0_0_tag_sha) { "0d7d2ca66539aca4af6c5102e29a33757e2c2d2c" }
      let(:v1_1_0_tag_sha) { "5273d0df9c603edc4284ac8402cf650b4f1f6686" }

      context "and there's a higher version tag" do
        let(:reference) { v1_0_0_tag_sha }

        it { is_expected.to eq(Gem::Version.new("1.1.0")) }
      end

      context "and there's no higher version tag" do
        let(:reference) { v1_1_0_tag_sha }

        it { is_expected.to eq(Gem::Version.new("1.1.0")) }
      end
    end

    context "given a dependency with multiple git refs", :vcr do
      include_context "with multiple git sources"

      it "returns the expected value" do
        expect(subject).to eq(Gem::Version.new("2.2.0"))
      end
    end

    context "given a realworld repository", :vcr do
      let(:upload_pack_fixture) { "github-action-push-to-another-repository" }
      let(:dependency_name) { "dependabot-fixtures/github-action-push-to-another-repository" }
      let(:dependency_version) { nil }

      let(:latest_commit_in_main) { "9e487f29582587eeb4837c0552c886bb0644b6b9" }
      let(:latest_commit_in_devel) { "c7563454dd4fbe0ea69095188860a62a19658a04" }

      context "when pinned to an up to date commit in the default branch" do
        let(:reference) { latest_commit_in_main }

        it "returns the expected value" do
          expect(subject).to eq(latest_commit_in_main)
        end
      end

      context "when pinned to an out of date commit in the default branch" do
        let(:reference) { "f4b9c90516ad3bdcfdc6f4fcf8ba937d0bd40465" }

        it "returns the expected value" do
          expect(subject).to eq(latest_commit_in_main)
        end
      end

      context "when pinned to an up to date commit in a non default branch" do
        let(:reference) { latest_commit_in_devel }

        it "returns the expected value" do
          expect(subject).to eq(latest_commit_in_devel)
        end
      end

      context "when pinned to an out of date commit in a non default branch" do
        let(:reference) { "96e7dec17bbeed08477b9edab6c3a573614b829d" }

        it "returns the expected value" do
          expect(subject).to eq(latest_commit_in_devel)
        end
      end
    end

    context "that is a git commit SHA not pointing to the tip of a branch" do
      let(:reference) { "1c24df3" }
      let(:exit_status) { double(success?: true) }

      before do
        checker.instance_variable_set(:@git_commit_checker, git_commit_checker)
        allow(git_commit_checker).to receive(:branch_or_ref_in_release?).and_return(false)
        allow(git_commit_checker).to receive(:head_commit_for_current_branch).and_return(reference)

        allow(Dir).to receive(:chdir).and_yield

        allow(Open3).to receive(:capture2e).
          with(anything, %r{git clone --no-recurse-submodules https://github\.com/actions/setup-node}).
          and_return(["", exit_status])
      end

      context "and it's in the current (default) branch" do
        before do
          allow(Open3).to receive(:capture2e).
            with(anything, "git branch --remotes --contains #{reference}").
            and_return(["  origin/HEAD -> origin/master\n  origin/master", exit_status])
        end

        it "can update to the latest version" do
          expect(subject).to eq(tip_of_master)
        end
      end

      context "and it's on a different branch" do
        let(:tip_of_releases_v1) { "5273d0df9c603edc4284ac8402cf650b4f1f6686" }

        before do
          allow(Open3).to receive(:capture2e).
            with(anything, "git branch --remotes --contains #{reference}").
            and_return(["  origin/releases/v1\n", exit_status])
        end

        it "can update to the latest version" do
          expect(subject).to eq(tip_of_releases_v1)
        end
      end

      context "and multiple branches include it, the current (default) branch among them" do
        before do
          allow(Open3).to receive(:capture2e).
            with(anything, "git branch --remotes --contains #{reference}").
            and_return(["  origin/HEAD -> origin/master\n  origin/master\n  origin/v1.1\n", exit_status])
        end

        it "can update to the latest version" do
          expect(subject).to eq(tip_of_master)
        end
      end

      context "and multiple branches include it, the current (default) branch NOT among them" do
        before do
          allow(Open3).to receive(:capture2e).
            with(anything, "git branch --remotes --contains #{reference}").
            and_return(["  origin/3.3-stable\n  origin/production\n", exit_status])
        end

        it "raises an error" do
          expect { subject }.
            to raise_error("Multiple ambiguous branches (3.3-stable, production) include #{reference}!")
        end
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    before { allow(checker).to receive(:latest_version).and_return("delegate") }
    it { is_expected.to eq("delegate") }
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { checker.lowest_security_fix_version }

    let(:upload_pack_fixture) { "ghas-to-csv" }

    let(:dependency_version) { "0.4.0" }
    let(:dependency_name) { "some-natalie/ghas-to-csv" }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "github_actions",
          vulnerable_versions: ["< 1.0"]
        )
      ]
    end

    context "when a supported newer version is available" do
      it "updates to the least new supported version" do
        is_expected.to eq(Dependabot::GithubActions::Version.new("1.0.0"))
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { ["= 1.0.0"] }

      it "doesn't return ignored versions" do
        is_expected.to eq(Dependabot::GithubActions::Version.new("2.0.0"))
      end
    end

    context "when there are non vulnerable versions lower than the current version" do
      let(:upload_pack_fixture) { "ghas-to-csv" }
      let(:dependency_version) { "1.0" }

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "github_actions",
            vulnerable_versions: ["< 0.4", "> 1.1, < 2.0"]
          )
        ]
      end

      it "still proposes an upgrade" do
        is_expected.to eq(Dependabot::GithubActions::Version.new("2.0.0"))
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lowest_resolvable_security_fix_version) { checker.lowest_resolvable_security_fix_version }

    before { allow(checker).to receive(:lowest_security_fix_version).and_return("delegate") }
    it { is_expected.to eq("delegate") }
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }

    context "given a dependency with a branch reference" do
      let(:reference) { "master" }
      it { is_expected.to eq(dependency.requirements) }
    end

    context "given a git commit SHA pointing to the tip of a branch not named like a version" do
      let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }
      let(:reference) { tip_of_master }

      context "when the specified reference is not in the latest release" do
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/setup-node",
              ref: tip_of_master,
              branch: nil
            },
            metadata: { declaration_string: "actions/setup-node@master" }
          }]
        end
        it { is_expected.to eq(expected_requirements) }
      end
    end

    context "given a git commit SHA pointing to the tip of a branch named like a version" do
      let(:upload_pack_fixture) { "run-vcpkg" }
      let(:tip_of_v6) { "205a4bde2b6ddf941a102fb50320ea1aa9338233" }
      let(:tip_of_v10) { "34684effe7451ea95f60397e56ba34c06daced68" }

      context "but not the latest version" do
        let(:reference) { tip_of_v6 }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/setup-node",
              ref: tip_of_v10,
              branch: nil
            },
            metadata: { declaration_string: "actions/setup-node@master" }
          }]
        end
        it { is_expected.to eq(expected_requirements) }
      end

      context "that's also the latest version" do
        let(:reference) { tip_of_v6 }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/setup-node",
              ref: tip_of_v10,
              branch: nil
            },
            metadata: { declaration_string: "actions/setup-node@master" }
          }]
        end

        it { is_expected.to eq(expected_requirements) }

        context "and the latest version is being ignored" do
          let(:ignored_versions) { [">= 10"] }
          let(:tip_of_v7) { "caea17de9196f8bd343efb496b1820e7438d1f83" }
          let(:expected_requirements) do
            [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/setup-node",
                ref: tip_of_v7,
                branch: nil
              },
              metadata: { declaration_string: "actions/setup-node@master" }
            }]
          end

          it { is_expected.to eq(expected_requirements) }
        end

        context "and the previous version is a short SHA" do
          let(:reference) { "5273d0df" }
          let(:expected_requirements) do
            [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/setup-node",
                ref: "5273d0df",
                branch: nil
              },
              metadata: { declaration_string: "actions/setup-node@master" }
            }]
          end

          it { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "given a dependency with a tag reference" do
      let(:reference) { "v1.0.1" }
      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/actions/setup-node",
            ref: "v1.1.0",
            branch: nil
          },
          metadata: { declaration_string: "actions/setup-node@master" }
        }]
      end

      it { is_expected.to eq(expected_requirements) }

      context "and the latest version is being ignored" do
        let(:ignored_versions) { [">= 1.1.0"] }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/setup-node",
              ref: "v1.0.4",
              branch: nil
            },
            metadata: { declaration_string: "actions/setup-node@master" }
          }]
        end

        it { is_expected.to eq(expected_requirements) }
      end
    end

    context "given a dependency with a vulnerable tag reference" do
      let(:upload_pack_fixture) { "ghas-to-csv" }
      let(:dependency_name) { "some-natalie/ghas-to-csv" }
      let(:reference) { "v0.4.0" }

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "github_actions",
            vulnerable_versions: ["< 1.0"]
          )
        ]
      end

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/#{dependency_name}",
            ref: "v1",
            branch: nil
          },
          metadata: { declaration_string: "#{dependency_name}@master" }
        }]
      end

      it { is_expected.to eq(expected_requirements) }
    end

    context "given a vulnerable dependency with a major tag reference" do
      let(:dependency_name) { "kartverket/github-workflows" }
      let(:reference) { "v2" }

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "github_actions",
            vulnerable_versions: ["< 2.7.5"]
          )
        ]
      end

      context "vulnerable because the major tag has not been moved" do
        context "when impossible to keep precision" do
          let(:upload_pack_fixture) { "github-workflows" }

          it "changes precision to avoid the vulnerability" do
            expect(subject.first[:source][:ref]).to eq("v2.7.5")
          end
        end

        context "when possible to keep precision" do
          let(:upload_pack_fixture) { "github-workflows-with-v3" }

          it "bumps to the lowest fixed version that keeps precision" do
            expect(subject.first[:source][:ref]).to eq("v3")
          end
        end
      end
    end

    context "given a non vulnerable dependency with a major tag reference" do
      let(:dependency_name) { "hashicorp/vault-action" }
      let(:reference) { "v2" }

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "github_actions",
            vulnerable_versions: ["< 2.2.0"]
          )
        ]
      end

      let(:upload_pack_fixture) { "vault-action" }

      it "stays on the current major" do
        expect(subject.first[:source][:ref]).to eq("v2")
      end
    end

    context "given a dependency with a tag reference with a major version upgrade available" do
      let(:upload_pack_fixture) { "setup-node-v2" }

      context "using the major version" do
        let(:reference) { "v1" }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/setup-node",
              ref: "v2",
              branch: nil
            },
            metadata: { declaration_string: "actions/setup-node@master" }
          }]
        end

        it { is_expected.to eq(expected_requirements) }
      end

      context "using the major minor version" do
        let(:reference) { "v1.0" }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/setup-node",
              ref: "v2.1",
              branch: nil
            },
            metadata: { declaration_string: "actions/setup-node@master" }
          }]
        end

        it { is_expected.to eq(expected_requirements) }
      end

      context "using the full version" do
        let(:reference) { "v1.0.0" }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/setup-node",
              ref: "v2.1.3",
              branch: nil
            },
            metadata: { declaration_string: "actions/setup-node@master" }
          }]
        end

        it { is_expected.to eq(expected_requirements) }
      end
    end

    context "with multiple requirement sources", :vcr do
      include_context "with multiple git sources"

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@v2.1.0" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.2.0",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@master" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.2.0",
            branch: nil
          }
        }]
      end

      it "returns the expected value" do
        expect(subject).to eq(expected_requirements)
      end
    end
  end
end
