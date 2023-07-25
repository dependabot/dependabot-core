# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/swift/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Swift::FileParser do
  it_behaves_like "a dependency file parser"

  let(:parser) do
    described_class.new(dependency_files: files, source: source, repo_contents_path: repo_contents_path)
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/Example",
      directory: "/"
    )
  end

  let(:files) do
    [
      package_manifest_file,
      package_resolved_file
    ]
  end

  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

  let(:package_manifest_file) do
    Dependabot::DependencyFile.new(
      name: "Package.swift",
      content: fixture("projects", project_name, "Package.swift")
    )
  end

  let(:package_resolved_file) do
    Dependabot::DependencyFile.new(
      name: "Package.resolved",
      content: fixture("projects", project_name, "Package.resolved")
    )
  end

  let(:dependencies) { parser.parse }

  shared_examples_for "parse" do
    it "parses dependencies fine" do
      expectations.each.with_index do |expected, index|
        url = expected[:url]
        version = expected[:version]
        name = expected[:name]
        source = { type: "git", url: url, ref: version, branch: nil }

        dependency = dependencies[index]

        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq(name)
        expect(dependency.version).to eq(version)

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
          name: "reactiveswift",
          url: "https://github.com/ReactiveCocoa/ReactiveSwift.git",
          version: "7.1.0",
          requirement: "= 7.1.0",
          declaration_string:
            ".package(url: \"https://github.com/ReactiveCocoa/ReactiveSwift.git\",\n             exact: \"7.1.0\")",
          requirement_string: "exact: \"7.1.0\""
        },
        {
          name: "swift-docc-plugin",
          url: "https://github.com/apple/swift-docc-plugin",
          version: "1.0.0",
          requirement: ">= 1.0.0, < 2.0.0",
          declaration_string:
            ".package(\n      url: \"https://github.com/apple/swift-docc-plugin\",\n      from: \"1.0.0\")",
          requirement_string: "from: \"1.0.0\""
        },
        {
          name: "swift-benchmark",
          url: "https://github.com/google/swift-benchmark",
          version: "0.1.1",
          requirement: ">= 0.1.0, < 0.1.2",
          declaration_string: ".package(url: \"https://github.com/google/swift-benchmark\", \"0.1.0\"..<\"0.1.2\")",
          requirement_string: "\"0.1.0\"..<\"0.1.2\""
        },
        {
          name: "swift-argument-parser",
          url: "https://github.com/apple/swift-argument-parser",
          version: "0.5.0"
        },
        {
          name: "combine-schedulers",
          url: "https://github.com/pointfreeco/combine-schedulers",
          version: "0.10.0",
          requirement: ">= 0.9.2, <= 0.10.0",
          declaration_string:
            ".package(url: \"https://github.com/pointfreeco/combine-schedulers\", \"0.9.2\"...\"0.10.0\")",
          requirement_string: "\"0.9.2\"...\"0.10.0\""
        },
        {
          name: "xctest-dynamic-overlay",
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
          name: "quick",
          url: "https://github.com/Quick/Quick.git",
          version: "7.0.2",
          requirement: ">= 7.0.0, < 8.0.0",
          declaration_string:
            ".package(url: \"https://github.com/Quick/Quick.git\",\n             .upToNextMajor(from: \"7.0.0\"))",
          requirement_string: ".upToNextMajor(from: \"7.0.0\")"
        },
        {
          name: "nimble",
          url: "https://github.com/Quick/Nimble.git",
          version: "9.0.1",
          requirement: ">= 9.0.0, < 9.1.0",
          declaration_string:
            ".package(url: \"https://github.com/Quick/Nimble.git\",\n             .upToNextMinor(from: \"9.0.0\"))",
          requirement_string: ".upToNextMinor(from: \"9.0.0\")"
        },
        {
          name: "swift-docc-plugin",
          url: "https://github.com/apple/swift-docc-plugin",
          version: "1.0.0",
          requirement: "= 1.0.0",
          declaration_string:
            ".package(\n      url: \"https://github.com/apple/swift-docc-plugin\",\n      .exact(\"1.0.0\"))",
          requirement_string: ".exact(\"1.0.0\")"
        },
        {
          name: "swift-benchmark",
          url: "https://github.com/google/swift-benchmark",
          version: "0.1.1",
          requirement: ">= 0.1.0, < 0.1.2",
          declaration_string:
            ".package(name: \"foo\", url: \"https://github.com/google/swift-benchmark\", \"0.1.0\"..<\"0.1.2\")",
          requirement_string: "\"0.1.0\"..<\"0.1.2\""
        },
        {
          name: "swift-argument-parser",
          url: "https://github.com/apple/swift-argument-parser",
          version: "0.5.0"
        },
        {
          name: "xctest-dynamic-overlay",
          url: "https://github.com/pointfreeco/xctest-dynamic-overlay",
          version: "0.8.5"
        }
      ]
    end

    it_behaves_like "parse"
  end
end
