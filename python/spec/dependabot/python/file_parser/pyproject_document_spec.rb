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
end
