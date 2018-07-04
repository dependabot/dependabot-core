# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/dotnet/nuget/project_file_parser"

RSpec.describe Dependabot::FileParsers::Dotnet::Nuget::ProjectFileParser do
  let(:file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
  end
  let(:file_body) { fixture("dotnet", "csproj", "basic.csproj") }
  let(:parser) { described_class.new(project_file: file) }

  describe "dependency_set" do
    subject(:dependency_set) { parser.dependency_set }

    it { is_expected.to be_a(Dependabot::FileParsers::Base::DependencySet) }

    describe "the dependencies" do
      subject(:dependencies) { dependency_set.dependencies }

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

      describe "the second dependency" do
        subject(:dependency) { dependencies[1] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.AspNetCore.App")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: nil,
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

      context "with version ranges" do
        let(:file_body) { fixture("dotnet", "csproj", "ranges.csproj") }

        its(:length) { is_expected.to eq(4) }

        it "has the right details" do
          expect(dependencies.first.requirements.first.fetch(:requirement)).
            to eq("[1.0,2.0]")
          expect(dependencies.first.version).to eq("1.0")

          expect(dependencies[1].requirements.first.fetch(:requirement)).
            to eq("[1.1]")
          expect(dependencies[1].version).to eq("1.1")

          expect(dependencies[2].requirements.first.fetch(:requirement)).
            to eq("(,1.0)")
          expect(dependencies[2].version).to be_nil

          expect(dependencies[3].requirements.first.fetch(:requirement)).
            to eq("1.0.*")
          expect(dependencies[3].version).to be_nil
        end
      end
    end
  end
end
