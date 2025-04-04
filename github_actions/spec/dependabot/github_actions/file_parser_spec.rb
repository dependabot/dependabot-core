# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/github_actions/file_parser"
require "dependabot/dependency"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::GithubActions::FileParser do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:workflow_file_fixture_name) { "workflow.yml" }
  let(:workflow_file_body) do
    fixture("workflow_files", workflow_file_fixture_name)
  end
  let(:workflow_files) do
    Dependabot::DependencyFile.new(
      name: ".github/workflows/workflow.yml",
      content: workflow_file_body
    )
  end
  let(:files) { [workflow_files] }

  it_behaves_like "a dependency file parser"

  def mock_service_pack_request(nwo)
    stub_request(:get, "https://github.com/#{nwo}.git/info/refs?service=git-upload-pack")
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", "checkout"),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    before do
      mock_service_pack_request("actions/checkout")
      mock_service_pack_request("actions/setup-node")
    end

    its(:length) { is_expected.to eq(2) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v1",
            branch: nil
          },
          metadata: { declaration_string: "actions/checkout@v1" }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("actions/checkout")
        expect(dependency.version).to eq("1")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    context "with a path" do
      let(:workflow_file_fixture_name) { "workflow_monorepo.yml" }

      before do
        mock_service_pack_request("actions/aws")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/aws",
              ref: "v1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "actions/aws/ec2@v1.0.0" }
          }, {
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/aws",
              ref: "v1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "actions/aws@v1.0.0" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("actions/aws")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    describe "with multiple sources" do
      subject(:dependency) { dependencies.first }

      let(:workflow_file_fixture_name) { "multiple_sources.yml" }

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.1.0",
            branch: nil
          },
          metadata: { declaration_string: "actions/checkout@v2.1.0" }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("actions/checkout")
        expect(dependency.version).to eq("2.1.0")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    describe "with multiple sources pinned to different refs, and newest ref parsed first" do
      subject(:dependency) { dependencies.first }

      let(:workflow_file_fixture_name) { "newest_ref_parsed_first.yml" }

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "8e5e7e5ab8b370d6c329ec480221332ada57f0ab",
            branch: nil
          },
          metadata: { declaration_string: "actions/checkout@8e5e7e5ab8b370d6c329ec480221332ada57f0ab" }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "8f4b7f84864484a7bf31766abe9204da3cbe65b3",
            branch: nil
          },
          metadata: { declaration_string: "actions/checkout@8f4b7f84864484a7bf31766abe9204da3cbe65b3" }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("actions/checkout")
        expect(dependency.version).to eq("3.5.0")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    describe "with reusable workflow" do
      subject(:dependency) { dependencies.first }

      let(:workflow_file_fixture_name) { "workflow_reusable.yml" }

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.1.0",
            branch: nil
          },
          metadata: { declaration_string: "actions/checkout/.github/workflows/test.yml@v2.1.0" }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("actions/checkout")
        expect(dependency.version).to eq("2.1.0")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    describe "with a local reusable workflow dependency" do
      let(:workflow_file_fixture_name) { "local_workflow.yml" }

      it "does not treat the path like a dependency" do
        expect(dependencies).to eq([])
      end
    end

    describe "with composite actions" do
      let(:workflow_file_fixture_name) { "composite_action.yml" }
      let(:workflow_files) do
        Dependabot::DependencyFile.new(
          name: "action.yml",
          content: workflow_file_body
        )
      end

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: "action.yml",
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v3.3.0",
            branch: nil
          },
          metadata: { declaration_string: "actions/checkout@v3.3.0" }
        }]
      end

      before do
        mock_service_pack_request("docker/setup-qemu-action")
        mock_service_pack_request("docker/setup-buildx-action")
        mock_service_pack_request("docker/login-action")
      end

      its(:length) { is_expected.to eq(4) }

      context "when dealing with the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("actions/checkout")
          expect(dependency.version).to eq("3.3.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    describe "with empty" do
      subject(:dependency) { dependencies.first }

      let(:workflow_file_fixture_name) { "empty.yml" }

      it "has no dependencies" do
        expect(dependencies.count).to be(0)
        expect(dependency).to be_nil
      end
    end

    context "with a bad Ruby object" do
      let(:workflow_file_fixture_name) { "bad_ruby_object.yml" }

      it "raises a helpful error" do
        expect { parser.parse }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with a bad reference" do
      let(:workflow_file_fixture_name) { "bad_reference.yml" }

      it "raises a helpful error" do
        expect { parser.parse }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with a Docker url reference" do
      subject(:dependency) { dependencies.first }

      let(:workflow_file_fixture_name) { "docker_reference.yml" }

      it "ignores the Docker url reference" do
        expect(dependencies.count).to be(0)
        expect(dependency).to be_nil
      end
    end

    context "with actions using inconsistent case" do
      let(:workflow_file_fixture_name) { "inconsistent_case.yml" }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "v1",
              branch: nil
            },
            metadata: {
              declaration_string: "actions/checkout@v1"
            }
          },
           {
             requirement: nil,
             groups: [],
             file: ".github/workflows/workflow.yml",
             source: {
               type: "git",
               url: "https://github.com/actions/checkout",
               ref: "v2",
               branch: nil
             },
             metadata: {
               declaration_string: "Actions/checkout@v2"
             }
           }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("actions/checkout")
          expect(dependency.version).to eq("1")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with actions currently pinned to a branch, but where tags with the same version format are now used" do
      let(:workflow_file_fixture_name) { "pinned_branch.yml" }

      let(:service_pack_url) do
        "https://github.com/swatinem/rust-cache.git/info/refs" \
          "?service=git-upload-pack"
      end

      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "rust-cache"),
            headers: {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
          )
      end

      its(:length) { is_expected.to eq(1) }
    end

    context "with a semver tag pinned to a reusable workflow commit" do
      let(:workflow_file_fixture_name) { "workflow_semver_reusable.yml" }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "01aecccf739ca6ff86c0539fbc67a7a5007bbc81",
              branch: nil
            },
            metadata: {
              declaration_string:
              "actions/checkout/.github/workflows/test.yml@01aecccf739ca6ff86c0539fbc67a7a5007bbc81"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("actions/checkout")
          expect(dependency.version).to eq("2.1.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a semver tag pinned to a commit" do
      let(:workflow_file_fixture_name) { "pinned_source.yml" }
      let(:service_pack_url) do
        "https://github.com/actions/checkout.git/info/refs" \
          "?service=git-upload-pack"
      end

      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "checkout"),
            headers: {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
          )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "01aecccf739ca6ff86c0539fbc67a7a5007bbc81",
              branch: nil
            },
            metadata: { declaration_string: "actions/checkout@01aecccf739ca6ff86c0539fbc67a7a5007bbc81" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("actions/checkout")
          expect(dependency.version).to eq("2.1.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a non-github.com source" do
      let(:workflow_file_fixture_name) { "non_github_source.yml" }
      let(:service_pack_url) do
        "https://ghes.other.com/inactions/checkout.git/info/refs" \
          "?service=git-upload-pack"
      end
      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "gocardless/bump",
          directory: "/",
          hostname: "ghes.other.com",
          api_endpoint: "https://ghes.other.com/api/v3"
        )
      end

      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "checkout"),
            headers: {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
          )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://ghes.other.com/inactions/checkout",
              ref: "01aecccf739ca6ff86c0539fbc67a7a5007bbc81",
              branch: nil
            },
            metadata: { declaration_string: "inactions/checkout@01aecccf739ca6ff86c0539fbc67a7a5007bbc81" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("inactions/checkout")
          expect(dependency.version).to eq("2.1.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with an inaccessible source" do
      let(:workflow_file_fixture_name) { "inaccessible_source.yml" }

      let(:service_pack_url) do
        "https://github.com/inaccessible/source.git/info/refs" \
          "?service=git-upload-pack"
      end

      before do
        stub_request(:get, service_pack_url).to_return(status: 404)
      end

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/inaccessible/source",
              ref: "v1",
              branch: nil
            },
            metadata: { declaration_string: "inaccessible/source@v1" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("inaccessible/source")
          expect(dependency.version).to eq("1")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with path based semver tag pinned to workflow action" do
      let(:workflow_file_fixture_name) { "workflow_monorepo_path_based_semver.yml" }

      let(:service_pack_url) do
        "https://github.com/gopidesupavan/monorepo-actions.git/info/refs" \
          "?service=git-upload-pack"
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

      it "has dependencies" do
        expect(dependencies.count).to be(2)
      end

      describe "the path based first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/gopidesupavan/monorepo-actions",
              ref: "init/v1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "gopidesupavan/monorepo-actions/first/init@init/v1.0.0" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("gopidesupavan/monorepo-actions/first/init@init/v1.0.0")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the path based last dependency" do
        subject(:dependency) { dependencies.last }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/gopidesupavan/monorepo-actions",
              ref: "run/v2.0.0",
              branch: nil
            },
            metadata: { declaration_string: "gopidesupavan/monorepo-actions/first/run@run/v2.0.0" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("gopidesupavan/monorepo-actions/first/run@run/v2.0.0")
          expect(dependency.version).to eq("2.0.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with path based without semver tag pinned to workflow action" do
      let(:workflow_file_fixture_name) { "workflow_monorepo_path_based_without_semver.yml" }

      let(:service_pack_url) do
        "https://github.com/gopidesupavan/monorepo-actions.git/info/refs" \
          "?service=git-upload-pack"
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

      it "has dependencies" do
        expect(dependencies.count).to be(1)
      end

      describe "the path based first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
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
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("gopidesupavan/monorepo-actions/second/exec@exec/1.0.0")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with mix of path based semver tag pinned to workflow action and direct ref" do
      let(:workflow_file_fixture_name) { "workflow_monorepo_path_based_semver_and_direct_ref.yml" }

      let(:service_pack_url) do
        "https://github.com/gopidesupavan/monorepo-actions.git/info/refs" \
          "?service=git-upload-pack"
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
        mock_service_pack_request("actions/checkout")
      end

      it "has dependencies" do
        expect(dependencies.count).to be(3)
      end

      describe "the path based first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/gopidesupavan/monorepo-actions",
              ref: "init/v1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "gopidesupavan/monorepo-actions/first/init@init/v1.0.0" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("gopidesupavan/monorepo-actions/first/init@init/v1.0.0")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the path based last dependency" do
        subject(:dependency) { dependencies.last }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "v1",
              branch: nil
            },
            metadata: { declaration_string: "actions/checkout@v1" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("actions/checkout")
          expect(dependency.version).to eq("1")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with mix of path based without semver tag pinned to workflow action and direct ref" do
      let(:workflow_file_fixture_name) { "workflow_monorepo_path_based_without_semver_and_direct_ref.yml" }

      let(:service_pack_url) do
        "https://github.com/gopidesupavan/monorepo-actions.git/info/refs" \
          "?service=git-upload-pack"
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
        mock_service_pack_request("actions/checkout")
      end

      it "has dependencies" do
        expect(dependencies.count).to be(2)
      end

      describe "the path based first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/gopidesupavan/monorepo-actions",
              ref: "init/1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "gopidesupavan/monorepo-actions/first/init@init/1.0.0" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("gopidesupavan/monorepo-actions/first/init@init/1.0.0")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the path based last dependency" do
        subject(:dependency) { dependencies.last }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "v1",
              branch: nil
            },
            metadata: { declaration_string: "actions/checkout@v1" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("actions/checkout")
          expect(dependency.version).to eq("1")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end
  end

  describe "#ecosystem" do
    it "returns the correct ecosystem" do
      expect(parser.ecosystem).to be_a(Dependabot::Ecosystem)
    end

    it "returns package manager with version" do
      expect(parser.ecosystem.package_manager).to be_a(Dependabot::GithubActions::PackageManager)
      expect(parser.ecosystem.package_manager.version.to_s).to eq("1.0.0")
    end
  end
end
