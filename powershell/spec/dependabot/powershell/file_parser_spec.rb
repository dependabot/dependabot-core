# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/powershell/file_parser"
require "dependabot/powershell/version"
require "dependabot/powershell/requirement"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Powershell::FileParser do
  subject(:parser) do
    described_class.new(
      dependency_files: dependency_files,
      source: source
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/powershell-project",
      directory: "/"
    )
  end

  let(:psgallery_source) do
    {
      type: "registry",
      url: "https://www.powershellgallery.com/api/v2"
    }
  end

  it_behaves_like "a dependency file parser"

  describe "parsing a .psd1 module manifest" do
    let(:dependency_files) { [manifest_file] }

    let(:manifest_file) do
      Dependabot::DependencyFile.new(
        name: "MyModule.psd1",
        content: fixture("psd1", "basic_manifest.psd1")
      )
    end

    it "parses a bare module name with no version constraint" do
      dependency = parser.parse.find { |dep| dep.name == "Az.Accounts" }

      expect(dependency).not_to be_nil
      expect(dependency.version).to be_nil
      expect(dependency.requirements).to eq(
        [{
          requirement: nil,
          groups: [],
          source: psgallery_source,
          file: "MyModule.psd1",
          metadata: { declaration_type: :required_modules, style: :string }
        }]
      )
    end

    it "parses a hashtable spec with a ModuleVersion as a minimum constraint" do
      dependency = parser.parse.find { |dep| dep.name == "Az.Storage" }

      expect(dependency).not_to be_nil
      expect(dependency.version).to be_nil
      expect(dependency.requirements.first.fetch(:requirement)).to eq(">= 1.0.0")
      expect(dependency.requirements.first.fetch(:metadata)).to eq(
        declaration_type: :required_modules,
        style: :hashtable,
        guid: nil,
        version_key: "ModuleVersion"
      )
    end

    it "parses a hashtable spec with a RequiredVersion as an exact pin" do
      dependency = parser.parse.find { |dep| dep.name == "Az.Compute" }

      expect(dependency).not_to be_nil
      expect(dependency.version).to eq("2.3.4")
      expect(dependency.requirements.first.fetch(:requirement)).to eq("= 2.3.4")
      expect(dependency.requirements.first.fetch(:metadata)).to eq(
        declaration_type: :required_modules,
        style: :hashtable,
        guid: "22222222-2222-2222-2222-222222222222",
        version_key: "RequiredVersion"
      )
    end

    it "parses a hashtable spec with ModuleVersion and MaximumVersion as a bounded range" do
      dependency = parser.parse.find { |dep| dep.name == "Az.Network" }

      expect(dependency).not_to be_nil
      expect(dependency.version).to be_nil
      expect(dependency.requirements.first.fetch(:requirement)).to eq(">= 1.0.0, <= 2.0.0")
      expect(dependency.requirements.first.fetch(:metadata).fetch(:version_key)).to eq("ModuleVersion+MaximumVersion")
    end

    it "excludes path-based RequiredModules entries" do
      names = parser.parse.map(&:name)
      expect(names).not_to include(a_string_matching(/LocalModule/))
    end

    it "excludes entries that combine RequiredVersion with ModuleVersion (invalid)" do
      expect(parser.parse.map(&:name)).not_to include("Az.Invalid")
    end

    it "does not crash and only returns the valid, resolvable dependencies" do
      names = parser.parse.map(&:name)
      expect(names).to contain_exactly("Az.Accounts", "Az.Storage", "Az.Compute", "Az.Network")
    end

    context "when the manifest has no RequiredModules key" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Empty.psd1",
          content: fixture("psd1", "no_required_modules_manifest.psd1")
        )
      end

      it "returns no dependencies" do
        expect(parser.parse).to eq([])
      end
    end

    context "when hashtable keys use mixed casing and mixed quote styles" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "MixedKeys.psd1",
          content: <<~Powershell
            @{
              RequiredModules = @(
                @{ modulename = "Az.Mixed"; requiredversion = "1.2.3" },
                @{ ModuleName = 'Az.Range'; moduleversion = "1.0.0"; maximumversion = '2.0.0' }
              )
            }
          Powershell
        )
      end

      it "parses case-insensitive keys and keeps constraint metadata aligned" do
        mixed = parser.parse.find { |dep| dep.name == "Az.Mixed" }
        range = parser.parse.find { |dep| dep.name == "Az.Range" }

        expect(mixed.requirements.first.fetch(:requirement)).to eq("= 1.2.3")
        expect(mixed.requirements.first.fetch(:metadata).fetch(:version_key)).to eq("RequiredVersion")

        expect(range.requirements.first.fetch(:requirement)).to eq(">= 1.0.0, <= 2.0.0")
        expect(range.requirements.first.fetch(:metadata).fetch(:version_key)).to eq("ModuleVersion+MaximumVersion")
      end
    end

    context "when RequiredModules contains a malformed hashtable entry" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Malformed.psd1",
          content: <<~Powershell
            @{
              RequiredModules = @(
                @{ ModuleName = 'Az.Broken'; RequiredVersion = '1.0.0' } trailing,
                'Az.Valid'
              )
            }
          Powershell
        )
      end

      it "ignores malformed entries and keeps valid ones" do
        expect(parser.parse.map(&:name)).to contain_exactly("Az.Valid")
      end
    end

    context "when RequiredModules has many entries" do
      let(:manifest_file) do
        modules = (1..75).map { |index| "'Module#{index}'" }.join(",\n        ")

        Dependabot::DependencyFile.new(
          name: "ManyModules.psd1",
          content: <<~Powershell
            @{
              RequiredModules = @(
                #{modules}
              )
            }
          Powershell
        )
      end

      it "parses every entry, including tail entries" do
        names = parser.parse.map(&:name)

        expect(names.size).to eq(75)
        expect(names.first).to eq("Module1")
        expect(names.last).to eq("Module75")
      end
    end
  end

  describe "parsing a .ps1 script" do
    let(:dependency_files) { [script_file] }

    let(:script_file) do
      Dependabot::DependencyFile.new(
        name: "Deploy.ps1",
        content: fixture("ps1", "requires_script.ps1")
      )
    end

    it "parses a bare module name from a #Requires -Modules directive" do
      dependency = parser.parse.find { |dep| dep.name == "Az.Accounts" }

      expect(dependency).not_to be_nil
      expect(dependency.requirements).to eq(
        [{
          requirement: nil,
          groups: [],
          source: psgallery_source,
          file: "Deploy.ps1",
          metadata: { declaration_type: :requires_directive, style: :string }
        }]
      )
    end

    it "parses a hashtable module spec from a #Requires -Modules directive" do
      dependency = parser.parse.find { |dep| dep.name == "Az.Storage" }

      expect(dependency).not_to be_nil
      expect(dependency.requirements.first.fetch(:requirement)).to eq(">= 1.0.0")
    end

    it "parses multiple comma-separated modules declared on the same #Requires line" do
      names = parser.parse.map(&:name)

      expect(names).to include("Az.Compute", "Az.Network")
    end

    it "parses a RequiredVersion exact pin declared inline" do
      dependency = parser.parse.find { |dep| dep.name == "Az.Network" }

      expect(dependency).not_to be_nil
      expect(dependency.version).to eq("2.3.4")
      expect(dependency.requirements.first.fetch(:requirement)).to eq("= 2.3.4")
    end

    context "when the script has no #Requires directives" do
      let(:script_file) do
        Dependabot::DependencyFile.new(
          name: "NoRequires.ps1",
          content: fixture("ps1", "no_requires_script.ps1")
        )
      end

      it "returns no dependencies" do
        expect(parser.parse).to eq([])
      end
    end
  end

  describe "parsing a .psm1 script module" do
    let(:dependency_files) { [module_file] }

    let(:module_file) do
      Dependabot::DependencyFile.new(
        name: "MyScriptModule.psm1",
        content: fixture("psm1", "requires_module.psm1")
      )
    end

    it "parses a bounded ModuleVersion/MaximumVersion range from a #Requires directive" do
      dependency = parser.parse.find { |dep| dep.name == "Pester" }

      expect(dependency).not_to be_nil
      expect(dependency.version).to be_nil
      expect(dependency.requirements.first.fetch(:requirement)).to eq(">= 5.0.0, <= 5.99.99")
    end
  end

  describe "parsing multiple files together" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "MyModule.psd1",
          content: fixture("psd1", "basic_manifest.psd1")
        ),
        Dependabot::DependencyFile.new(
          name: "Deploy.ps1",
          content: fixture("ps1", "requires_script.ps1")
        )
      ]
    end

    it "combines dependencies declared across multiple files" do
      az_accounts = parser.parse.find { |dep| dep.name == "Az.Accounts" }

      expect(az_accounts.requirements.map { |r| r[:file] }).to contain_exactly("MyModule.psd1", "Deploy.ps1")
    end
  end
end
