# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/language_version_manager"
require "dependabot/python/language"

RSpec.describe Dependabot::Python::LanguageVersionManager do
  extend T::Sig

  sig { returns(Dependabot::Python::LanguageVersionManager) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:manager) do
    described_class.new(
      python_requirement_parser: python_requirement_parser,
      highest_for_major_version: highest_for_major_version
    )
  end

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Python::FileParser::PythonRequirementParser) }
  let(:python_requirement_parser) do
    instance_double(
      Dependabot::Python::FileParser::PythonRequirementParser,
      user_specified_requirements: user_specified_requirements,
      imputed_requirements: []
    )
  end

  sig { returns(T::Array[String]) }
  let(:user_specified_requirements) { [] }

  sig { returns(T::Boolean) }
  let(:highest_for_major_version) { false }

  sig { returns(String) }
  let(:highest_version) { Dependabot::Python::Language::PRE_INSTALLED_HIGHEST_VERSION.to_s }

  sig { returns(String) }
  let(:lowest_version) { T.must(Dependabot::Python::Language::PRE_INSTALLED_PYTHON_VERSIONS.min).to_s }

  describe "#python_version" do
    context "with a requirement that names only the major version" do
      sig { override.returns(T::Array[String]) }
      let(:user_specified_requirements) { ["3"] }

      it "uses the lowest matching version" do
        expect(manager.python_version).to eq(lowest_version)
      end

      context "when matching the version Pipenv selects" do
        sig { override.returns(T::Boolean) }
        let(:highest_for_major_version) { true }

        it "uses the highest matching version" do
          expect(manager.python_version).to eq(highest_version)
        end
      end
    end

    context "with a requirement that names the minor version" do
      sig { override.returns(T::Array[String]) }
      let(:user_specified_requirements) { ["3.12"] }

      sig { override.returns(T::Boolean) }
      let(:highest_for_major_version) { true }

      it "uses that minor version" do
        expect(manager.python_major_minor).to eq("3.12")
      end
    end

    context "with an unsupported major version" do
      sig { override.returns(T::Array[String]) }
      let(:user_specified_requirements) { ["2"] }

      sig { override.returns(T::Boolean) }
      let(:highest_for_major_version) { true }

      it "raises a ToolVersionNotSupported error" do
        expect { manager.python_version }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end
  end
  # rubocop:enable RSpec/ScatteredLet
end
