# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/dependency"
require "dependabot/file_parsers/go/modules"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Go::Modules do
  it_behaves_like "a dependency file parser"

  let(:parser) { described_class.new(dependency_files: files, source: source) }

  let(:files) { [go_mod] }
  let(:go_mod) do
    Dependabot::DependencyFile.new(
      name: "go.mod",
      content: fixture("go", "go_mods", "go.mod")
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  it "requires a go.mod to be present" do
    expect do
      described_class.new(dependency_files: [], source: source)
    end.to raise_error(RuntimeError)
  end

  it "returns parsed dependencies" do
    dependencies = parser.parse
    expect(dependencies.length).to eq(5)
    expect(dependencies[0]).to be_a(Dependabot::Dependency)
  end
end
