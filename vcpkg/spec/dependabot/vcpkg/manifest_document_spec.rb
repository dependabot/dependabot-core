# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/vcpkg/manifest_document"

RSpec.describe Dependabot::Vcpkg::ManifestDocument do
  subject(:document) { described_class.from_file(file) }

  let(:file) { Dependabot::DependencyFile.new(name: "vcpkg.json", directory: "/project", content: content) }
  let(:content) { JSON.dump(data) }
  let(:data) do
    {
      "$schema" => "schema.json",
      "builtin-baseline" => "old-baseline",
      "dependencies" => [
        "fmt",
        { "name" => "zlib", "version>=" => "1.2.11", "features" => ["tools"], "default-features" => false }
      ],
      "default-registry" => {
        "kind" => "git",
        "repository" => "https://github.com/microsoft/vcpkg",
        "baseline" => "default-baseline",
        "$comment" => "keep"
      },
      "registries" => [
        { "kind" => "git", "repository" => "https://example.test/registry", "baseline" => "old",
          "packages" => ["x-*"] },
        { "kind" => "builtin", "baseline" => "builtin-old" }
      ],
      "unknown" => { "nested" => [false, nil, { "keep" => 7 }] }
    }
  end

  it "reads typed port and registry values" do
    expect(document.ports.map(&:name)).to eq(%w(fmt zlib))
    expect(document.ports.map(&:constraint)).to eq([nil, "1.2.11"])
    expect(document.default_registry).to have_attributes(
      name: "https://github.com/microsoft/vcpkg",
      baseline: "default-baseline",
      repository: "https://github.com/microsoft/vcpkg",
      reference: "HEAD",
      builtin: false
    )
    expect(document.registries.last).to have_attributes(
      name: "github.com/microsoft/vcpkg",
      baseline: "builtin-old",
      reference: "master",
      builtin: true
    )
  end

  it "preserves the original tree and pretty-generation format" do
    expect(document.content).to eq(JSON.pretty_generate(data))
  end

  it "writes nested changes back without losing unrelated fields or mutating the input file" do
    document.set_port_version(name: "fmt", version: "11.0.0")
    document.set_port_version(name: "zlib", version: "1.3.1#2")
    document.set_registry_baseline(
      baseline: "registry-new",
      repository: "https://example.test/registry",
      builtin: false
    )
    document.set_baseline(path: %w(default-registry baseline), baseline: "default-new")
    document.set_baseline(path: ["builtin-baseline"], baseline: "manifest-new")

    expected = data.merge("builtin-baseline" => "manifest-new")
    expected["dependencies"][0] = { "name" => "fmt", "version>=" => "11.0.0" }
    expected["dependencies"][1]["version>="] = "1.3.1#2"
    expected["registries"][0]["baseline"] = "registry-new"
    expected["default-registry"]["baseline"] = "default-new"
    expect(document.content).to eq(JSON.pretty_generate(expected))
    expect(file.content).to eq(content)
    expect(JSON.parse(file.content)["builtin-baseline"]).to eq("old-baseline")
  end

  context "with an incomplete default registry and skipped declarations" do
    let(:data) do
      { "default-registry" => { "kind" => "git" }, "dependencies" => [{ "name" => false }] }
    end

    it "retains declaration and registry presence separately from usable records" do
      expect(document.default_registry_present?).to be(true)
      expect(document.default_registry).to be_nil
      expect(document.default_registry_baseline).to be_nil
      expect(document.dependencies_declared?).to be(true)
      expect(document.ports).to be_empty
    end
  end

  context "with unsupported or incomplete registry entries" do
    let(:data) do
      { "registries" => [
        { "kind" => "filesystem", "baseline" => "default", "reference" => [] },
        { "kind" => "git", "baseline" => "old" },
        { "kind" => "git", "repository" => "https://example.test/registry", "baseline" => 1 }
      ] }
    end

    it "ignores them without validating fields it does not use" do
      expect(document.registries).to be_empty
    end
  end

  [nil, false, ""].each do |reference|
    context "with registry reference #{reference.inspect}" do
      let(:data) do
        super().tap { |value| value["default-registry"]["reference"] = reference }
      end

      it "preserves the existing reference default" do
        expect(document.default_registry.reference).to eq(reference || "HEAD")
      end
    end
  end

  context "with duplicate port declarations" do
    let(:data) { { "dependencies" => ["fmt", { "name" => "fmt", "version>=" => "1" }] } }

    it "updates only the first matching declaration" do
      document.set_port_version(name: "fmt", version: "2")
      expect(JSON.parse(document.content)["dependencies"]).to eq(
        [{ "name" => "fmt", "version>=" => "2" }, { "name" => "fmt", "version>=" => "1" }]
      )
    end
  end

  context "with an existing override" do
    let(:data) do
      super().merge(
        "overrides" => [
          { "name" => "fmt", "version" => "10" },
          { "name" => "zlib", "version-string" => "legacy", "port-version" => 1 }
        ]
      )
    end

    it "replaces that pin without retaining conflicting scheme fields" do
      document.set_override(name: "zlib", version: "1.3.1#2")
      expect(JSON.parse(document.content)["overrides"]).to eq(
        [{ "name" => "fmt", "version" => "10" }, { "name" => "zlib", "version" => "1.3.1#2" }]
      )
    end
  end

  context "without optional containers" do
    let(:data) { {} }

    it "reads empty collections and creates a requested default registry and pin" do
      expect(document.ports).to be_empty
      expect(document.registries).to be_empty
      expect(document.default_registry_present?).to be(false)
      document.set_default_registry_baseline(baseline: "new", create: true)
      document.set_override(name: "zlib", version: "1.3.1")
      expect(JSON.parse(document.content)).to eq(
        "default-registry" => {
          "kind" => "git", "repository" => "https://github.com/microsoft/vcpkg", "baseline" => "new"
        },
        "overrides" => [{ "name" => "zlib", "version" => "1.3.1" }]
      )
    end
  end

  [nil, [], "invalid", 7, false].each do |root|
    context "with #{root.inspect} as the root" do
      let(:data) { root }

      it "identifies the file and root shape" do
        expect { document }.to raise_error(
          Dependabot::DependencyFileNotParseable, "/project/vcpkg.json: root must be an object"
        ) do |error|
          expect(error.file_path).to eq("/project/vcpkg.json")
        end
      end
    end
  end

  context "with invalid JSON" do
    let(:content) { "{ invalid json" }

    it "reports the file without echoing its content" do
      expect { document }.to raise_error(Dependabot::DependencyFileNotParseable, "/project/vcpkg.json: invalid JSON")
    end
  end

  context "with malformed dependency and registry collections" do
    let(:data) { { "builtin-baseline" => "old", "dependencies" => {}, "registries" => false } }

    it "rejects malformed fields only when they are read" do
      expect(document.builtin_baseline).to eq("old")
      expect { document.ports }.to raise_error(Dependabot::DependencyFileNotParseable, /dependencies must be an array/)
      expect do
        document.registries
      end.to raise_error(Dependabot::DependencyFileNotParseable, /registries must be an array/)
    end

    it "rejects an edit instead of silently skipping it" do
      expect { document.set_port_version(name: "fmt", version: "2") }
        .to raise_error(Dependabot::DependencyFileNotParseable, /dependencies must be an array/)
    end

    it "preserves unrelated malformed fields when changing the baseline" do
      document.set_baseline(path: ["builtin-baseline"], baseline: "new")
      expect(JSON.parse(document.content)).to eq(data.merge("builtin-baseline" => "new"))
    end
  end

  context "with malformed overrides" do
    let(:data) { { "overrides" => { "keep" => "invalid" } } }

    it "does not replace the invalid container" do
      expect { document.set_override(name: "fmt", version: "2") }
        .to raise_error(Dependabot::DependencyFileNotParseable, /overrides must be an array/)
      expect(JSON.parse(document.content)).to eq(data)
    end
  end

  context "with a malformed default registry" do
    let(:data) { { "default-registry" => [] } }

    it "does not overwrite it even when creation is requested" do
      expect { document.set_default_registry_baseline(baseline: "new", create: true) }
        .to raise_error(Dependabot::DependencyFileNotParseable, /default-registry must be an object/)
    end
  end

  context "with null optional containers" do
    let(:data) { { "dependencies" => nil, "registries" => nil, "default-registry" => nil, "overrides" => nil } }

    it "preserves absence until an operation creates the requested field" do
      expect(document.dependencies_declared?).to be(false)
      expect(document.ports).to be_empty
      expect(document.registries).to be_empty
      document.set_default_registry_baseline(baseline: "unused", create: false)
      document.set_port_version(name: "missing", version: "2")
      expect(JSON.parse(document.content)).to eq(data)
      document.set_override(name: "fmt", version: "2")
      expect(JSON.parse(document.content)).to eq(data.merge("overrides" => [{ "name" => "fmt", "version" => "2" }]))
    end
  end

  context "with duplicate matching registries" do
    let(:data) do
      { "registries" => [
        { "kind" => "builtin", "baseline" => "first" },
        { "kind" => "builtin", "baseline" => "second" }
      ] }
    end

    it "updates only the first match" do
      document.set_registry_baseline(baseline: "new", repository: nil, builtin: true)
      expect(JSON.parse(document.content)["registries"].map { |entry| entry["baseline"] }).to eq(%w(new second))
    end
  end

  context "with a malformed registry entry" do
    let(:data) { { "registries" => [{ "kind" => "filesystem" }, nil] } }

    it "identifies the array position" do
      expect { document.registries }
        .to raise_error(Dependabot::DependencyFileNotParseable, "/project/vcpkg.json: registries[1] must be an object")
    end
  end

  context "with an unusable reference on a supported registry" do
    let(:data) do
      super().tap { |value| value["default-registry"]["reference"] = [] }
    end

    it "rejects the reference only when a tracked registry needs it" do
      expect(document.default_registry_baseline).to eq("default-baseline")
      expect { document.default_registry }
        .to raise_error(Dependabot::DependencyFileNotParseable, /default-registry.reference must be a string/)
    end
  end
end
