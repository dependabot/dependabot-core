# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/dotnet/nuget"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Dotnet::Nuget do
  it_behaves_like "a dependency file parser"

  let(:files) { [csproj_file] }
  let(:csproj_file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:csproj_body) { fixture("dotnet", "csproj", "basic.csproj") }
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

    context "for top-level dependencies" do
      its(:length) { is_expected.to eq(3) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Extensions.DependencyModel")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "my.csproj",
              groups: [],
              source: nil
            }]
          )
        end
      end

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.Collections.Specialized")
          expect(dependency.version).to eq("4.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.3.0",
              file: "my.csproj",
              groups: [],
              source: nil
            }]
          )
        end
      end
    end
  end
end
