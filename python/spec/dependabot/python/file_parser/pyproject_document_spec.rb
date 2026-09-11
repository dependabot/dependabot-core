# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/file_parser/pyproject_document"

RSpec.describe Dependabot::Python::FileParser::PyprojectDocument do
  subject(:document) { described_class.from_file(file) }

  let(:file) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: content
    )
  end
  let(:content) do
    <<~TOML
      [project]
      dependencies = ["requests>=2"]
      dynamic = ["optional-dependencies"]

      [project.optional-dependencies]
      test = ["pytest"]

      [tool.poetry.dependencies]
      python = "^3.12"
      requests = "^2.0"
      attrs = [{ version = "^24.0" }]

      [tool.poetry.group.dev.dependencies]
      rspec = "^3.0"

      [[tool.poetry.source]]
      name = "private"
      url = "https://example.com/simple"

      [tool.uv.workspace]
      members = ["packages/*"]
      exclude = ["packages/ignored"]

      [dependency-groups]
      lint = ["ruff"]
    TOML
  end

  it "exposes typed project and Poetry values" do
    expect(document).to be_poetry
    expect(document).to be_pep621
    expect(document).to be_pep735
    expect(document.dynamic_fields).to eq(["optional-dependencies"])
    expect(document.optional_dependency_group?("test")).to be(true)
    expect(document.poetry_dependencies("dependencies")).to eq(
      "python" => ["^3.12"],
      "requests" => ["^2.0"],
      "attrs" => [{ "version" => "^24.0" }]
    )
    expect(document.poetry_groups).to eq(
      "dev" => { "rspec" => ["^3.0"] }
    )
  end

  it "resolves Poetry sources and UV workspace globs" do
    expect(document.poetry_source("private")).to have_attributes(
      name: "private",
      url: "https://example.com/simple"
    )
    expect(document.workspace_globs("members")).to eq(["packages/*"])
    expect(document.workspace_globs("exclude")).to eq(["packages/ignored"])
  end

  context "with Poetry's reserved PyPI source" do
    let(:content) do
      <<~TOML
        [[tool.poetry.source]]
        name = "pypi"
        priority = "explicit"

        [[tool.poetry.source]]
        name = "private"
        url = "https://example.com/simple"
      TOML
    end

    it "allows the reserved source to omit its URL" do
      expect(document.poetry_source("pypi")).to have_attributes(name: "pypi", url: nil)
      expect(document.poetry_source("private")).to have_attributes(
        name: "private",
        url: "https://example.com/simple"
      )
    end
  end

  it "ignores unknown keys" do
    file.content = "#{content}\n[tool.unknown]\nvalue = 1\n"

    expect(document.poetry_dependencies("dependencies")).to include("requests" => ["^2.0"])
  end

  context "with invalid TOML" do
    let(:content) { "[project\n" }

    it "raises the existing parse error" do
      expect { document }.to raise_error(Dependabot::DependencyFileNotParseable)
    end
  end

  context "with a malformed Poetry dependency value" do
    let(:content) do
      <<~TOML
        [tool.poetry.dependencies]
        requests = 123
      TOML
    end

    it "raises an explicit type error" do
      expect { document.poetry_dependencies("dependencies") }
        .to raise_error(TypeError, "Poetry dependency requests must be a string, object, or array")
    end
  end

  context "with malformed workspace globs" do
    let(:content) do
      <<~TOML
        [tool.uv.workspace]
        members = ["packages/*", 1]
      TOML
    end

    it "raises an explicit type error" do
      expect { document.workspace_globs("members") }
        .to raise_error(TypeError, "tool.uv.workspace.members must contain only strings")
    end
  end

  describe "library metadata" do
    let(:content) do
      <<~TOML
        [tool.poetry]
        name = "poetry-project"
        description = "Poetry description"

        [project]
        name = "standard-project"
        description = "Project description"

        [build-system]
        name = "build-project"
        description = "Build description"
      TOML
    end

    it "returns typed metadata for each section" do
      expect(document.poetry_metadata).to have_attributes(
        name: "poetry-project", description: "Poetry description"
      )
      expect(document.project_metadata).to have_attributes(
        name: "standard-project", description: "Project description"
      )
      expect(document.build_system_metadata).to have_attributes(
        name: "build-project", description: "Build description"
      )
    end

    context "with an empty project section" do
      let(:content) { "[project]" }

      it "distinguishes a present section from a missing one" do
        expect(document).to be_project
        expect(document).not_to be_pep621
        expect(document.project_metadata).to have_attributes(name: nil, description: nil)
        expect(document.poetry_metadata).to be_nil
        expect(document.build_system_metadata).to be_nil
      end
    end

    context "without metadata sections" do
      let(:content) { "" }

      it "returns no metadata" do
        expect(document).not_to be_project
        expect(document.poetry_metadata).to be_nil
        expect(document.project_metadata).to be_nil
        expect(document.build_system_metadata).to be_nil
      end
    end

    context "with a non-string name" do
      let(:content) { "[project]\nname = 123" }

      it "raises a contextual error when the metadata is read" do
        expect(document).to be_project
        expect { document.project_metadata }.to raise_error(TypeError, "project.name must be a string")
      end
    end

    context "with a non-table metadata section" do
      let(:content) { "project = 123" }

      it "rejects the malformed section" do
        expect { document.project_metadata }.to raise_error(TypeError, "project must be an object")
      end
    end

    context "with a non-string description" do
      let(:content) do
        <<~TOML
          [tool.poetry]
          name = "valid-project"

          [project]
          description = false
        TOML
      end

      it "validates only the requested metadata section" do
        expect(document.poetry_metadata).to have_attributes(name: "valid-project", description: nil)
        expect { document.project_metadata }
          .to raise_error(TypeError, "project.description must be a string")
      end
    end

    context "with unknown metadata fields" do
      let(:content) { "[project]\nname = \"example\"\nextra = { nested = [1, false] }" }

      it "reads known fields without validating unrelated fields" do
        expect(document.project_metadata).to have_attributes(name: "example", description: nil)
      end
    end
  end

  describe ".from_content" do
    it "parses the same document without a dependency file" do
      expect(described_class.from_content(content).poetry_dependencies("dependencies"))
        .to eq(document.poetry_dependencies("dependencies"))
    end

    it "preserves native TOML syntax errors" do
      expect { described_class.from_content("[project\n") }.to raise_error(TomlRB::ParseError)
    end

    it "preserves native duplicate-key errors" do
      expect { described_class.from_content("[project]\nname = \"one\"\nname = \"two\"") }
        .to raise_error(TomlRB::ValueOverwriteError)
    end
  end
end
