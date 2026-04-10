# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/swift/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Swift::FileParser do
  let(:dependencies) { parser.parse }
  let(:package_resolved_file) do
    Dependabot::DependencyFile.new(
      name: "Package.resolved",
      content: fixture("projects", project_name, "Package.resolved")
    )
  end
  let(:package_manifest_file) do
    Dependabot::DependencyFile.new(
      name: "Package.swift",
      content: fixture("projects", project_name, "Package.swift")
    )
  end
  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
  let(:files) do
    [
      package_manifest_file,
      package_resolved_file
    ]
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/Example",
      directory: "/"
    )
  end
  let(:parser) do
    described_class.new(dependency_files: files, source: source, repo_contents_path: repo_contents_path)
  end

  it_behaves_like "a dependency file parser"

  shared_examples_for "parse" do
    it "parses dependencies fine" do
      expectations.each.with_index do |expected, index|
        url = expected[:url]
        version = expected[:version]
        name = expected[:name]
        identity = expected[:identity]
        source = { type: "git", url: url, ref: version, branch: nil }

        dependency = dependencies[index]

        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq(name)
        expect(dependency.version).to eq(version)
        expect(dependency.metadata).to eq({ identity: identity })

        if expected[:requirement]
          expect(dependency.requirements).to eq(
            [
              {
                requirement: expected[:requirement],
                groups: ["dependencies"],
                file: "Package.swift",
                source: source,
                metadata: {
                  declaration_string: expected[:declaration_string],
                  requirement_string: expected[:requirement_string]
                }
              }
            ]
          )
        else # subdependency
          expect(dependency.subdependency_metadata).to eq(
            [
              {
                source: source
              }
            ]
          )
        end
      end
    end
  end

  context "with supported declarations" do
    let(:project_name) { "Example" }

    let(:expectations) do
      [
        {
          identity: "reactiveswift",
          name: "github.com/reactivecocoa/reactiveswift",
          url: "https://github.com/ReactiveCocoa/ReactiveSwift.git",
          version: "7.1.0",
          requirement: "= 7.1.0",
          declaration_string:
            ".package(url: \"https://github.com/ReactiveCocoa/ReactiveSwift.git\",\n             exact: \"7.1.0\")",
          requirement_string: "exact: \"7.1.0\""
        },
        {
          identity: "swift-docc-plugin",
          name: "github.com/apple/swift-docc-plugin",
          url: "https://github.com/apple/swift-docc-plugin",
          version: "1.0.0",
          requirement: ">= 1.0.0, < 2.0.0",
          declaration_string:
            ".package(\n      url: \"https://github.com/apple/swift-docc-plugin\",\n      from: \"1.0.0\")",
          requirement_string: "from: \"1.0.0\""
        },
        {
          identity: "swift-benchmark",
          name: "github.com/google/swift-benchmark",
          url: "https://github.com/google/swift-benchmark",
          version: "0.1.1",
          requirement: ">= 0.1.0, < 0.1.2",
          declaration_string: ".package(url: \"https://github.com/google/swift-benchmark\", \"0.1.0\"..<\"0.1.2\")",
          requirement_string: "\"0.1.0\"..<\"0.1.2\""
        },
        {
          identity: "swift-argument-parser",
          name: "github.com/apple/swift-argument-parser",
          url: "https://github.com/apple/swift-argument-parser",
          version: "0.5.0",
          requirement: ">= 0.4.0, <= 0.5.0",
          declaration_string:
            ".package(url: \"https://github.com/apple/swift-argument-parser\", \"0.4.0\" ... \"0.5.0\")",
          requirement_string: "\"0.4.0\" ... \"0.5.0\""
        },
        {
          identity: "combine-schedulers",
          name: "github.com/pointfreeco/combine-schedulers",
          url: "https://github.com/pointfreeco/combine-schedulers",
          version: "0.10.0",
          requirement: ">= 0.9.2, <= 0.10.0",
          declaration_string:
            ".package(url: \"https://github.com/pointfreeco/combine-schedulers\", \"0.9.2\"...\"0.10.0\")",
          requirement_string: "\"0.9.2\"...\"0.10.0\""
        },
        {
          identity: "xctest-dynamic-overlay",
          name: "github.com/pointfreeco/xctest-dynamic-overlay",
          url: "https://github.com/pointfreeco/xctest-dynamic-overlay",
          version: "0.8.5"
        }
      ]
    end

    it_behaves_like "parse"
  end

  context "with deprecated declarations" do
    let(:project_name) { "Example-Deprecated" }

    let(:expectations) do
      [
        {
          identity: "quick",
          name: "github.com/quick/quick",
          url: "https://github.com/Quick/Quick.git",
          version: "7.0.2",
          requirement: ">= 7.0.0, < 8.0.0",
          declaration_string:
            ".package(url: \"https://github.com/Quick/Quick.git\",\n             .upToNextMajor(from: \"7.0.0\"))",
          requirement_string: ".upToNextMajor(from: \"7.0.0\")"
        },
        {
          identity: "nimble",
          name: "github.com/quick/nimble",
          url: "https://github.com/Quick/Nimble.git",
          version: "9.0.1",
          requirement: ">= 9.0.0, < 9.1.0",
          declaration_string:
            ".package(url: \"https://github.com/Quick/Nimble.git\",\n             .upToNextMinor(from: \"9.0.0\"))",
          requirement_string: ".upToNextMinor(from: \"9.0.0\")"
        },
        {
          identity: "swift-openapi-runtime",
          name: "github.com/apple/swift-openapi-runtime",
          url: "https://github.com/apple/swift-openapi-runtime",
          version: "0.1.5",
          requirement: ">= 0.1.0, < 0.2.0",
          declaration_string: <<~DECLARATION.strip,
            .package(
                    url: "https://github.com/apple/swift-openapi-runtime",
                    .upToNextMinor(from: "0.1.0")
                )
          DECLARATION
          requirement_string: ".upToNextMinor(from: \"0.1.0\")"
        },
        {
          identity: "swift-docc-plugin",
          name: "github.com/apple/swift-docc-plugin",
          url: "https://github.com/apple/swift-docc-plugin",
          version: "1.0.0",
          requirement: "= 1.0.0",
          declaration_string:
            ".package(\n      url: \"https://github.com/apple/swift-docc-plugin\",\n      .exact(\"1.0.0\"))",
          requirement_string: ".exact(\"1.0.0\")"
        },
        {
          identity: "swift-benchmark",
          name: "github.com/google/swift-benchmark",
          url: "https://github.com/google/swift-benchmark",
          version: "0.1.1",
          requirement: ">= 0.1.0, < 0.1.2",
          declaration_string:
            ".package(name: \"foo\", url: \"https://github.com/google/swift-benchmark\", \"0.1.0\"..<\"0.1.2\")",
          requirement_string: "\"0.1.0\"..<\"0.1.2\""
        },
        {
          identity: "swift-argument-parser",
          name: "github.com/apple/swift-argument-parser",
          url: "https://github.com/apple/swift-argument-parser",
          version: "0.5.0"
        },
        {
          identity: "xctest-dynamic-overlay",
          name: "github.com/pointfreeco/xctest-dynamic-overlay",
          url: "https://github.com/pointfreeco/xctest-dynamic-overlay",
          version: "0.8.5"
        }
      ]
    end

    it_behaves_like "parse"
  end

  context "with SCP-style URIs" do
    let(:project_name) { "scp" }

    let(:expectations) do
      [
        {
          identity: "dummyswiftpackage",
          name: "github.com/marcoeidinger/dummyswiftpackage",
          url: "https://github.com/MarcoEidinger/DummySwiftPackage.git",
          version: "1.0.0",
          requirement: ">= 1.0.0, < 2.0.0",
          declaration_string:
            ".package(url: \"git@github.com:MarcoEidinger/DummySwiftPackage.git\", .upToNextMajor(from: \"1.0.0\"))",
          requirement_string: ".upToNextMajor(from: \"1.0.0\")"
        }
      ]
    end

    it_behaves_like "parse"
  end

  context "with declarations that include multiple spaces after uri" do
    let(:project_name) { "double_space" }

    let(:expectations) do
      [
        {
          identity: "dummyswiftpackage",
          name: "github.com/marcoeidinger/dummyswiftpackage",
          url: "https://github.com/MarcoEidinger/DummySwiftPackage.git",
          version: "1.0.0",
          requirement: ">= 1.0.0, < 2.0.0",
          declaration_string:
            ".package(url:  \"https://github.com/MarcoEidinger/DummySwiftPackage.git\", from: \"1.0.0\")",
          requirement_string: "from: \"1.0.0\""
        }
      ]
    end

    it_behaves_like "parse"
  end

  context "with declarations that end with two parentheses" do
    let(:project_name) { "double_parentheses" }

    let(:expectations) do
      [
        {
          identity: "swift-crypto",
          name: "github.com/apple/swift-crypto",
          url: "https://github.com/apple/swift-crypto.git",
          version: "2.6.0",
          requirement: ">= 1.0.0, < 3.0.0",
          declaration_string: ".package(url: \"https://github.com/apple/swift-crypto.git\", \"1.0.0\"..<\"3.0.0\")",
          requirement_string: "\"1.0.0\"..<\"3.0.0\""
        }
      ]
    end

    it_behaves_like "parse"
  end

  context "with dependency using trait specification" do
    let(:project_name) { "dependency_with_trait" }

    let(:expectations) do
      [
        {
          identity: "swift-otel",
          name: "github.com/swift-otel/swift-otel",
          url: "https://github.com/swift-otel/swift-otel.git",
          version: "1.0.3",
          requirement: ">= 1.0.0, < 2.0.0",
          declaration_string:
            ".package(url: \"https://github.com/swift-otel/swift-otel.git\", from: \"1.0.0\", traits: [\"OTLPHTTP\"])",
          requirement_string: "from: \"1.0.0\""
        }
      ]
    end

    it_behaves_like "parse"
  end

  describe "#ecosystem" do
    subject(:ecosystem) { parser.ecosystem }

    let(:project_name) { "Example" }

    it "has the correct name" do
      expect(ecosystem.name).to eq "swift"
    end

    describe "#package_manager" do
      subject(:package_manager) { ecosystem.package_manager }

      it "returns the correct package manager" do
        expect(package_manager.name).to eq "swift"
        expect(package_manager.requirement).to be_nil
        expect(package_manager.version.to_s).to eq "6.2.3"
      end
    end

    describe "#package_manager_version" do
      # If this test starts failing, the format of the output of `swing package --version` has
      # changed and you'll need to update the code to extract the version correctly.
      subject(:package_manager_version) { parser.send(:package_manager_version) }

      it "has the correct format" do
        expect(package_manager_version.match(/^\d+(?:\.\d+)*/)).to be_truthy
      end
    end

    describe "#swift_version" do
      # If this test starts failing, the format of the output of `swing --version` has
      # changed and you'll need to update the code to extract the version correctly.
      subject(:swift_version) { parser.send(:swift_version) }

      it "has the correct format" do
        expect(swift_version.match(/^\d+(?:\.\d+)*$/)).to be_truthy
      end
    end

    describe "#language" do
      subject(:language) { ecosystem.language }

      it "returns the correct language" do
        expect(language.name).to eq "swift"
        expect(language.requirement).to be_nil
        expect(language.version.to_s).to eq "6.2.3"
      end
    end
  end

  context "when enable_swift_xcode_spm experiment is enabled" do
    before { Dependabot::Experiments.register(:enable_swift_xcode_spm, true) }
    after { Dependabot::Experiments.register(:enable_swift_xcode_spm, false) }

    context "with a single Xcode project (v2 Package.resolved)" do
      let(:project_name) { "xcode_project" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "parses Xcode SPM dependencies" do
        deps = parser.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
        expect(dep.package_manager).to eq("swift")
      end

      it "enriches dependencies with pbxproj requirements" do
        dep = parser.parse.first
        req = dep.requirements.first

        expect(req[:requirement]).to eq(">= 2.54.0, < 3.0.0")
        expect(req[:file]).to eq("MyApp.xcodeproj/project.pbxproj")
        expect(req[:metadata][:requirement_string]).to eq("from: \"2.54.0\"")
      end

      it "sets correct source info" do
        dep = parser.parse.first
        source = dep.requirements.first[:source]

        expect(source[:type]).to eq("git")
        expect(source[:url]).to eq("https://github.com/apple/swift-nio.git")
        expect(source[:ref]).to eq("2.54.0")
      end
    end

    context "with v1 Package.resolved" do
      let(:project_name) { "xcode_project_v1_resolved" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "parses v1 format dependencies" do
        deps = parser.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
      end
    end

    context "with v3 Package.resolved" do
      let(:project_name) { "xcode_project_v3_resolved" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "parses v3 format dependencies" do
        deps = parser.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
      end
    end

    context "with multiple dependencies and requirement types" do
      let(:project_name) { "xcode_project_multi_req" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "parses all dependencies" do
        deps = parser.parse
        expect(deps.length).to eq(4)

        names = deps.map(&:name)
        expect(names).to contain_exactly(
          "github.com/apple/swift-nio",
          "github.com/apple/swift-collections",
          "github.com/apple/swift-argument-parser",
          "github.com/apple/swift-log"
        )
      end

      it "applies correct requirement types from pbxproj" do
        deps = parser.parse
        nio = deps.find { |d| d.name == "github.com/apple/swift-nio" }
        collections = deps.find { |d| d.name == "github.com/apple/swift-collections" }
        parser_dep = deps.find { |d| d.name == "github.com/apple/swift-argument-parser" }
        log = deps.find { |d| d.name == "github.com/apple/swift-log" }

        expect(nio.requirements.first[:requirement]).to eq(">= 2.54.0, < 3.0.0")
        expect(collections.requirements.first[:requirement]).to eq(">= 1.0.0, < 1.1.0")
        expect(parser_dep.requirements.first[:requirement]).to eq("= 1.2.0")
        expect(log.requirements.first[:requirement]).to eq(">= 1.4.0, < 2.0.0")
      end
    end

    context "with multiple .xcodeproj directories" do
      let(:project_name) { "xcode_project_multiple" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "AppA.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "AppA.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "AppA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "AppA.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          ),
          Dependabot::DependencyFile.new(
            name: "AppB.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "AppB.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "AppB.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "AppB.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "parses dependencies from all resolved files" do
        deps = parser.parse
        names = deps.map(&:name)

        expect(names).to include("github.com/apple/swift-nio")
        expect(names).to include("github.com/apple/swift-collections")
      end

      it "associates requirements with correct pbxproj files" do
        deps = parser.parse
        nio_dep = deps.find { |d| d.name == "github.com/apple/swift-nio" }
        collections_dep = deps.find { |d| d.name == "github.com/apple/swift-collections" }

        # With scoped requirements, swift-nio comes from AppA and swift-collections from AppB
        expect(nio_dep.requirements.first[:file]).to eq("AppA.xcodeproj/project.pbxproj")
        expect(collections_dep.requirements.first[:file]).to eq("AppB.xcodeproj/project.pbxproj")
      end
    end

    context "with revision-only pin (no version)" do
      let(:project_name) { "xcode_project_revision_only" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "parses with nil version" do
        dep = parser.parse.first
        expect(dep.version).to be_nil
      end

      it "records revision in source ref" do
        dep = parser.parse.first
        source = dep.requirements.first[:source]
        expect(source[:ref]).to eq("6213ba7a06febe8fef60563a4a7d26a4085783cf")
      end
    end

    context "with no pbxproj file (only Package.resolved)" do
      let(:project_name) { "xcode_project" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "parses dependencies without requirement enrichment" do
        deps = parser.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
        # Without pbxproj, requirement comes from Package.resolved only
        expect(dep.requirements.first[:requirement]).to eq("= 2.54.0")
      end
    end

    context "with invalid JSON in Package.resolved" do
      let(:project_name) { "xcode_project_invalid_json" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "raises DependencyFileNotParseable" do
        expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with unknown schema version" do
      let(:project_name) { "xcode_project_unknown_schema" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "raises DependencyFileNotParseable with schema info" do
        expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.message).to include("unsupported schema version")
        end
      end
    end

    context "with empty pins" do
      let(:project_name) { "xcode_project_empty_pins" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "returns an empty dependency list" do
        expect(parser.parse).to be_empty
      end
    end

    context "with both Package.swift and .xcodeproj present" do
      let(:project_name) { "xcode_project_with_manifest" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Package.swift",
            content: fixture("projects", project_name, "Package.swift")
          ),
          Dependabot::DependencyFile.new(
            name: "Package.resolved",
            content: fixture("projects", project_name, "Package.resolved")
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "uses classic SPM path (Package.swift takes precedence)" do
        deps = parser.parse
        # Classic SPM parses via swift CLI, so requirements come from Package.swift
        dep = deps.find { |d| d.name == "github.com/apple/swift-nio" }
        expect(dep).not_to be_nil
        expect(dep.requirements.first[:file]).to eq("Package.swift")
      end
    end
  end

  context "when enable_swift_xcode_spm experiment is disabled" do
    before { Dependabot::Experiments.register(:enable_swift_xcode_spm, false) }

    context "with only Xcode files (no Package.swift)" do
      let(:project_name) { "xcode_project" }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

      it "raises an error about missing Package.swift" do
        expect { parser }.to raise_error("No Package.swift!")
      end
    end
  end
end
