# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/git/submodules"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Git::Submodules do
  it_behaves_like "a dependency file parser"

  let(:files) { [gitmodules, manifesto_submodule, about_submodule] }
  let(:gitmodules) do
    Dependabot::DependencyFile.new(
      name: ".gitmodules",
      content: gitmodules_body
    )
  end
  let(:manifesto_submodule) do
    Dependabot::DependencyFile.new(name: "manifesto", content: "sha1")
  end
  let(:about_submodule) do
    Dependabot::DependencyFile.new(name: "about/documents", content: "sha2")
  end
  let(:gitmodules_body) do
    fixture("git", "gitmodules", ".gitmodules")
  end
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("about/documents")
        expect(dependency.version).to eq("sha2")
        expect(dependency.requirements).to eq(
          [
            {
              requirement: {
                url: "https://github.com/example/documents.git",
                branch: "gh-pages"
              },
              file: ".gitmodules",
              groups: []
            }
          ]
        )
      end
    end

    describe "the second dependency" do
      subject(:dependency) { dependencies.last }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("custom-name")
        expect(dependency.version).to eq("sha1")
        expect(dependency.requirements).to eq(
          [
            {
              requirement: {
                url: "https://github.com/example/manifesto.git",
                branch: "master"
              },
              file: ".gitmodules",
              groups: []
            }
          ]
        )
      end
    end
  end
end
