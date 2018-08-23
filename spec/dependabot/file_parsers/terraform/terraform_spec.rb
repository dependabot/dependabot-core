# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/terraform/terraform"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Terraform::Terraform do
  it_behaves_like "a dependency file parser"

  let(:files) { [terraform_file] }
  let(:terraform_file) do
    Dependabot::DependencyFile.new(name: "main.tf", content: terraform_body)
  end
  let(:terraform_body) do
    fixture("terraform", "config_files", terraform_fixture_name)
  end
  let(:terraform_fixture_name) { "git_tags.tf" }
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

    its(:length) { is_expected.to eq(4) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }
      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-null-label.git"\
                 "?ref=tags/0.3.7"
          }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("origin_label")
        expect(dependency.version).to be_nil
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end
  end
end
