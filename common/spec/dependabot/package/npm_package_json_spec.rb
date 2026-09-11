# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/package/npm_package_json"

RSpec.describe Dependabot::Package::NpmPackageJson do
  subject(:reader) { described_class.from_file(file) }

  let(:file) do
    Dependabot::DependencyFile.new(
      name: "packages/example/package.json",
      content: content
    )
  end
  let(:content) { JSON.pretty_generate(payload) + "\n" }
  let(:payload) do
    {
      "name" => "@scope/example",
      "dependencies" => { "first" => "^1", "empty" => "" },
      "devDependencies" => { "first" => "~2" },
      "optionalDependencies" => { "last" => "*" },
      "peerDependencies" => { "ignored" => "^3" },
      "packageManager" => "pnpm@9.1",
      "engines" => { "node" => ">=18", "unknown" => nil },
      "unknown" => { "nested" => [1, false] }
    }
  end
  let(:dependencies) do
    result = []
    reader.each_dependency { |name, requirement, type| result << [name, requirement, type] }
    result
  end

  it "yields string requirements in section and entry order" do
    expect(dependencies).to eq(
      [
        ["first", "^1", "dependencies"],
        ["empty", "", "dependencies"],
        ["first", "~2", "devDependencies"],
        ["last", "*", "optionalDependencies"]
      ]
    )
  end

  it "returns the package name unchanged" do
    expect(reader.name).to eq("@scope/example")
  end

  it "uses the existing package-manager config parser" do
    expect(reader.package_manager_config).to be_a(Dependabot::Package::NpmPackageManagerConfig)
    expect(reader.package_manager_config).to have_attributes(
      package_manager: "pnpm@9.1",
      engines: { "node" => ">=18" }
    )
  end

  it "leaves the original file and unknown fields unchanged" do
    original_content = file.content.dup

    dependencies
    reader.package_manager_config
    reader.name
    reader.flat?
    reader.workspaces?

    expect(file.content).to eq(original_content)
  end

  context "with protocol requirements" do
    let(:payload) do
      {
        "dependencies" => {
          "workspace" => "workspace:*",
          "catalog" => "catalog:testing",
          "alias" => "npm:other@^2",
          "git" => "git+ssh://git@example.com/project.git#v1",
          "file" => "file:../shared",
          "url" => "https://example.com/package.tgz"
        }
      }
    end

    it "does not interpret or normalize requirement strings" do
      expect(dependencies.map { |name, requirement, _type| [name, requirement] })
        .to eq(payload.fetch("dependencies").to_a)
    end
  end

  context "with non-string requirements" do
    let(:payload) do
      {
        "dependencies" => {
          "valid" => "1.0.0",
          "null" => nil,
          "false" => false,
          "true" => true,
          "number" => 12,
          "array" => ["1.0.0"],
          "object" => { "version" => "1.0.0" }
        }
      }
    end

    it "ignores them" do
      expect(dependencies).to eq([["valid", "1.0.0", "dependencies"]])
    end
  end

  context "with missing, null, and false sections" do
    let(:payload) { { "dependencies" => nil, "devDependencies" => false } }

    it "yields no dependencies" do
      expect(dependencies).to be_empty
    end
  end

  [[], [["package", "1.0.0"]], "invalid", 123, true].each do |value|
    context "with dependencies set to #{value.inspect}" do
      let(:payload) { { "dependencies" => value } }

      it "rejects the malformed map with file and field context" do
        expect { dependencies }
          .to raise_error(TypeError, "#{file.path}: dependencies must be an object")
      end
    end
  end

  [nil, [], "invalid", 123, false].each do |value|
    context "with #{value.inspect} as the manifest root" do
      let(:payload) { value }

      it "rejects the malformed root" do
        expect { reader }.to raise_error(TypeError, "#{file.path}: root must be an object")
      end
    end
  end

  context "with invalid JSON" do
    let(:content) { "{" }

    it "preserves the JSON parsing exception" do
      expect { reader }.to raise_error(JSON::ParserError)
    end
  end

  context "with unrelated malformed fields" do
    let(:payload) do
      {
        "name" => "example",
        "flat" => true,
        "workspaces" => [],
        "dependencies" => [],
        "engines" => true
      }
    end

    it "validates each field only when it is read" do
      expect(reader).to be_flat
      expect(reader).to be_workspaces
      expect(reader.name).to eq("example")
      expect { dependencies }
        .to raise_error(TypeError, "#{file.path}: dependencies must be an object")
      expect { reader.package_manager_config }.to raise_error(TypeError, "engines must be an object")
    end
  end

  [
    [nil, false], [false, false], [true, true], [[], true],
    [{}, true], ["", true], [0, true], ["invalid", true]
  ].each do |value, expected|
    context "with flags set to #{value.inspect}" do
      let(:payload) { { "flat" => value, "workspaces" => value } }

      it "preserves Ruby truthiness" do
        expect(reader.flat?).to eq(expected)
        expect(reader.workspaces?).to eq(expected)
      end
    end
  end

  context "without flags" do
    it "returns false" do
      expect(reader).not_to be_flat
      expect(reader).not_to be_workspaces
    end
  end

  context "with an empty name" do
    let(:payload) { { "name" => "" } }

    it "preserves the empty string" do
      expect(reader.name).to eq("")
    end
  end

  [nil, false, 123, [], {}].each do |value|
    context "with a non-string name #{value.inspect}" do
      let(:payload) { { "name" => value } }

      it "returns no workspace name" do
        expect(reader.name).to be_nil
      end
    end
  end

  context "without optional metadata" do
    let(:payload) { {} }

    it "keeps the existing missing-field defaults" do
      expect(reader.name).to be_nil
      expect(reader.package_manager_config).to have_attributes(package_manager: nil, engines: nil)
    end
  end
end
