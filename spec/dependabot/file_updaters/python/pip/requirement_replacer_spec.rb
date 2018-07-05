# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_updaters/python/pip/requirement_replacer"

RSpec.describe Dependabot::FileUpdaters::Python::Pip::RequirementReplacer do
  let(:replacer) do
    described_class.new(
      content: requirement_content,
      dependency_name: dependency_name,
      old_requirement: old_requirement,
      new_requirement: new_requirement
    )
  end

  let(:requirement_content) do
    fixture("python", "pip_compile_files", "bounded.in")
  end
  let(:dependency_name) { "attrs" }
  let(:old_requirement) { "<=17.4.0" }
  let(:new_requirement) { ">=17.3.0" }

  describe "#updated_content" do
    subject(:updated_content) { replacer.updated_content }

    it { is_expected.to include("Attrs>=17.3.0\n") }
    it { is_expected.to include("mock\n") }

    context "with multiple requirements" do
      let(:dependency_name) { "django" }
      let(:requirement_content) { "django>=1.11,<1.12" }
      # Order swapped during file parsing
      let(:old_requirement) { "<1.12,>=1.11" }
      let(:new_requirement) { ">=1.11.5" }

      it { is_expected.to eq("django>=1.11.5") }
    end

    context "with no requirement" do
      let(:old_requirement) { nil }
      let(:new_requirement) { "==1.11.5" }

      context "and another requirement with the same beginning" do
        let(:dependency_name) { "pytest" }
        it { is_expected.to include("pytest==1.11.5") }
        it { is_expected.to include("pytest-xdist\n") }
      end

      context "and another requirement with the same ending" do
        let(:requirement_content) do
          fixture("python", "pip_compile_files", "superstring.in")
        end
        let(:dependency_name) { "sqlalchemy" }
        it { is_expected.to include("\nSQLAlchemy==1.11.5") }
        it { is_expected.to include("Flask-SQLAlchemy\n") }
      end
    end
  end
end
