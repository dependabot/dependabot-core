# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/dotnet/nuget/packages_config_parser"

RSpec.describe Dependabot::FileParsers::Dotnet::Nuget::PackagesConfigParser do
  let(:file) do
    Dependabot::DependencyFile.new(name: "packages.config", content: file_body)
  end
  let(:file_body) { fixture("dotnet", "packages_configs", "packages.config") }
  let(:parser) { described_class.new(packages_config: file) }

  describe "dependency_set" do
    subject(:dependency_set) { parser.dependency_set }

    it { is_expected.to be_a(Dependabot::FileParsers::Base::DependencySet) }

    describe "the dependencies" do
      subject(:dependencies) { dependency_set.dependencies }

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
  end
end
