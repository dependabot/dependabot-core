# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/language_version_manager"
require "dependabot/python/language"

RSpec.describe Dependabot::Python::LanguageVersionManager do
  subject(:manager) do
    described_class.new(python_requirement_parser: python_requirement_parser, **options)
  end

  let(:python_requirement_parser) do
    instance_double(
      Dependabot::Python::FileParser::PythonRequirementParser,
      user_specified_requirements: user_specified_requirements,
      imputed_requirements: []
    )
  end
  let(:options) { {} }
  let(:highest_version) { Dependabot::Python::Language::PRE_INSTALLED_HIGHEST_VERSION.to_s }
  let(:lowest_version) { Dependabot::Python::Language::PRE_INSTALLED_PYTHON_VERSIONS.min.to_s }

  describe "#python_version" do
    context "with a requirement that names only the major version" do
      let(:user_specified_requirements) { ["3"] }

      it "uses the lowest matching version" do
        expect(manager.python_version).to eq(lowest_version)
      end

      context "when matching the version Pipenv selects" do
        let(:options) { { highest_for_major_version: true } }

        it "uses the highest matching version" do
          expect(manager.python_version).to eq(highest_version)
        end
      end
    end

    context "with a requirement that names the minor version" do
      let(:user_specified_requirements) { ["3.12"] }
      let(:options) { { highest_for_major_version: true } }

      it "uses that minor version" do
        expect(manager.python_major_minor).to eq("3.12")
      end
    end

    context "with an unsupported major version" do
      let(:user_specified_requirements) { ["2"] }
      let(:options) { { highest_for_major_version: true } }

      it "raises a ToolVersionNotSupported error" do
        expect { manager.python_version }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end
  end
end
