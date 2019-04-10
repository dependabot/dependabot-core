# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/file_updater/project_file_declaration_finder"

namespace = Dependabot::Nuget::FileUpdater
RSpec.describe namespace::ProjectFileDeclarationFinder do
  let(:finder) do
    described_class.new(
      dependency_name: dependency_name,
      declaring_requirement: declaring_requirement,
      dependency_files: dependency_files
    )
  end

  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:declaring_requirement) do
    {
      requirement: declaring_requirement_string,
      file: "my.csproj",
      groups: [],
      source: nil
    }
  end
  let(:declaring_requirement_string) { "1.1.1" }
  let(:dependency_files) { [csproj] }
  let(:csproj) do
    Dependabot::DependencyFile.new(
      name: "my.csproj",
      content: fixture("csproj", csproj_fixture_name)
    )
  end
  let(:csproj_fixture_name) { "basic.csproj" }

  describe "#declaration_strings" do
    subject(:declaration_strings) { finder.declaration_strings }

    context "with a basic csproj file (no properties)" do
      let(:csproj_fixture_name) { "basic.csproj" }

      context "and the version as an attribute of a self-closing node" do
        let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
        let(:declaring_requirement_string) { "1.1.1" }

        it "finds the declaration" do
          expect(declaration_strings.count).to eq(1)

          expect(declaration_strings.first).
            to eq('<PackageReference Include="Microsoft.Extensions.'\
                  'DependencyModel" Version="1.1.1" />')
        end

        context "with a difference in capitalization" do
          let(:dependency_name) { "Microsoft.Extensions.dependencymodel" }

          it "finds the declaration" do
            expect(declaration_strings.count).to eq(1)

            expect(declaration_strings.first).
              to eq('<PackageReference Include="Microsoft.Extensions.'\
                    'DependencyModel" Version="1.1.1" />')
          end
        end
      end

      context "and the version as an attribute of a normal node" do
        let(:dependency_name) { "Microsoft.Extensions.PlatformAbstractions" }
        let(:declaring_requirement_string) { "1.1.0" }

        it "finds the declaration" do
          expect(declaration_strings.count).to eq(1)

          expect(declaration_strings.first).
            to eq('<PackageReference Include="Microsoft.Extensions.'\
                  'PlatformAbstractions" Version="1.1.0"></PackageReference>')
        end
      end

      context "and the version as a child node" do
        let(:dependency_name) { "System.Collections.Specialized" }
        let(:declaring_requirement_string) { "4.3.0" }

        it "finds the declaration" do
          expect(declaration_strings.count).to eq(1)

          expect(declaration_strings.first).
            to eq('<PackageReference Include="System.Collections.Specialized">'\
                  "<Version>4.3.0</Version></PackageReference>")
        end
      end

      context "and a non-matching version" do
        let(:dependency_name) { "System.Collections.Specialized" }
        let(:declaring_requirement_string) { "4.3.1" }

        it "does not find a declaration" do
          expect(declaration_strings.count).to eq(0)
        end
      end
    end

    context "with a nuproj file" do
      let(:csproj_fixture_name) { "basic.nuproj" }

      context "and the version as a child node" do
        let(:dependency_name) { "nanoFramework.CoreLibrary" }
        let(:declaring_requirement_string) { "[1.0.0-preview062]" }

        it "finds the declaration" do
          expect(declaration_strings.count).to eq(1)

          expect(declaration_strings.first).
            to eq('<Dependency Include="nanoFramework.CoreLibrary">'\
                  "\n      <Version>[1.0.0-preview062]</Version>"\
                  "\n    </Dependency>")
        end
      end
    end
  end
end
