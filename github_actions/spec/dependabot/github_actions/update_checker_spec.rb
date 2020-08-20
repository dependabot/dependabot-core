# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/github_actions/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::GithubActions::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: github_credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: nil,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        source: dependency_source,
        metadata: { declaration_string: "actions/setup-node@master" }
      }],
      package_manager: "github_actions"
    )
  end
  let(:dependency_name) { "actions/setup-node" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/actions/setup-node",
      ref: reference,
      branch: nil
    }
  end
  let(:reference) { "master" }
  let(:service_pack_url) do
    "https://github.com/actions/setup-node.git/info/refs"\
    "?service=git-upload-pack"
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
        let(:reference) { "v1" }
        it { is_expected.to be_falsey }
      end

      context "that is not version-like" do
        let(:upload_pack_fixture) { "reactive" }
        let(:reference) { "refassm-blog-post" }
        it { is_expected.to be_falsey }
      end

      context "that is a git commit SHA" do
        let(:upload_pack_fixture) { "setup-node" }
        let(:reference) { "1c24df3" }

        let(:repo_url) { "https://api.github.com/repos/actions/setup-node" }
        let(:comparison_url) { repo_url + "/compare/v1.1.0...1c24df3" }
        before do
          stub_request(:get, comparison_url).
            to_return(
              status: 200,
              body: comparison_response,
              headers: { "Content-Type" => "application/json" }
            )
        end

        context "when the specified reference is not in the latest release" do
          let(:comparison_response) do
            fixture("github", "commit_compare_diverged.json")
          end
          it { is_expected.to be_falsey }
        end

        context "when the specified ref is included in the latest release" do
          let(:comparison_response) do
            fixture("github", "commit_compare_behind.json")
          end
          it { is_expected.to be_truthy }
        end
      end
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    context "given a dependency with a branch reference" do
      let(:reference) { "master" }
      it { is_expected.to eq("d963e800e3592dd31d6c76252092562d0bc7a3ba") }
    end

    context "given a dependency with a tag reference" do
      let(:reference) { "v1.0.1" }
      it { is_expected.to eq("5273d0df9c603edc4284ac8402cf650b4f1f6686") }

      context "and the latest version is being ignored" do
        let(:ignored_versions) { [">= 1.1.0"] }
        it { is_expected.to eq("fc9ff49b90869a686df00e922af871c12215986a") }
      end

      context "and all versions are being ignored" do
        let(:ignored_versions) { [">= 0"] }
        it "returns nil" do
          expect(subject).to be_nil
        end

        context "raise_on_ignored" do
          let(:raise_on_ignored) { true }
          it "raises an error" do
            expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
          end
        end
      end
    end

    context "given a git commit SHA" do
      let(:reference) { "1c24df3" }

      let(:repo_url) { "https://api.github.com/repos/actions/setup-node" }
      let(:comparison_url) { repo_url + "/compare/v1.1.0...1c24df3" }
      before do
        stub_request(:get, comparison_url).
          to_return(
            status: 200,
            body: comparison_response,
            headers: { "Content-Type" => "application/json" }
          )
      end

      context "when the specified reference is not in the latest release" do
        let(:comparison_response) do
          fixture("github", "commit_compare_diverged.json")
        end
        it { is_expected.to be_nil }
      end

      context "when the specified ref is included in the latest release" do
        let(:comparison_response) do
          fixture("github", "commit_compare_behind.json")
        end
        it { is_expected.to eq(Gem::Version.new("1.1.0")) }

        context "and the latest version is being ignored" do
          let(:ignored_versions) { [">= 1.1.0"] }
          let(:comparison_url) { repo_url + "/compare/v1.0.4...1c24df3" }
          it { is_expected.to eq(Gem::Version.new("1.0.4")) }
        end
      end
    end

    context "given a dependency with multiple git refs", :vcr do
      include_context "with multiple git sources"

      it { is_expected.to eq("aabbfeb2ce60b5bd82389903509092c4648a9713") }
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    before { allow(checker).to receive(:latest_version).and_return("delegate") }
    it { is_expected.to eq("delegate") }
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }

    context "given a dependency with a branch reference" do
      let(:reference) { "master" }
      it { is_expected.to eq(dependency.requirements) }
    end

    context "given a git commit SHA" do
      let(:reference) { "1c24df3" }

      let(:repo_url) { "https://api.github.com/repos/actions/setup-node" }
      let(:comparison_url) { repo_url + "/compare/v1.1.0...1c24df3" }
      before do
        stub_request(:get, comparison_url).
          to_return(
            status: 200,
            body: comparison_response,
            headers: { "Content-Type" => "application/json" }
          )
      end

      context "when the specified reference is not in the latest release" do
        let(:comparison_response) do
          fixture("github", "commit_compare_diverged.json")
        end
        it { is_expected.to eq(dependency.requirements) }
      end

      context "when the specified ref is included in the latest release" do
        let(:comparison_response) do
          fixture("github", "commit_compare_behind.json")
        end
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
          let(:comparison_url) { repo_url + "/compare/v1.0.4...1c24df3" }
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

      it { is_expected.to eq(expected_requirements) }
    end
  end
end
