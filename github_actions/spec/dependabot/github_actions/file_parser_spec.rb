# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/github_actions/file_parser"
require "dependabot/dependency"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::GithubActions::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [workflow_files] }
  let(:workflow_files) do
    Dependabot::DependencyFile.new(
      name: ".github/workflows/workflow.yml",
      content: workflow_file_body
    )
  end
  let(:workflow_file_body) do
    fixture("workflow_files", workflow_file_fixture_name)
  end
  let(:workflow_file_fixture_name) { "workflow.yml" }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

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
            ref: "master",
            branch: nil
          },
          metadata: { declaration_string: "actions/checkout@master" }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("actions/checkout")
        expect(dependency.version).to be_nil
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    context "with a path" do
      let(:workflow_file_fixture_name) { "workflow_monorepo.yml" }

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
              ref: "master",
              branch: nil
            },
            metadata: { declaration_string: "actions/aws/ec2@master" }
          }, {
            requirement: nil,
            groups: [],
            file: ".github/workflows/workflow.yml",
            source: {
              type: "git",
              url: "https://github.com/actions/aws",
              ref: "master",
              branch: nil
            },
            metadata: { declaration_string: "actions/aws@master" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("actions/aws")
          expect(dependency.version).to be_nil
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
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "master",
            branch: nil
          },
          metadata: { declaration_string: "actions/checkout@master" }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("actions/checkout")
        expect(dependency.version).to eq("2.1.0")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    context "with a bad Ruby object" do
      let(:workflow_file_fixture_name) { "bad_ruby_object.yml" }

      it "raises a helpful error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with a bad reference" do
      let(:workflow_file_fixture_name) { "bad_reference.yml" }

      it "raises a helpful error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotParseable)
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

    context "with a semver tag pinned to a commit" do
      let(:workflow_file_fixture_name) { "pinned_source.yml" }
      let(:service_pack_url) do
        "https://github.com/actions/checkout.git/info/refs" \
          "?service=git-upload-pack"
      end
      before do
        stub_request(:get, service_pack_url).
          to_return(
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
        stub_request(:get, service_pack_url).
          to_return(
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
  end
end
