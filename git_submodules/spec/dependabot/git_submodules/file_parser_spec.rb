# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/git_submodules/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::GitSubmodules::FileParser do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:gitmodules_body) { fixture("gitmodules", ".gitmodules") }
  let(:relative_submodule) do
    Dependabot::DependencyFile.new(name: "relative/url", content: "sha3")
  end
  let(:about_submodule) do
    Dependabot::DependencyFile.new(name: "about/documents", content: "sha2")
  end
  let(:manifesto_submodule) do
    Dependabot::DependencyFile.new(name: "manifesto", content: "sha1")
  end
  let(:gitmodules) do
    Dependabot::DependencyFile.new(
      name: ".gitmodules",
      content: gitmodules_body
    )
  end
  let(:files) do
    [gitmodules, manifesto_submodule, about_submodule, relative_submodule]
  end

  it_behaves_like "a dependency file parser"

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(3) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("about/documents")
        expect(dependency.version).to eq("sha2")
        expect(dependency.requirements).to eq(
          [{
            requirement: nil,
            file: ".gitmodules",
            source: {
              type: "git",
              url: "git@github.com:example/documents.git",
              branch: "gh-pages",
              ref: "gh-pages"
            },
            groups: []
          }]
        )
      end
    end

    describe "the second dependency" do
      subject(:dependency) { dependencies[1] }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("manifesto")
        expect(dependency.version).to eq("sha1")
        expect(dependency.requirements).to eq(
          [{
            requirement: nil,
            file: ".gitmodules",
            source: {
              type: "git",
              url: "https://github.com/example/manifesto.git",
              branch: nil,
              ref: nil
            },
            groups: []
          }]
        )
      end
    end

    describe "the third dependency" do
      subject(:dependency) { dependencies[2] }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("relative/url")
        expect(dependency.version).to eq("sha3")
        expect(dependency.requirements).to eq(
          [{
            requirement: nil,
            file: ".gitmodules",
            source: {
              type: "git",
              url: "https://github.com/gocardless/such-relative.git",
              branch: nil,
              ref: nil
            },
            groups: []
          }]
        )
      end
    end

    context "with a trailing slash in a path" do
      let(:gitmodules_body) { fixture("gitmodules", "trailing_slash") }

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies }
          .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq(".gitmodules")
          end
      end
    end

    describe "#ecosystem" do
      subject(:ecosystem) { parser.ecosystem }

      it "has the correct name" do
        expect(ecosystem.name).to eq "git_submodules"
      end

      describe "#package_manager" do
        subject(:package_manager) { ecosystem.package_manager }

        it "returns the correct package manager" do
          expect(package_manager.name).to eq "git_submodules"
          expect(package_manager.requirement).to be_nil
          expect(package_manager.version.to_s).to eq "2.34.1"
        end
      end
    end
  end
end
