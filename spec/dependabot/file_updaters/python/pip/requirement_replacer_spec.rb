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
  let(:new_requirement) { ">=17.4.0" }

  describe "#updated_content" do
    subject(:updated_content) { replacer.updated_content }

    it { is_expected.to include("Attrs>=17.4.0\n") }
    it { is_expected.to include("mock\n") }
  end
end
