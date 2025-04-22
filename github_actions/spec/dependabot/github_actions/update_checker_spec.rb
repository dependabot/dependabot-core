# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/github_actions/update_checker"
require "dependabot/github_actions/metadata_finder"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::GithubActions::UpdateChecker do
  let(:upload_pack_fixture) { "setup-node" }
  let(:git_commit_checker) do
    Dependabot::GitCommitChecker.new(
      dependency: dependency,
      credentials: github_credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end
  let(:service_pack_url) do
    "https://github.com/#{dependency_name}.git/info/refs" \
      "?service=git-upload-pack"
  end
  let(:reference) { "master" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/#{dependency_name}",
      ref: reference,
      branch: nil
    }
  end
  let(:dependency_version) do
    return unless Dependabot::GithubActions::Version.correct?(reference)

    Dependabot::GithubActions::Version.new(reference).to_s
  end
  let(:dependency_name) { "actions/setup-node" }
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
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
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

  before do
    stub_request(:get, service_pack_url)
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  it_behaves_like "an update checker"

  shared_context "with multiple git sources" do
    let(:upload_pack_fixture) { "checkout" }
    let(:dependency_name) { "actions/checkout" }

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
    subject(:can_update) { checker.can_update?(requirements_to_unlock: :own) }

    context "when given a dependency with a branch reference" do
      let(:reference) { "master" }

      it { is_expected.to be_falsey }
    end

    context "when given a dependency with a tag reference" do
      let(:reference) { "v1.0.1" }

      it { is_expected.to be_truthy }

      context "when is up-to-date" do
        let(:reference) { "v1.1.0" }

        it { is_expected.to be_falsey }
      end

      context "when it is different and up-to-date" do
        let(:upload_pack_fixture) { "checkout" }
        let(:reference) { "v3" }

        it { is_expected.to be_falsey }
      end

      context "when it is not version-like" do
        let(:upload_pack_fixture) { "reactive" }
        let(:reference) { "refassm-blog-post" }

        it { is_expected.to be_falsey }
      end

      context "when a git commit SHA pointing to the tip of a branch not named like a version" do
        let(:upload_pack_fixture) { "setup-node" }
        let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }
        let(:reference) { tip_of_master }

        it { is_expected.to be_falsey }
      end

      context "when a git commit SHA pointing to the tip of a branch named like a version" do
        let(:upload_pack_fixture) { "run-vcpkg" }

        context "when there's a branch named like a higher version" do
          let(:tip_of_v6) { "205a4bde2b6ddf941a102fb50320ea1aa9338233" }

          let(:reference) { tip_of_v6 }

          it { is_expected.to be_truthy }
        end

        context "when there's no branch named like a higher version" do
          let(:tip_of_v10) { "34684effe7451ea95f60397e56ba34c06daced68" }

          let(:reference) { tip_of_v10 }

          it { is_expected.to be_falsey }
        end
      end

      context "when a git commit SHA pointing to the tip of a version tag" do
        let(:upload_pack_fixture) { "setup-node" }
        let(:v1_0_0_tag_sha) { "0d7d2ca66539aca4af6c5102e29a33757e2c2d2c" }
        let(:v1_1_0_tag_sha) { "5273d0df9c603edc4284ac8402cf650b4f1f6686" }

        context "when there's a higher version tag" do
          let(:reference) { v1_0_0_tag_sha }

          it { is_expected.to be_truthy }
        end

        context "when there's no higher version tag" do
          let(:reference) { v1_1_0_tag_sha }

          it { is_expected.to be_falsey }
        end
      end

      context "with a dependency that has a latest requirement and a valid version" do
        let(:dependency_name) { "actions/create-release" }
        let(:upload_pack_fixture) { "create-release" }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
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
          expect(can_update).to be_falsey
        end
      end
    end
  end

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }

    context "when given a dependency has a branch reference" do
      let(:reference) { "master" }

      it { is_expected.to eq(tip_of_master) }
    end

    context "when given a dependency has a tag reference" do
      let(:reference) { "v1.0.1" }

      it { is_expected.to eq(Dependabot::GithubActions::Version.new("1.1.0")) }

      context "when the latest version is being ignored" do
        let(:ignored_versions) { [">= 1.1.0"] }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("1.0.4")) }
      end

      context "when all versions are being ignored" do
        let(:ignored_versions) { [">= 0"] }

        it "returns current version" do
          expect(latest_version).to be_nil
        end

        context "when raise_on_ignored is enabled" do
          let(:raise_on_ignored) { true }

          it "raises an error" do
            expect { latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
          end
        end
      end

      context "when the latest version being also a branch" do
        let(:upload_pack_fixture) { "msbuild" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("1.1.3")) }
      end

      context "when it is a major-only tag of the the latest version" do
        let(:reference) { "v1" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("v1")) }
      end

      context "when it is a major-minor tag of the the latest version" do
        let(:reference) { "v1.1" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("v1.1")) }
      end

      context "when it is a major-minor tag of a previous version" do
        let(:reference) { "v1.0" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("v1.1")) }
      end
    end

    context "when a dependency with a tag reference has a major version upgrade available" do
      let(:upload_pack_fixture) { "setup-node-v2" }

      context "when using the major version" do
        let(:reference) { "v1" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("2")) }
      end

      context "when using the major minor version" do
        let(:reference) { "v1.0" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("2.1")) }
      end

      context "when using the full version" do
        let(:reference) { "v1.0.0" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("2.1.3")) }
      end
    end

    context "when given a repo and the latest major does not point to the latest patch" do
      let(:upload_pack_fixture) { "cache" }

      context "when pinned to patch" do
        let(:reference) { "v2.1.3" }

        it "updates to the latest patch" do
          expect(latest_version).to eq(Dependabot::GithubActions::Version.new("3.0.11"))
        end
      end

      context "when pinned to major" do
        let(:reference) { "v2" }

        it "updates to the latest major" do
          expect(latest_version).to eq(Dependabot::GithubActions::Version.new("3"))
        end
      end
    end

    context "when a dependency that uses branches to track major releases" do
      let(:upload_pack_fixture) { "run-vcpkg" }

      context "when using the major version" do
        let(:reference) { "v7" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("10")) }
      end

      context "when using the minor version" do
        let(:reference) { "v7.0" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("10.5")) }
      end

      context "when using a patch version" do
        let(:reference) { "v7.0.0" }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("10.5")) }
      end
    end

    context "when a dependency has a tag reference and a branch similar to the tag" do
      let(:upload_pack_fixture) { "download-artifact" }
      let(:reference) { "v2" }

      it { is_expected.to eq(Dependabot::GithubActions::Version.new("3")) }
    end

    context "when a git commit SHA pointing to the tip of a branch not named like a version" do
      let(:upload_pack_fixture) { "setup-node" }
      let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }
      let(:reference) { tip_of_master }

      it "considers the commit itself as the latest version" do
        expect(latest_version).to eq(tip_of_master)
      end
    end

    context "when a git commit SHA pointing to the tip of a branch named like a version" do
      let(:upload_pack_fixture) { "run-vcpkg" }

      context "when a branch named like a higher version" do
        let(:tip_of_v6) { "205a4bde2b6ddf941a102fb50320ea1aa9338233" }

        let(:reference) { tip_of_v6 }

        it { is_expected.to eq(Gem::Version.new("10.5")) }
      end

      context "when no branch named like a higher version" do
        let(:tip_of_v10) { "34684effe7451ea95f60397e56ba34c06daced68" }

        let(:reference) { tip_of_v10 }

        it { is_expected.to eq(Gem::Version.new("10.5")) }
      end
    end

    context "when a git commit SHA pointing to the tip of a version tag" do
      let(:upload_pack_fixture) { "setup-node" }
      let(:v1_0_0_tag_sha) { "0d7d2ca66539aca4af6c5102e29a33757e2c2d2c" }
      let(:v1_1_0_tag_sha) { "5273d0df9c603edc4284ac8402cf650b4f1f6686" }

      context "when there's a higher version tag" do
        let(:reference) { v1_0_0_tag_sha }

        it { is_expected.to eq(Gem::Version.new("1.1.0")) }
      end

      context "when there's no higher version tag" do
        let(:reference) { v1_1_0_tag_sha }

        it { is_expected.to eq(Gem::Version.new("1.1.0")) }
      end

      context "when there's a higher version tag and one not matching the existing tag format" do
        let(:upload_pack_fixture) { "codeql" }
        let(:v2_3_6_tag_sha) { "83f0fe6c4988d98a455712a27f0255212bba9bd4" }
        let(:reference) { v2_3_6_tag_sha }

        it { is_expected.to eq(Gem::Version.new("2.3.6")) }
      end
    end

    context "when using a dependency with multiple git refs" do
      include_context "with multiple git sources"

      it "returns the expected value" do
        expect(latest_version).to eq(Gem::Version.new("3.5.2"))
      end
    end

    context "when dealing with a realworld repository" do
      let(:upload_pack_fixture) { "github-action-push-to-another-repository" }
      let(:dependency_name) { "dependabot-fixtures/github-action-push-to-another-repository" }
      let(:dependency_version) { nil }

      let(:latest_commit_in_main) { "9e487f29582587eeb4837c0552c886bb0644b6b9" }
      let(:latest_commit_in_devel) { "c7563454dd4fbe0ea69095188860a62a19658a04" }

      context "when pinned to an up to date commit in the default branch" do
        let(:reference) { latest_commit_in_main }

        it "returns the expected value" do
          expect(latest_version).to eq(latest_commit_in_main)
        end
      end

      context "when pinned to an out of date commit in the default branch" do
        let(:reference) { "f4b9c90516ad3bdcfdc6f4fcf8ba937d0bd40465" }

        it "returns the expected value" do
          expect(latest_version).to eq(latest_commit_in_main)
        end
      end

      context "when pinned to an up to date commit in a non default branch" do
        let(:reference) { latest_commit_in_devel }

        it "returns the expected value" do
          expect(latest_version).to eq(latest_commit_in_devel)
        end
      end

      context "when pinned to an out of date commit in a non default branch" do
        let(:reference) { "96e7dec17bbeed08477b9edab6c3a573614b829d" }

        it "returns the expected value" do
          expect(latest_version).to eq(latest_commit_in_devel)
        end
      end
    end

    context "when a git commit SHA not pointing to the tip of a branch" do
      let(:reference) { "1c24df3" }
      let(:exit_status) { double(success?: true) }

      before do
        checker.instance_variable_set(:@git_commit_checker, git_commit_checker)
        allow(git_commit_checker).to receive_messages(branch_or_ref_in_release?: false,
                                                      head_commit_for_current_branch: reference)

        allow(Dir).to receive(:chdir).and_yield

        allow(Open3).to receive(:capture2e)
          .with(anything, %r{git clone --no-recurse-submodules https://github\.com/actions/setup-node}, anything)
          .and_return(["", exit_status])
      end

      context "when it's in the current (default) branch" do
        before do
          allow(Open3).to receive(:capture2e)
            .with(anything, "git branch --remotes --contains #{reference}", anything)
            .and_return(["  origin/HEAD -> origin/master\n  origin/master", exit_status])
        end

        it "can update to the latest version" do
          expect(latest_version).to eq(tip_of_master)
        end
      end

      context "when it's on a different branch" do
        let(:tip_of_releases_v1) { "5273d0df9c603edc4284ac8402cf650b4f1f6686" }

        before do
          allow(Open3).to receive(:capture2e)
            .with(anything, "git branch --remotes --contains #{reference}", anything)
            .and_return(["  origin/releases/v1\n", exit_status])
        end

        it "can update to the latest version" do
          expect(latest_version).to eq(tip_of_releases_v1)
        end
      end

      context "when multiple branches include it and the current (default) branch among them" do
        before do
          allow(Open3).to receive(:capture2e)
            .with(anything, "git branch --remotes --contains #{reference}", anything)
            .and_return(["  origin/HEAD -> origin/master\n  origin/master\n  origin/v1.1\n", exit_status])
        end

        it "can update to the latest version" do
          expect(latest_version).to eq(tip_of_master)
        end
      end

      context "when multiple branches include it and the current (default) branch NOT among them" do
        before do
          allow(Open3).to receive(:capture2e)
            .with(anything, "git branch --remotes --contains #{reference}", anything)
            .and_return(["  origin/3.3-stable\n  origin/production\n", exit_status])
        end

        it "raises an error" do
          expect { latest_version }
            .to raise_error("Multiple ambiguous branches (3.3-stable, production) include #{reference}!")
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
        expect(lowest_security_fix_version).to eq(Dependabot::GithubActions::Version.new("1.0.0"))
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { ["= 1.0.0"] }

      it "doesn't return ignored versions" do
        expect(lowest_security_fix_version).to eq(Dependabot::GithubActions::Version.new("2.0.0"))
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
        expect(lowest_security_fix_version).to eq(Dependabot::GithubActions::Version.new("2.0.0"))
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lowest_resolvable_security_fix_version) { checker.lowest_resolvable_security_fix_version }

    before do
      allow(checker)
        .to receive(:lowest_security_fix_version)
        .and_return(Dependabot::GithubActions::Version.new("2.0.0"))
    end

    it { is_expected.to eq(Dependabot::GithubActions::Version.new("2.0.0")) }
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    context "when a dependency with a branch reference" do
      let(:reference) { "master" }

      it { is_expected.to eq(dependency.requirements) }
    end

    context "when a git commit SHA pointing to the tip of a branch not named like a version" do
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

    context "when a git commit SHA pointing to the tip of a branch named like a version" do
      let(:upload_pack_fixture) { "run-vcpkg" }
      let(:tip_of_v6) { "205a4bde2b6ddf941a102fb50320ea1aa9338233" }
      let(:tip_of_v10) { "34684effe7451ea95f60397e56ba34c06daced68" }

      context "when it's not the latest version" do
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

      context "when it's also the latest version" do
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

        context "when the latest version is being ignored" do
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

        context "when the previous version is a short SHA" do
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

    context "when a dependency has a tag reference" do
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

      context "when the latest version is being ignored" do
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

    context "when a dependency has a vulnerable tag reference" do
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

    context "when a vulnerable dependency has a major tag reference" do
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

      context "when the major tag has not been moved and is vulnerable" do
        context "when impossible to keep precision" do
          let(:upload_pack_fixture) { "github-workflows" }

          it "changes precision to avoid the vulnerability" do
            expect(updated_requirements.first[:source][:ref]).to eq("v2.7.5")
          end
        end

        context "when possible to keep precision" do
          let(:upload_pack_fixture) { "github-workflows-with-v3" }

          it "bumps to the lowest fixed version that keeps precision" do
            expect(updated_requirements.first[:source][:ref]).to eq("v3")
          end
        end

        context "when no matching tag with a higher version is available" do
          let(:upload_pack_fixture) { "github-workflows-no-tags" }

          it "stays on the vulnerable version" do
            expect(updated_requirements.first[:source][:ref]).to eq(reference)
          end
        end
      end
    end

    context "when a non vulnerable dependency has a major tag reference" do
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
        expect(updated_requirements.first[:source][:ref]).to eq("v2")
      end
    end

    context "when a dependency with a tag reference has a major version upgrade available" do
      let(:upload_pack_fixture) { "setup-node-v2" }

      context "when using the major version" do
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

      context "when using the major minor version" do
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

      context "when using the full version" do
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

    context "with multiple requirement sources" do
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
            ref: "v3.5.2",
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
      end

      it "returns the expected value" do
        expect(updated_requirements).to eq(expected_requirements)
      end
    end

    context "with multiple requirement sources pinned to different versions" do
      let(:dependency_name) { "actions/checkout" }
      let(:upload_pack_fixture) { "checkout" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "actions/checkout",
          version: "2",
          package_manager: "github_actions",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/bump-datadog-ci.yml",
            metadata: { declaration_string: "actions/checkout@v3" },
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "v3",
              branch: nil
            }
          }, {
            requirement: nil,
            groups: [],
            file: ".github/workflows/check-license.yml",
            metadata: { declaration_string: "actions/checkout@v2" },
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "v2",
              branch: nil
            }
          }]
        )
      end

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/bump-datadog-ci.yml",
          metadata: { declaration_string: "actions/checkout@v3" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v3",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/check-license.yml",
          metadata: { declaration_string: "actions/checkout@v2" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v3",
            branch: nil
          }
        }]
      end

      it "updates all source refs to the target ref" do
        expect(updated_requirements).to eq(expected_requirements)
      end
    end

    context "with multiple requirement sources pinned to different SHAs" do
      let(:dependency_name) { "actions/checkout" }
      let(:upload_pack_fixture) { "checkout" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "actions/checkout",
          version: nil,
          package_manager: "github_actions",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            metadata: { declaration_string: "actions/checkout@8e5e7e5ab8b370d6c329ec480221332ada57f0ab" },
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "8e5e7e5ab8b370d6c329ec480221332ada57f0ab",
              branch: nil
            }
          }, {
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            metadata: { declaration_string: "actions/checkout@8f4b7f84864484a7bf31766abe9204da3cbe65b3" },
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "8f4b7f84864484a7bf31766abe9204da3cbe65b3",
              branch: nil
            }
          }]
        )
      end

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@8e5e7e5ab8b370d6c329ec480221332ada57f0ab" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "8e5e7e5ab8b370d6c329ec480221332ada57f0ab",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@8f4b7f84864484a7bf31766abe9204da3cbe65b3" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "8e5e7e5ab8b370d6c329ec480221332ada57f0ab",
            branch: nil
          }
        }]
      end

      it "updates all source refs to the target ref" do
        expect(updated_requirements).to eq(expected_requirements)
      end
    end

    context "when a dependency has a path based tag reference with semver" do
      let(:service_pack_url) do
        "https://github.com/gopidesupavan/monorepo-actions.git/info/refs" \
          "?service=git-upload-pack"
      end
      let(:upload_pack_fixture) { "github-monorepo-path-based" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "gopidesupavan/monorepo-actions/first/run@run/v1.0.0",
          version: "1.0.0",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/gopidesupavan/monorepo-actions",
              ref: "run/v1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "gopidesupavan/monorepo-actions/first/run@run/v1.0.0" }
          }],
          package_manager: "github_actions"
        )
      end
      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/gopidesupavan/monorepo-actions",
            ref: "run/v3.0.0",
            branch: nil
          },
          metadata: { declaration_string: "gopidesupavan/monorepo-actions/first/run@run/v1.0.0" }
        }]
      end

      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "github-monorepo-path-based"),
            headers: {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
          )
      end

      it { is_expected.to eq(expected_requirements) }
    end

    context "when a dependency has a path based tag reference without semver" do
      let(:service_pack_url) do
        "https://github.com/gopidesupavan/monorepo-actions.git/info/refs" \
          "?service=git-upload-pack"
      end
      let(:upload_pack_fixture) { "github-monorepo-path-based" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "gopidesupavan/monorepo-actions/second/exec@exec/1.0.0",
          version: "1.0.0",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/gopidesupavan/monorepo-actions",
              ref: "exec/1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "gopidesupavan/monorepo-actions/second/exec@exec/1.0.0" }
          }],
          package_manager: "github_actions"
        )
      end
      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/gopidesupavan/monorepo-actions",
            ref: "exec/2.0.0",
            branch: nil
          },
          metadata: { declaration_string: "gopidesupavan/monorepo-actions/second/exec@exec/1.0.0" }
        }]
      end

      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "github-monorepo-path-based"),
            headers: {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
          )
      end

      it { is_expected.to eq(expected_requirements) }
    end
  end
end
