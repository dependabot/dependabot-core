# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/haskell/file_parser"
require "dependabot/dependency"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Haskell::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [cabal_files] }
  let(:cabal_files) do
    Dependabot::DependencyFile.new(
      name: "Cabal.cabal",
      content: cabal_file_body
    )
  end
  let(:cabal_file_body) do
    fixture("cabal_files", cabal_file_fixture_name)
  end
  let(:cabal_file_fixture_name) { "Cabal.cabal" }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "haskell/cabal",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(21) }
    
    describe "the first dependency" do
      subject(:dependency) { dependencies.first }
      let(:expected_requirements) do
        [{
          requirement: ">= 0.4.0.1  && < 0.6",
          groups: [],
          file: "Cabal.cabal",
          source: nil,
          metadata: { declaration_string: "array      >= 0.4.0.1  && < 0.6" }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("array")
        expect(dependency.version).to eq(">= 0.4.0.1  && < 0.6")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

  end
end
