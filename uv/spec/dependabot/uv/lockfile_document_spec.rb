# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/uv/lockfile_document"

RSpec.describe Dependabot::Uv::LockfileDocument do
  subject(:document) { described_class.from_file(file) }

  let(:file) { Dependabot::DependencyFile.new(name: "uv.lock", content: content) }
  let(:content) do
    <<~TOML
      [manifest]
      members = ["Root_Project", false, "second"]

      [[package]]
      name = "Root_Project"
      source = { editable = false }
      dependencies = ["Foo_Bar", { name = "other" }, false, { name = 1 }]
      optional-dependencies = { extra = ["Foo_Bar", { name = "optional" }], ignored = false }
      dev-dependencies = { test = ["test"] }

      [[package]]
      name = "Foo_Bar"
      version = "1.0"
      dependencies = false

      [[package]]
      name = "Foo_Bar"
      version = "2.0"
      optional-dependencies = false

      [[package]]
      name = 12
      version = false
    TOML
  end

  it "retains only string workspace members without normalizing them" do
    expect(document.workspace_members).to eq(%w(Root_Project second))
  end

  it "retains package occurrences and versionless graph roots" do
    packages = document.graph_packages

    expect(packages.map(&:name)).to eq(["Root_Project", "Foo_Bar", "Foo_Bar", nil])
    expect(packages.map(&:version)).to eq([nil, "1.0", "2.0", nil])
    expect(packages.map(&:local_source)).to eq([true, false, false, false])
  end

  it "decodes each edge group without normalizing or deduplicating names" do
    root = document.graph_packages.first

    expect(root.dependencies).to eq(%w(Foo_Bar other))
    expect(root.optional_dependencies).to eq(%w(Foo_Bar optional))
    expect(root.dev_dependencies).to eq(["test"])
    expect(document.graph_packages.drop(1).map(&:dependencies)).to eq([[], [], []])
  end

  context "with non-object packages and an invalid manifest" do
    let(:content) do
      <<~TOML
        manifest = false
        package = [false, "ignored", { name = "valid", version = "1" }]
      TOML
    end

    it "skips non-object graph entries" do
      expect(document.graph_packages.map(&:name)).to eq(["valid"])
      expect(document.workspace_members).to eq([])
    end
  end

  context "with no packages" do
    let(:content) { "" }

    it "returns empty graph data" do
      expect(document.graph_packages).to eq([])
      expect(document.workspace_members).to eq([])
    end
  end

  context "with a malformed package container" do
    let(:content) { "package = false" }

    it "rejects the container instead of returning an apparently complete graph" do
      expect { document.graph_packages }.to raise_error(TypeError, /uv.lock.*package.*array/)
    end
  end

  context "with invalid TOML" do
    let(:content) { "not valid {{{" }

    it "leaves syntax errors for the caller to handle" do
      expect { document }.to raise_error(TomlRB::ParseError)
    end
  end

  describe "#each_dependency" do
    let(:content) do
      <<~TOML
        package = [
          false,
          { name = false, version = "1" },
          { name = "same", version = "1" },
          { name = "same", version = "1" },
          { name = "invalid", version = 2 },
          { name = "after", version = "3" },
        ]
      TOML
    end

    it "yields valid occurrences before a later consumed-field failure" do
      packages = []
      expect { document.each_dependency { |package| packages << [package.name, package.version] } }
        .to raise_error(TypeError, /uv.lock.*package.*version.*string/)
      expect(packages).to eq([%w(same 1), %w(same 1)])
    end
  end

  describe "#resolution_packages" do
    let(:content) do
      <<~TOML
        package = [
          "ignored",
          { name = "same", version = "1" },
          { name = "same", version = "1" },
          { name = "same", version = "invalid" },
          { name = "missing" },
          { version = "2" },
        ]
      TOML
    end

    it "retains duplicate occurrences and leaves version syntax to the resolver" do
      expect(document.resolution_packages.map { |package| [package.name, package.version] })
        .to eq([%w(same 1), %w(same 1), %w(same invalid)])
    end

    context "with false fields" do
      let(:content) { 'package = [{ name = false, version = "1" }]' }

      it "rejects the field that the dependency parser skips" do
        expect { document.resolution_packages }.to raise_error(TypeError, /uv.lock.*package.*name.*string/)
      end
    end
  end
end
