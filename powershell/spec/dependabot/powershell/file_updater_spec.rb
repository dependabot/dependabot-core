# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/powershell/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Powershell::FileUpdater do
  subject(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: []
    )
  end

  let(:psgallery_source) do
    { type: "registry", url: "https://www.powershellgallery.com/api/v2" }
  end

  it_behaves_like "a dependency file updater"

  def build_dependency(name:, requirements:, previous_requirements:, version: nil, previous_version: nil)
    Dependabot::Dependency.new(
      name: name,
      version: version,
      previous_version: previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "powershell"
    )
  end

  def hashtable_requirement(
    requirement_string,
    file:,
    version_key:,
    guid: nil,
    updated_guid: nil,
    maximum_version: nil,
    declaration_type: :required_modules
  )
    metadata = { declaration_type: declaration_type, style: :hashtable, guid: guid, version_key: version_key }
    metadata[:updated_guid] = updated_guid if updated_guid
    metadata[:maximum_version] = maximum_version if maximum_version

    {
      requirement: requirement_string,
      groups: [],
      source: psgallery_source,
      file: file,
      metadata: metadata
    }
  end

  def string_requirement(file:, declaration_type: :required_modules)
    {
      requirement: nil,
      groups: [],
      source: psgallery_source,
      file: file,
      metadata: { declaration_type: declaration_type, style: :string }
    }
  end

  describe "updating a GUID-qualified RequiredVersion" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Guid.ps1",
          content: <<~POWERSHELL
            #Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.0.0'; GUID = '11111111-1111-1111-1111-111111111111' }
          POWERSHELL
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Pester",
          version: "6.0.0",
          previous_version: "5.0.0",
          requirements: [
            hashtable_requirement(
              "= 6.0.0",
              file: "Guid.ps1",
              version_key: "RequiredVersion",
              guid: "11111111-1111-1111-1111-111111111111",
              updated_guid: "22222222-2222-2222-2222-222222222222",
              declaration_type: :requires_directive
            )
          ],
          previous_requirements: [
            hashtable_requirement(
              "= 5.0.0",
              file: "Guid.ps1",
              version_key: "RequiredVersion",
              guid: "11111111-1111-1111-1111-111111111111",
              declaration_type: :requires_directive
            )
          ]
        )
      ]
    end

    it "rewrites both the exact version and GUID" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("RequiredVersion = '6.0.0'")
      expect(content).to include("GUID = '22222222-2222-2222-2222-222222222222'")
    end
  end

  describe "updating a .psd1 module manifest" do
    let(:dependency_files) do
      [Dependabot::DependencyFile.new(name: "MyModule.psd1", content: fixture("psd1", "basic_manifest.psd1"))]
    end

    context "when a RequiredVersion pin (exact version) is bumped" do
      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Compute",
            version: "2.5.0",
            previous_version: "2.3.4",
            requirements: [
              hashtable_requirement(
                "= 2.5.0",
                file: "MyModule.psd1",
                version_key: "RequiredVersion",
                guid: "22222222-2222-2222-2222-222222222222"
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                "= 2.3.4",
                file: "MyModule.psd1",
                version_key: "RequiredVersion",
                guid: "22222222-2222-2222-2222-222222222222"
              )
            ]
          )
        ]
      end

      it "rewrites only the RequiredVersion value" do
        updated = updater.updated_dependency_files
        expect(updated.size).to eq(1)

        content = updated.first.content
        expect(content).to include("RequiredVersion = '2.5.0'")
        expect(content).not_to include("2.3.4")
      end

      it "preserves the GUID and unrelated keys" do
        content = updater.updated_dependency_files.first.content
        expect(content).to include("GUID           = '22222222-2222-2222-2222-222222222222'")
        expect(content).to include("ModuleName     = 'Az.Compute'")
      end
    end

    context "when a normalized RequiredVersion pin is bumped" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "LeadingZero.psd1",
            content: <<~POWERSHELL
              @{
                ModuleVersion = '1.0.0'
                RequiredModules = @(
                  @{ ModuleName = 'Az.Exact'; RequiredVersion = '01.02' }
                )
              }
            POWERSHELL
          )
        ]
      end

      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Exact",
            version: "2.0",
            previous_version: "1.2",
            requirements: [
              hashtable_requirement("= 2.0", file: "LeadingZero.psd1", version_key: "RequiredVersion")
            ],
            previous_requirements: [
              hashtable_requirement("= 1.2", file: "LeadingZero.psd1", version_key: "RequiredVersion")
            ]
          )
        ]
      end

      it "matches and rewrites the original noncanonical literal" do
        content = updater.updated_dependency_files.first.content

        expect(content).to include("RequiredVersion = '2.0'")
        expect(content).not_to include("RequiredVersion = '01.02'")
      end
    end

    context "when a ModuleVersion minimum is bumped" do
      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Storage",
            requirements: [
              hashtable_requirement(">= 2.5.0", file: "MyModule.psd1", version_key: "ModuleVersion")
            ],
            previous_requirements: [
              hashtable_requirement(">= 1.0.0", file: "MyModule.psd1", version_key: "ModuleVersion")
            ]
          )
        ]
      end

      it "rewrites only the ModuleVersion value" do
        content = updater.updated_dependency_files.first.content
        expect(content).to include("@{ ModuleName = 'Az.Storage'; ModuleVersion = '2.5.0' }")
      end
    end

    context "when a ModuleVersion+MaximumVersion range is bumped" do
      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Network",
            requirements: [
              hashtable_requirement(
                ">= 1.0.0, <= 2.5.0",
                file: "MyModule.psd1",
                version_key: "ModuleVersion+MaximumVersion"
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                ">= 1.0.0, <= 2.0.0",
                file: "MyModule.psd1",
                version_key: "ModuleVersion+MaximumVersion"
              )
            ]
          )
        ]
      end

      it "raises only the MaximumVersion, leaving ModuleVersion untouched" do
        content = updater.updated_dependency_files.first.content
        expect(content).to include(
          "@{ ModuleName = 'Az.Network'; ModuleVersion = '1.0.0'; MaximumVersion = '2.5.0' }"
        )
      end
    end

    context "when a wildcard MaximumVersion is exceeded" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "Wildcard.psd1",
            content: <<~POWERSHELL
              @{
                ModuleVersion = '1.0.0'
                RequiredModules = @(
                  @{ ModuleName = 'Az.Wildcard'; MaximumVersion = '5.*' }
                )
              }
            POWERSHELL
          )
        ]
      end

      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Wildcard",
            requirements: [
              hashtable_requirement(
                "<= 6.0.0",
                file: "Wildcard.psd1",
                version_key: "MaximumVersion",
                maximum_version: "5.*"
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                "<= 5.999999999.999999999.999999999",
                file: "Wildcard.psd1",
                version_key: "MaximumVersion",
                maximum_version: "5.*"
              )
            ]
          )
        ]
      end

      it "rewrites the wildcard with the selected version" do
        content = updater.updated_dependency_files.first.content

        expect(content).to include("MaximumVersion = '6.0.0'")
        expect(content).not_to include("MaximumVersion = '5.*'")
      end
    end

    context "when other declarations are unaffected by an update" do
      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Storage",
            requirements: [
              hashtable_requirement(">= 2.5.0", file: "MyModule.psd1", version_key: "ModuleVersion")
            ],
            previous_requirements: [
              hashtable_requirement(">= 1.0.0", file: "MyModule.psd1", version_key: "ModuleVersion")
            ]
          )
        ]
      end

      it "leaves the bare string, path-based and invalid entries untouched" do
        content = updater.updated_dependency_files.first.content
        expect(content).to include("'Az.Accounts',")
        expect(content).to include("'.\\Modules\\LocalModule.psd1',")
        expect(content).to include(
          "@{ ModuleName = 'Az.Invalid'; ModuleVersion = '1.0.0'; RequiredVersion = '2.0.0' }"
        )
      end
    end

    context "when the requirement string is unchanged" do
      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Storage",
            requirements: [
              hashtable_requirement(">= 1.0.0", file: "MyModule.psd1", version_key: "ModuleVersion")
            ],
            previous_requirements: [
              hashtable_requirement(">= 1.0.0", file: "MyModule.psd1", version_key: "ModuleVersion")
            ]
          )
        ]
      end

      it "returns no updated files" do
        expect(updater.updated_dependency_files).to eq([])
      end
    end

    context "when the dependency has no version constraint (bare string style)" do
      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Accounts",
            requirements: [string_requirement(file: "MyModule.psd1")],
            previous_requirements: [string_requirement(file: "MyModule.psd1")]
          )
        ]
      end

      it "returns no updated files, since there's no version to rewrite" do
        expect(updater.updated_dependency_files).to eq([])
      end
    end

    context "when hashtable keys are non-canonical case and values are double-quoted" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "MixedQuotes.psd1",
            content: <<~POWERSHELL
              @{
                ModuleVersion = '1.0.0'
                RequiredModules = @(
                  @{ modulename = "Az.Mixed"; requiredversion = "1.0.0" },
                  @{ ModuleName = "Az.Range"; moduleversion = "1.0.0"; maximumversion = "2.0.0" }
                )
              }
            POWERSHELL
          )
        ]
      end

      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Mixed",
            requirements: [
              hashtable_requirement("= 2.5.0", file: "MixedQuotes.psd1", version_key: "RequiredVersion")
            ],
            previous_requirements: [
              hashtable_requirement("= 1.0.0", file: "MixedQuotes.psd1", version_key: "RequiredVersion")
            ]
          ),
          build_dependency(
            name: "Az.Range",
            requirements: [
              hashtable_requirement(
                ">= 1.0.0, <= 3.0.0",
                file: "MixedQuotes.psd1",
                version_key: "ModuleVersion+MaximumVersion"
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                ">= 1.0.0, <= 2.0.0",
                file: "MixedQuotes.psd1",
                version_key: "ModuleVersion+MaximumVersion"
              )
            ]
          )
        ]
      end

      it "rewrites values case-insensitively while preserving key and quote style" do
        content = updater.updated_dependency_files.first.content

        expect(content).to include('@{ modulename = "Az.Mixed"; requiredversion = "2.5.0" }')
        expect(content).to include('@{ ModuleName = "Az.Range"; moduleversion = "1.0.0"; maximumversion = "3.0.0" }')
      end
    end

    context "when hashtable field names are themselves quoted" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "QuotedKeys.psd1",
            content: <<~POWERSHELL
              @{
                ModuleVersion = '1.0.0'
                RequiredModules = @(
                  @{ 'ModuleName' = 'Az.Quoted'; 'RequiredVersion' = '1.0.0' }
                )
              }
            POWERSHELL
          )
        ]
      end

      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Quoted",
            requirements: [
              hashtable_requirement("= 2.5.0", file: "QuotedKeys.psd1", version_key: "RequiredVersion")
            ],
            previous_requirements: [
              hashtable_requirement("= 1.0.0", file: "QuotedKeys.psd1", version_key: "RequiredVersion")
            ]
          )
        ]
      end

      it "rewrites the value even though its field name is quoted" do
        content = updater.updated_dependency_files.first.content

        expect(content).to include("@{ 'ModuleName' = 'Az.Quoted'; 'RequiredVersion' = '2.5.0' }")
      end
    end
  end

  describe "updating a .ps1 script's #Requires directives" do
    let(:dependency_files) do
      [Dependabot::DependencyFile.new(name: "Deploy.ps1", content: fixture("ps1", "requires_script.ps1"))]
    end

    context "when modules declared on different lines are both bumped" do
      let(:dependencies) do
        [
          build_dependency(
            name: "Az.Storage",
            requirements: [
              hashtable_requirement(
                ">= 9.9.9",
                file: "Deploy.ps1",
                version_key: "ModuleVersion",
                declaration_type: :requires_directive
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                ">= 1.0.0",
                file: "Deploy.ps1",
                version_key: "ModuleVersion",
                declaration_type: :requires_directive
              )
            ]
          ),
          build_dependency(
            name: "Az.Network",
            requirements: [
              hashtable_requirement(
                "= 3.0.0",
                file: "Deploy.ps1",
                version_key: "RequiredVersion",
                declaration_type: :requires_directive
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                "= 2.3.4",
                file: "Deploy.ps1",
                version_key: "RequiredVersion",
                declaration_type: :requires_directive
              )
            ]
          )
        ]
      end

      it "rewrites each #Requires line independently" do
        content = updater.updated_dependency_files.first.content
        expect(content).to include("#Requires -Modules @{ModuleName = 'Az.Storage'; ModuleVersion = '9.9.9'}")
        expect(content).to include(
          "#Requires -Modules Az.Compute, @{ModuleName = 'Az.Network'; RequiredVersion = '3.0.0'}"
        )
      end

      it "leaves the bare string declarations on those same lines untouched" do
        content = updater.updated_dependency_files.first.content
        expect(content).to include("#Requires -Modules Az.Accounts")
        expect(content).to include("Az.Compute,")
      end
    end
  end

  describe "updating a .psm1 script module's #Requires directive" do
    let(:dependency_files) do
      [Dependabot::DependencyFile.new(name: "MyScriptModule.psm1", content: fixture("psm1", "requires_module.psm1"))]
    end

    context "when the ModuleVersion+MaximumVersion range is bumped" do
      let(:dependencies) do
        [
          build_dependency(
            name: "Pester",
            requirements: [
              hashtable_requirement(
                ">= 5.0.0, <= 6.0.0",
                file: "MyScriptModule.psm1",
                version_key: "ModuleVersion+MaximumVersion",
                declaration_type: :requires_directive
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                ">= 5.0.0, <= 5.99.99",
                file: "MyScriptModule.psm1",
                version_key: "ModuleVersion+MaximumVersion",
                declaration_type: :requires_directive
              )
            ]
          )
        ]
      end

      it "raises only the MaximumVersion" do
        content = updater.updated_dependency_files.first.content
        expect(content).to include(
          "#Requires -Modules @{ModuleName = 'Pester'; ModuleVersion = '5.0.0'; MaximumVersion = '6.0.0'}"
        )
      end
    end
  end

  describe "updating using module statements" do
    context "when an exact GUID-qualified module specification is bumped" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "UsingModuleScript.ps1",
            content: fixture("ps1", "using_module_script.ps1")
          )
        ]
      end

      let(:dependencies) do
        [
          build_dependency(
            name: "Pester",
            version: "6.0.1",
            previous_version: "5.0.0",
            requirements: [
              hashtable_requirement(
                "= 6.0.1",
                file: "UsingModuleScript.ps1",
                version_key: "RequiredVersion",
                guid: "11111111-1111-1111-1111-111111111111",
                updated_guid: "a699dea5-2c73-4616-a270-1f7abb777e71",
                declaration_type: :using_module
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                "= 5.0.0",
                file: "UsingModuleScript.ps1",
                version_key: "RequiredVersion",
                guid: "11111111-1111-1111-1111-111111111111",
                declaration_type: :using_module
              )
            ]
          )
        ]
      end

      it "rewrites the version and GUID while preserving the local path" do
        content = updater.updated_dependency_files.first.content

        expect(content).to include("RequiredVersion = '6.0.1'")
        expect(content).to include("GUID = 'a699dea5-2c73-4616-a270-1f7abb777e71'")
        expect(content).to include("using module './LocalTypes.psm1'")
      end
    end

    context "when a bounded module specification is bumped" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "UsingModule.psm1",
            content: fixture("psm1", "using_module.psm1")
          )
        ]
      end

      let(:dependencies) do
        [
          build_dependency(
            name: "Pester",
            requirements: [
              hashtable_requirement(
                ">= 5.0.0, <= 6.0.1",
                file: "UsingModule.psm1",
                version_key: "ModuleVersion+MaximumVersion",
                declaration_type: :using_module
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                ">= 5.0.0, <= 5.99.99",
                file: "UsingModule.psm1",
                version_key: "ModuleVersion+MaximumVersion",
                declaration_type: :using_module
              )
            ]
          )
        ]
      end

      it "raises only the maximum and preserves the bare module name" do
        content = updater.updated_dependency_files.first.content

        expect(content).to include(
          "using module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0'; MaximumVersion = '6.0.1' }"
        )
        expect(content).to include("using module Microsoft.PowerShell.Management")
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

      let(:dependencies) do
        [
          build_dependency(
            name: "Pester",
            version: "6.0.1",
            previous_version: "5.0.0",
            requirements: [
              hashtable_requirement(
                "= 6.0.1",
                file: "UsingModuleVariants.ps1",
                version_key: "RequiredVersion",
                declaration_type: :using_module
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                "= 5.0.0",
                file: "UsingModuleVariants.ps1",
                version_key: "RequiredVersion",
                declaration_type: :using_module
              )
            ]
          ),
          build_dependency(
            name: "PSScriptAnalyzer",
            requirements: [
              hashtable_requirement(
                ">= 1.24.0",
                file: "UsingModuleVariants.ps1",
                version_key: "ModuleVersion",
                declaration_type: :using_module
              )
            ],
            previous_requirements: [
              hashtable_requirement(
                ">= 1.21.0",
                file: "UsingModuleVariants.ps1",
                version_key: "ModuleVersion",
                declaration_type: :using_module
              )
            ]
          )
        ]
      end

      it "updates each versioned statement without changing separators" do
        content = updater.updated_dependency_files.first.content

        expect(content).to include("@{ ModuleName = 'Pester'; RequiredVersion = '6.0.1' }")
        expect(content).to include(
          "using module Microsoft.PowerShell.Management; " \
          "using module @{ ModuleName = 'PSScriptAnalyzer'; ModuleVersion = '1.24.0' }"
        )
      end
    end
  end

  describe "updating versioned external NestedModules" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "NestedModules.psd1",
          content: fixture("psd1", "nested_modules_manifest.psd1")
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Pester",
          version: "6.0.1",
          previous_version: "5.0.0",
          requirements: [
            hashtable_requirement(
              "= 6.0.1",
              file: "NestedModules.psd1",
              version_key: "RequiredVersion",
              declaration_type: :nested_modules
            )
          ],
          previous_requirements: [
            hashtable_requirement(
              "= 5.0.0",
              file: "NestedModules.psd1",
              version_key: "RequiredVersion",
              declaration_type: :nested_modules
            )
          ]
        ),
        build_dependency(
          name: "PSScriptAnalyzer",
          requirements: [
            hashtable_requirement(
              ">= 1.24.0",
              file: "NestedModules.psd1",
              version_key: "ModuleVersion",
              declaration_type: :nested_modules
            )
          ],
          previous_requirements: [
            hashtable_requirement(
              ">= 1.21.0",
              file: "NestedModules.psd1",
              version_key: "ModuleVersion",
              declaration_type: :nested_modules
            )
          ]
        )
      ]
    end

    it "rewrites external versions while preserving every local component" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("@{ ModuleName = 'Pester'; RequiredVersion = '6.0.1' }")
      expect(content).to include("@{ ModuleName = 'PSScriptAnalyzer'; ModuleVersion = '1.24.0' }")
      expect(content).to include("'./LocalNested.psm1'")
      expect(content).to include("'LocalNested.psm1'")
      expect(content).to include("'LocalNested.dll'")
      expect(content).to include("@{ ModuleName = 'LocalVersioned.dll'; ModuleVersion = '1.0.0' }")
    end
  end

  describe "updating multiple declarations of the same module in one file" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Repeated.ps1",
          content: fixture("ps1", "repeated_module_script.ps1")
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Az.Storage",
          requirements: [
            hashtable_requirement(
              ">= 9.0.0",
              file: "Repeated.ps1",
              version_key: "ModuleVersion",
              declaration_type: :requires_directive
            ),
            hashtable_requirement(
              "= 9.0.0",
              file: "Repeated.ps1",
              version_key: "RequiredVersion",
              declaration_type: :requires_directive
            )
          ],
          previous_requirements: [
            hashtable_requirement(
              ">= 1.0.0",
              file: "Repeated.ps1",
              version_key: "ModuleVersion",
              declaration_type: :requires_directive
            ),
            hashtable_requirement(
              "= 2.0.0",
              file: "Repeated.ps1",
              version_key: "RequiredVersion",
              declaration_type: :requires_directive
            )
          ]
        )
      ]
    end

    it "updates each occurrence independently, in declaration order" do
      content = updater.updated_dependency_files.first.content
      lines = content.each_line.map(&:chomp)

      expect(lines[0]).to eq("#Requires -Modules @{ModuleName = 'Az.Storage'; ModuleVersion = '9.0.0'}")
      expect(lines[1]).to eq("#Requires -Modules @{ModuleName = 'Az.Storage'; RequiredVersion = '9.0.0'}")
    end
  end

  describe "updating duplicate identical declarations of the same module" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Duplicate.ps1",
          content: fixture("ps1", "duplicate_requires_script.ps1")
        )
      ]
    end

    # DependencySet dedupes two identical `#Requires` declarations of the
    # same module into a single requirement, even though the locator still
    # finds two occurrences in the file - both must still get rewritten.
    let(:dependencies) do
      [
        build_dependency(
          name: "Az.Storage",
          requirements: [
            hashtable_requirement(
              "= 2.0.0",
              file: "Duplicate.ps1",
              version_key: "RequiredVersion",
              declaration_type: :requires_directive
            )
          ],
          previous_requirements: [
            hashtable_requirement(
              "= 1.0.0",
              file: "Duplicate.ps1",
              version_key: "RequiredVersion",
              declaration_type: :requires_directive
            )
          ]
        )
      ]
    end

    it "rewrites every occurrence, not just the first" do
      content = updater.updated_dependency_files.first.content
      lines = content.each_line.map(&:chomp).reject(&:empty?)

      expect(lines).to eq(
        [
          "#Requires -Modules @{ModuleName = 'Az.Storage'; RequiredVersion = '2.0.0'}",
          "#Requires -Modules @{ModuleName = 'Az.Storage'; RequiredVersion = '2.0.0'}"
        ]
      )
      expect(content).not_to include("1.0.0")
    end
  end

  describe "ignoring declaration-like text inside a block comment" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "WithComment.psd1",
          content: fixture("psd1", "block_comment_manifest.psd1")
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Az.Real",
          requirements: [
            hashtable_requirement(">= 2.0.0", file: "WithComment.psd1", version_key: "ModuleVersion")
          ],
          previous_requirements: [
            hashtable_requirement(">= 1.0.0", file: "WithComment.psd1", version_key: "ModuleVersion")
          ]
        )
      ]
    end

    it "rewrites the real declaration, not the one described in the block comment" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("@{ModuleName = 'Az.Real'; ModuleVersion = '2.0.0'}")
      expect(content).to include("RequiredModules = @('FakeModule')")
    end
  end

  describe "ignoring a RequiredModules mention inside a quoted field value" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "QuotedMention.psd1",
          content: fixture("psd1", "quoted_value_mentions_required_modules.psd1")
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Az.Real",
          requirements: [
            hashtable_requirement(">= 2.0.0", file: "QuotedMention.psd1", version_key: "ModuleVersion")
          ],
          previous_requirements: [
            hashtable_requirement(">= 1.0.0", file: "QuotedMention.psd1", version_key: "ModuleVersion")
          ]
        )
      ]
    end

    it "rewrites the real declaration, leaving the Description and NotRequiredModules mentions untouched" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("@{ModuleName = 'Az.Real'; ModuleVersion = '2.0.0'}")
      expect(content).to include("Description   = 'See RequiredModules = @(''Fake'')")
      expect(content).to include("NotRequiredModules = @('Fake')")
    end
  end

  describe "updating the outer manifest RequiredModules declaration" do
    let(:dependency_files) do
      [
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
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Az.Real",
          requirements: [
            hashtable_requirement(">= 2.0.0", file: "Nested.psd1", version_key: "ModuleVersion")
          ],
          previous_requirements: [
            hashtable_requirement(">= 1.0.0", file: "Nested.psd1", version_key: "ModuleVersion")
          ]
        )
      ]
    end

    it "rewrites only the outer declaration" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("RequiredModules = @('Fake.PrivateModule')")
      expect(content).to include("@{ ModuleName = 'Az.Real'; ModuleVersion = '2.0.0' }")
    end
  end

  describe "updating newline-separated RequiredModules entries" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Separated.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @(
                @{ ModuleName = 'Az.Real'; ModuleVersion = '1.0.0' }
                @{ ModuleName = 'Az.Other'; ModuleVersion = '1.0.0' }
              )
            }
          POWERSHELL
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Az.Real",
          requirements: [
            hashtable_requirement(">= 2.0.0", file: "Separated.psd1", version_key: "ModuleVersion")
          ],
          previous_requirements: [
            hashtable_requirement(">= 1.0.0", file: "Separated.psd1", version_key: "ModuleVersion")
          ]
        )
      ]
    end

    it "rewrites only the matching entry" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("@{ ModuleName = 'Az.Real'; ModuleVersion = '2.0.0' }")
      expect(content).to include("@{ ModuleName = 'Az.Other'; ModuleVersion = '1.0.0' }")
    end
  end

  describe "updating a RequiredModules declaration written as a quoted hashtable key" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "QuotedKey.psd1",
          content: fixture("psd1", "quoted_required_modules_key.psd1")
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Az.Real",
          requirements: [
            hashtable_requirement(">= 2.0.0", file: "QuotedKey.psd1", version_key: "ModuleVersion")
          ],
          previous_requirements: [
            hashtable_requirement(">= 1.0.0", file: "QuotedKey.psd1", version_key: "ModuleVersion")
          ]
        )
      ]
    end

    it "still locates and rewrites the declaration" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("'RequiredModules' = @(")
      expect(content).to include("@{ModuleName = 'Az.Real'; ModuleVersion = '2.0.0'}")
    end
  end

  describe "ignoring declaration-like text inside a here-string" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "WithHereString.ps1",
          content: fixture("ps1", "here_string_requires_script.ps1")
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Az.Real",
          requirements: [
            hashtable_requirement(
              ">= 2.0.0",
              file: "WithHereString.ps1",
              version_key: "ModuleVersion",
              declaration_type: :requires_directive
            )
          ],
          previous_requirements: [
            hashtable_requirement(
              ">= 1.0.0",
              file: "WithHereString.ps1",
              version_key: "ModuleVersion",
              declaration_type: :requires_directive
            )
          ]
        )
      ]
    end

    it "rewrites the real directive, not the one described in the here-string" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("#Requires -Modules @{ModuleName = 'Az.Real'; ModuleVersion = '2.0.0'}")
      expect(content).to include("#Requires -Modules FakeModule.FromHereString")
    end
  end

  describe "updating a single-hashtable RequiredModules declaration" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "SingleHashtable.psd1",
          content: fixture("psd1", "single_hashtable_manifest.psd1")
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Az",
          version: "2.5.0",
          previous_version: "1.0.0",
          requirements: [
            hashtable_requirement(">= 2.5.0", file: "SingleHashtable.psd1", version_key: "ModuleVersion")
          ],
          previous_requirements: [
            hashtable_requirement(">= 1.0.0", file: "SingleHashtable.psd1", version_key: "ModuleVersion")
          ]
        )
      ]
    end

    it "locates and rewrites the version inside the un-parenthesized RequiredModules hashtable" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("RequiredModules = @{ ModuleName = 'Az'; ModuleVersion = '2.5.0' }")
      # The manifest's own top-level ModuleVersion field is untouched.
      expect(content).to include("ModuleVersion = '1.0.0'")
    end
  end

  describe "rewriting a hashtable with a commented-out field preceding the active one" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "CommentedField.psd1",
          content: fixture("psd1", "commented_field_before_active_manifest.psd1")
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Az.Sql",
          version: "2.0.0",
          previous_version: "1.0.0",
          requirements: [
            hashtable_requirement("= 2.0.0", file: "CommentedField.psd1", version_key: "RequiredVersion")
          ],
          previous_requirements: [
            hashtable_requirement("= 1.0.0", file: "CommentedField.psd1", version_key: "RequiredVersion")
          ]
        )
      ]
    end

    it "rewrites the active RequiredVersion field, not the commented-out one" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("# RequiredVersion = '1.0.0'")
      expect(content).to include("RequiredVersion = '2.0.0'")
    end
  end

  describe "rewriting a hashtable with a block-commented field before the active one" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "BlockCommentedField.psd1",
          content: <<~POWERSHELL
            @{
              ModuleVersion = '1.0.0'
              RequiredModules = @{
                ModuleName = 'Pester'
                <# RequiredVersion = '1.0.0' #>
                RequiredVersion = '5.0.0'
              }
            }
          POWERSHELL
        )
      ]
    end

    let(:dependencies) do
      [
        build_dependency(
          name: "Pester",
          version: "6.0.1",
          previous_version: "5.0.0",
          requirements: [
            hashtable_requirement(
              "= 6.0.1",
              file: "BlockCommentedField.psd1",
              version_key: "RequiredVersion"
            )
          ],
          previous_requirements: [
            hashtable_requirement(
              "= 5.0.0",
              file: "BlockCommentedField.psd1",
              version_key: "RequiredVersion"
            )
          ]
        )
      ]
    end

    it "updates the active field and preserves the block comment" do
      content = updater.updated_dependency_files.first.content

      expect(content).to include("<# RequiredVersion = '1.0.0' #>")
      expect(content).to include("RequiredVersion = '6.0.1'")
    end
  end
end
