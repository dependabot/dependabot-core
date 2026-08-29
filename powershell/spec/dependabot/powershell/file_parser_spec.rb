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
          source: nil,
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
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ modulename = "Az.Mixed"; requiredversion = "1.2.3" },
                @{ ModuleName = 'Az.Range'; moduleversion = "1.0.0"; maximumversion = '2.0.0' }
              )
            }
          POWERSHELL
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

    context "when PrivateData contains a nested RequiredModules key" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Nested.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              PrivateData = @{
                RequiredModules = @('Fake.PrivateModule')
              }
              RequiredModules = @(
                @{ ModuleName = 'Az.Real'; ModuleVersion = '1.0.0' }
              )
            }
          POWERSHELL
        )
      end

      it "parses only the outer manifest RequiredModules declaration" do
        expect(parser.parse.map(&:name)).to contain_exactly("Az.Real")
      end
    end

    context "when RequiredModules contains a malformed hashtable entry" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Malformed.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ ModuleName = 'Az.Broken'; RequiredVersion = '1.0.0' } trailing,
                'Az.Valid'
              )
            }
          POWERSHELL
        )
      end

      it "ignores malformed entries and keeps valid ones" do
        expect(parser.parse.map(&:name)).to contain_exactly("Az.Valid")
      end
    end

    context "when a hashtable entry has quoted keys" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "QuotedKeys.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ 'ModuleName' = 'Az.Quoted'; "ModuleVersion" = '1.0.0' }
              )
            }
          POWERSHELL
        )
      end

      it "unquotes the keys before canonicalizing them" do
        dependency = parser.parse.find { |dep| dep.name == "Az.Quoted" }

        expect(dependency).not_to be_nil
        expect(dependency.requirements.first.fetch(:requirement)).to eq(">= 1.0.0")
      end
    end

    context "when a hashtable entry has a malformed version field" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "BadVersion.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ ModuleName = 'Az.BadVersion'; ModuleVersion = 'not-a-version' },
                'Az.Valid'
              )
            }
          POWERSHELL
        )
      end

      it "excludes the entry instead of propagating the malformed version" do
        expect(parser.parse.map(&:name)).to contain_exactly("Az.Valid")
      end
    end

    context "when module specification versions use registry SemVer or too many components" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "InvalidNativeVersions.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ ModuleName = 'Az.PrereleaseMinimum'; ModuleVersion = '1.2.0-beta1' },
                @{ ModuleName = 'Az.PrereleaseExact'; RequiredVersion = '1.2.0-beta1' },
                @{ ModuleName = 'Az.PrereleaseMaximum'; MaximumVersion = '1.2.0-beta1' },
                @{ ModuleName = 'Az.FivePartMinimum'; ModuleVersion = '1.2.3.4.5' },
                @{ ModuleName = 'Az.FivePartExact'; RequiredVersion = '1.2.3.4.5' },
                @{ ModuleName = 'Az.FivePartMaximum'; MaximumVersion = '1.2.3.4.5' },
                'Az.Valid'
              )
            }
          POWERSHELL
        )
      end

      it "excludes values that native PowerShell ModuleSpecification rejects" do
        expect(parser.parse.map(&:name)).to contain_exactly("Az.Valid")
      end
    end

    context "when module specification versions contain leading zeroes" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "LeadingZeroVersions.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ ModuleName = 'Az.Minimum'; ModuleVersion = '01.02' },
                @{ ModuleName = 'Az.Exact'; RequiredVersion = '01.02.003' },
                @{ ModuleName = 'Az.Maximum'; MaximumVersion = '01.02.003.0004' }
              )
            }
          POWERSHELL
        )
      end

      it "normalizes each numeric component while preserving component count" do
        dependencies = parser.parse.to_h { |dependency| [dependency.name, dependency] }

        expect(dependencies.fetch("Az.Minimum").requirements.first.fetch(:requirement)).to eq(">= 1.2")
        expect(dependencies.fetch("Az.Exact").version).to eq("1.2.3")
        expect(dependencies.fetch("Az.Exact").requirements.first.fetch(:requirement)).to eq("= 1.2.3")
        expect(dependencies.fetch("Az.Maximum").requirements.first.fetch(:requirement)).to eq("<= 1.2.3.4")
      end
    end

    context "when module specification versions use signed or boundary components" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "BoundaryVersions.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ ModuleName = 'Az.SignedZero'; ModuleVersion = '-0.2' },
                @{ ModuleName = 'Az.LeadingPlus'; RequiredVersion = '+1.2' },
                @{ ModuleName = 'Az.InnerPlus'; MaximumVersion = '1.+2' },
                @{ ModuleName = 'Az.InnerWhitespace'; ModuleVersion = '1 . 2' },
                @{ ModuleName = 'Az.OuterWhitespace'; RequiredVersion = ' 1.2 ' },
                @{ ModuleName = 'Az.MaxInt'; MaximumVersion = '1.2147483647' },
                @{ ModuleName = 'Az.Negative'; ModuleVersion = '-1.2' },
                @{ ModuleName = 'Az.Overflow'; ModuleVersion = '2147483648.0' }
              )
            }
          POWERSHELL
        )
      end

      it "matches native signed, whitespace, and Int32 boundary behavior" do
        dependencies = parser.parse.to_h { |dependency| [dependency.name, dependency] }

        expect(dependencies.keys).to contain_exactly(
          "Az.SignedZero",
          "Az.LeadingPlus",
          "Az.InnerPlus",
          "Az.InnerWhitespace",
          "Az.OuterWhitespace",
          "Az.MaxInt"
        )
        expect(dependencies.fetch("Az.SignedZero").requirements.first.fetch(:requirement)).to eq(">= 0.2")
        expect(dependencies.fetch("Az.LeadingPlus").version).to eq("1.2")
        expect(dependencies.fetch("Az.InnerPlus").requirements.first.fetch(:requirement)).to eq("<= 1.2")
        expect(dependencies.fetch("Az.InnerWhitespace").requirements.first.fetch(:requirement)).to eq(">= 1.2")
        expect(dependencies.fetch("Az.OuterWhitespace").version).to eq("1.2")
        expect(dependencies.fetch("Az.MaxInt").requirements.first.fetch(:requirement)).to eq("<= 1.2147483647")
      end
    end

    context "when a hashtable entry has no version field" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "MissingVersion.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ ModuleName = 'Az.MissingVersion' },
                'Az.Valid'
              )
            }
          POWERSHELL
        )
      end

      it "excludes the malformed module specification" do
        expect(parser.parse.map(&:name)).to contain_exactly("Az.Valid")
      end
    end

    context "when a hashtable entry supplies an empty version field" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "EmptyVersions.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ ModuleName = 'Az.EmptyRequired'; RequiredVersion = '' },
                @{ ModuleName = 'Az.EmptyMinimum'; ModuleVersion = '' },
                @{ ModuleName = 'Az.EmptyMaximum'; MaximumVersion = '' },
                'Az.Valid'
              )
            }
          POWERSHELL
        )
      end

      it "excludes every malformed module specification" do
        expect(parser.parse.map(&:name)).to contain_exactly("Az.Valid")
      end
    end

    context "when MaximumVersion ends in a wildcard" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "WildcardMaximum.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ ModuleName = 'Az.Wildcard'; MaximumVersion = '5.*' }
              )
            }
          POWERSHELL
        )
      end

      it "expands the wildcard for version comparison and preserves its source value" do
        dependency = parser.parse.first

        expect(dependency.requirements.first.fetch(:requirement)).to eq(
          "<= 5.999999999.999999999.999999999"
        )
        expect(dependency.requirements.first.fetch(:metadata)).to include(
          version_key: "MaximumVersion",
          maximum_version: "5.*"
        )
      end
    end

    context "when a data file is not a module manifest" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "ApplicationData.psd1",
          content: <<~POWERSHELL
            @{
              RequiredModules = @(
                @{ ModuleName = 'Not.A.Dependency'; RequiredVersion = '1.0.0' }
              )
            }
          POWERSHELL
        )
      end

      it "does not parse similarly named application data" do
        expect(parser.parse).to eq([])
      end
    end

    context "when RequiredModules has many entries" do
      let(:manifest_file) do
        modules = (1..75).map { |index| "'Module#{index}'" }.join(",\n        ")

        Dependabot::DependencyFile.new(
          name: "ManyModules.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                #{modules}
              )
            }
          POWERSHELL
        )
      end

      it "parses every entry, including tail entries" do
        names = parser.parse.map(&:name)

        expect(names.size).to eq(75)
        expect(names.first).to eq("Module1")
        expect(names.last).to eq("Module75")
      end
    end

    context "when RequiredModules entries are separated by newlines and semicolons" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Separated.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                'Az.First'
                @{ ModuleName = 'Az.Second'; ModuleVersion = '1.0.0' };
                'Az.Third'
              )
            }
          POWERSHELL
        )
      end

      it "parses every top-level entry" do
        expect(parser.parse.map(&:name)).to contain_exactly("Az.First", "Az.Second", "Az.Third")
      end
    end

    context "when RequiredModules is a single bare string" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "SingleString.psd1",
          content: fixture("psd1", "single_string_manifest.psd1")
        )
      end

      it "parses the lone module name" do
        names = parser.parse.map(&:name)
        expect(names).to contain_exactly("Pester")
      end
    end

    context "when RequiredModules is a single hashtable" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "SingleHashtable.psd1",
          content: fixture("psd1", "single_hashtable_manifest.psd1")
        )
      end

      it "parses the lone hashtable spec" do
        dependency = parser.parse.find { |dep| dep.name == "Az" }

        expect(dependency).not_to be_nil
        expect(dependency.requirements.first.fetch(:requirement)).to eq(">= 1.0.0")
        expect(dependency.requirements.first.fetch(:metadata).fetch(:version_key)).to eq("ModuleVersion")
      end
    end

    context "when RequiredModules entries have trailing comments" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Commented.psd1",
          content: fixture("psd1", "commented_manifest.psd1")
        )
      end

      it "strips the comments and parses both entries" do
        names = parser.parse.map(&:name)
        expect(names).to contain_exactly("Az.Accounts", "Az.Storage")
      end

      it "still resolves the hashtable's version constraint" do
        dependency = parser.parse.find { |dep| dep.name == "Az.Storage" }
        expect(dependency.requirements.first.fetch(:requirement)).to eq(">= 1.0.0")
      end
    end

    context "when a RequiredModules example appears inside a block comment" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "BlockComment.psd1",
          content: fixture("psd1", "block_comment_manifest.psd1")
        )
      end

      it "ignores the commented-out example and parses the active assignment" do
        names = parser.parse.map(&:name)
        expect(names).to contain_exactly("Az.Real")
        expect(names).not_to include("FakeModule")
      end
    end

    context "when a commented-out RequiredModules line precedes the active assignment" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "LineComment.psd1",
          content: fixture("psd1", "line_comment_before_required_modules.psd1")
        )
      end

      it "ignores the commented-out line and parses the active assignment" do
        names = parser.parse.map(&:name)
        expect(names).to contain_exactly("Az.Real")
        expect(names).not_to include("OldModule")
      end
    end

    context "when a quoted field value mentions RequiredModules as an example" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "QuotedMention.psd1",
          content: fixture("psd1", "quoted_value_mentions_required_modules.psd1")
        )
      end

      it "ignores the mention inside the quoted Description value and the NotRequiredModules key, " \
         "parsing only the active RequiredModules assignment" do
        names = parser.parse.map(&:name)
        expect(names).to contain_exactly("Az.Real")
        expect(names).not_to include("Fake")
      end
    end

    context "when RequiredModules is written as a quoted hashtable key" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "QuotedKey.psd1",
          content: fixture("psd1", "quoted_required_modules_key.psd1")
        )
      end

      it "still parses the assignment" do
        names = parser.parse.map(&:name)
        expect(names).to contain_exactly("Az.Real")
      end
    end

    context "when NestedModules contains external module specifications and local components" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "NestedModules.psd1",
          content: fixture("psd1", "nested_modules_manifest.psd1")
        )
      end

      it "parses only the versioned external module specifications" do
        expect(parser.parse.map(&:name)).to contain_exactly("Pester", "PSScriptAnalyzer")
      end

      it "preserves NestedModules declaration metadata" do
        pester = parser.parse.find { |dependency| dependency.name == "Pester" }
        analyzer = parser.parse.find { |dependency| dependency.name == "PSScriptAnalyzer" }

        expect(pester.version).to eq("5.0.0")
        expect(pester.requirements.first.fetch(:metadata)).to include(
          declaration_type: :nested_modules,
          version_key: "RequiredVersion"
        )
        expect(analyzer.requirements.first.fetch(:requirement)).to eq(">= 1.21.0")
        expect(analyzer.requirements.first.fetch(:metadata)).to include(
          declaration_type: :nested_modules,
          version_key: "ModuleVersion"
        )
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
          source: nil,
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

    context "when a #Requires -Modules line appears inside a block comment" do
      let(:script_file) do
        Dependabot::DependencyFile.new(
          name: "BlockComment.ps1",
          content: fixture("ps1", "block_comment_requires_script.ps1")
        )
      end

      it "ignores the directive described in the comment and only parses the real one" do
        names = parser.parse.map(&:name)

        expect(names).to contain_exactly("Az.Real")
      end
    end

    context "when a #Requires -Modules line appears inside a here-string" do
      let(:script_file) do
        Dependabot::DependencyFile.new(
          name: "HereString.ps1",
          content: fixture("ps1", "here_string_requires_script.ps1")
        )
      end

      it "ignores the directive described in the here-string and only parses the real one" do
        names = parser.parse.map(&:name)

        expect(names).to contain_exactly("Az.Real")
      end
    end
  end

  describe "parsing using module statements" do
    context "when a script uses an exact module specification and a local path" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "UsingModuleScript.ps1",
            content: fixture("ps1", "using_module_script.ps1")
          )
        ]
      end

      it "parses the multiline external module specification" do
        dependency = parser.parse.find { |candidate| candidate.name == "Pester" }

        expect(dependency.version).to eq("5.0.0")
        expect(dependency.requirements.first.fetch(:requirement)).to eq("= 5.0.0")
        expect(dependency.requirements.first.fetch(:metadata)).to eq(
          declaration_type: :using_module,
          style: :hashtable,
          guid: "11111111-1111-1111-1111-111111111111",
          version_key: "RequiredVersion"
        )
      end

      it "excludes the local module path" do
        expect(parser.parse.map(&:name)).to contain_exactly("Pester")
      end
    end

    context "when a script module uses a range and a bare module name" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "UsingModule.psm1",
            content: fixture("psm1", "using_module.psm1")
          )
        ]
      end

      it "parses both registry-resolvable declarations" do
        expect(parser.parse.map(&:name)).to contain_exactly("Pester", "Microsoft.PowerShell.Management")
      end

      it "parses the bounded module specification" do
        dependency = parser.parse.find { |candidate| candidate.name == "Pester" }

        expect(dependency.requirements.first.fetch(:requirement)).to eq(">= 5.0.0, <= 5.99.99")
        expect(dependency.requirements.first.fetch(:metadata)).to include(
          declaration_type: :using_module,
          version_key: "ModuleVersion+MaximumVersion"
        )
      end
    end

    context "when a multiline string documents a using module statement" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "Documented.ps1",
            content: <<~POWERSHELL
              $description = "Example:
              using module Pester"
            POWERSHELL
          )
        ]
      end

      it "does not parse the documentation as a dependency" do
        expect(parser.parse).to eq([])
      end
    end

    context "when statements use line continuation and semicolon separators" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "UsingModuleVariants.ps1",
            content: fixture("ps1", "using_module_variants.ps1")
          )
        ]
      end

      it "parses every statement independently" do
        expect(parser.parse.map(&:name)).to contain_exactly(
          "Pester",
          "Microsoft.PowerShell.Management",
          "PSScriptAnalyzer"
        )
      end

      it "preserves each versioned statement's requirement" do
        pester = parser.parse.find { |dependency| dependency.name == "Pester" }
        analyzer = parser.parse.find { |dependency| dependency.name == "PSScriptAnalyzer" }

        expect(pester.requirements.first.fetch(:requirement)).to eq("= 5.0.0")
        expect(analyzer.requirements.first.fetch(:requirement)).to eq(">= 1.21.0")
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
