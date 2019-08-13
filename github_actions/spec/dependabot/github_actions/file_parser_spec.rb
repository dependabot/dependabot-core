# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/github_actions/file_parser"
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
  end
end
