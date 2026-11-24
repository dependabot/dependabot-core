# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/requirement_references"

RSpec.describe Dependabot::Python::RequirementReferences do
  let(:file) do
    Dependabot::DependencyFile.new(
      name: "requirements/base.txt",
      content: content
    )
  end

  let(:content) do
    <<~REQUIREMENTS
      -r child.txt
      --requirement=extras.in
      --no-index --constraint ../pins.txt
      --find-links https://example.com -cconstraints.txt
      --requirement \\
        continued.txt
    REQUIREMENTS
  end

  it "parses short, long, compact, preceded, and continued references" do
    expect(described_class.references(file).map { |reference| [reference.path, reference.constraint] }).to eq(
      [
        ["requirements/child.txt", false],
        ["requirements/extras.in", false],
        ["pins.txt", true],
        ["requirements/constraints.txt", true],
        ["requirements/continued.txt", false]
      ]
    )
  end

  it "filters references by type" do
    expect(described_class.requirement_paths(file)).to eq(
      %w(requirements/child.txt requirements/extras.in requirements/continued.txt)
    )
    expect(described_class.constraint_paths(file)).to eq(
      %w(pins.txt requirements/constraints.txt)
    )
  end
end
