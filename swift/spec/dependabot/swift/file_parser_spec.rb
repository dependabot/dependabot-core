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
          expect(dependency.requirements).to eq([
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
          ])
        else # subdependency
          expect(dependency.subdependency_metadata).to eq([
            {
              source: source
            }
          ])
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
        expect(package_manager.version.to_s).to eq "6.0.1.pre.dev"
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
        expect(language.version.to_s).to eq "6.0.1"
      end
    end
  end
end
