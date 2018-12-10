# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/dotnet/nuget/"\
        "packages_config_declaration_finder"

namespace = Dependabot::FileUpdaters::Dotnet::Nuget
RSpec.describe namespace::PackagesConfigDeclarationFinder do
  let(:finder) do
    described_class.new(
      dependency_name: dependency_name,
      declaring_requirement: declaring_requirement,
      packages_config: packages_config
    )
  end

  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:declaring_requirement) do
    {
      requirement: declaring_requirement_string,
      file: "packages.config",
      groups: [],
      source: nil
    }
  end
  let(:declaring_requirement_string) { "1.1.1" }
  let(:packages_config) do
    Dependabot::DependencyFile.new(
      name: "packages.config",
      content: fixture("dotnet", "packages_configs", fixture_name)
    )
  end
  let(:fixture_name) { "packages.config" }

  describe "#declaration_strings" do
    subject(:declaration_strings) { finder.declaration_strings }

    context "with a basic packages.config file" do
      let(:fixture_name) { "packages.config" }

      context "and the version as an attribute of a self-closing node" do
        let(:dependency_name) { "NuGet.Core" }
        let(:declaring_requirement_string) { "2.11.1" }

        it "finds the declaration" do
          expect(declaration_strings.count).to eq(1)

          expect(declaration_strings.first).
            to eq('<package id="NuGet.Core" version="2.11.1" '\
                  'targetFramework="net46" />')
        end
      end

      context "and a non-matching version" do
        let(:dependency_name) { "NuGet.Core" }
        let(:declaring_requirement_string) { "2.11.2" }

        it "does not find a declaration" do
          expect(declaration_strings.count).to eq(0)
        end
      end
    end
  end
end
