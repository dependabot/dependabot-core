# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/language"
require "dependabot/python/requirement"
require "dependabot/uv/language_version_manager"

RSpec.describe Dependabot::Uv::LanguageVersionManager do
  let(:python_requirement_parser) do
    double(
      user_specified_requirements: user_specified_requirements,
      imputed_requirements: []
    )
  end

  let(:manager) do
    described_class.new(
      python_requirement_parser: python_requirement_parser
    )
  end

  describe "#python_version" do
    context "when the project pins an exact patch version" do
      let(:user_specified_requirements) { ["==3.12.2"] }

      it "raises a helpful error" do
        expect { manager.python_version }.to raise_error(Dependabot::ToolVersionNotSupported) do |err|
          expect(err.message).to start_with(
            "Dependabot detected the following Python requirement for your project: '==3.12.2'."
          )
        end
      end
    end

    context "when .python-version pins an exact patch version" do
      let(:user_specified_requirements) { ["3.12.2"] }
      let(:expected_version) do
        Dependabot::Python::Language::PRE_INSTALLED_PYTHON_VERSIONS
          .map(&:to_s)
          .select { |version| version.start_with?("3.12.") }
          .max_by { |version| Gem::Version.new(version) }
      end

      it "uses the newest supported patch in that minor line" do
        expect(manager.python_version).to eq(expected_version)
      end
    end
  end
end
