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

    its(:length) { is_expected.to eq(4) }

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

    context "with a csproj and a vbproj" do
      let(:files) { [csproj_file, vbproj_file] }
      let(:vbproj_file) do
        Dependabot::DependencyFile.new(
          name: "my.vbproj",
          content: fixture("dotnet", "csproj", "basic2.csproj")
        )
      end

      its(:length) { is_expected.to eq(5) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Extensions.DependencyModel")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [
              {
                requirement: "1.1.1",
                file: "my.csproj",
                groups: [],
                source: nil
              },
              {
                requirement: "1.0.1",
                file: "my.vbproj",
                groups: [],
                source: nil
              }
            ]
          )
        end
      end

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Serilog")
          expect(dependency.version).to eq("2.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.3.0",
              file: "my.vbproj",
              groups: [],
              source: nil
            }]
          )
        end
      end
    end

    context "with a packages.config" do
      let(:files) { [packages_config] }
      let(:packages_config) do
        Dependabot::DependencyFile.new(
          name: "packages.config",
          content: fixture("dotnet", "packages_configs", "packages.config")
        )
      end

      its(:length) { is_expected.to eq(9) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("Microsoft.CodeDom.Providers.DotNetCompilerPlatform")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.0",
              file: "packages.config",
              groups: [],
              source: nil
            }]
          )
        end
      end
    end

    context "with an imported properties file" do
      let(:files) { [csproj_file, imported_file] }
      let(:imported_file) do
        Dependabot::DependencyFile.new(
          name: "commonprops.props",
          content: fixture("dotnet", "csproj", "commonprops.props")
        )
      end

      its(:length) { is_expected.to eq(5) }

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Serilog")
          expect(dependency.version).to eq("2.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.3.0",
              file: "commonprops.props",
              groups: [],
              source: nil
            }]
          )
        end
      end
    end
  end
end
