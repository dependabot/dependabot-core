# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.shared_examples "a dependabot ecosystem module" do
  describe ".name" do
    subject { described_class.name }

    it { is_expected.to eq("Dependabot::Julia") }
  end

  describe ".package_ecosystem" do
    subject { described_class.package_ecosystem }

    it { is_expected.to eq("julia") }
  end

  it "has the file parsers", :aggregate_failures do
    expect(described_class.file_parser_class).to be_a(Class)
    expect(described_class::FileParser).to be_a(Class)
  end

  it "has the update checkers", :aggregate_failures do
    expect(described_class.update_checker_class).to be_a(Class)
    expect(described_class::UpdateChecker).to be_a(Class)
  end

  it "has the file updaters", :aggregate_failures do
    expect(described_class.file_updater_class).to be_a(Class)
    expect(described_class::FileUpdater).to be_a(Class)
  end

  it "has the metadata finders", :aggregate_failures do
    expect(described_class.metadata_finder_class).to be_a(Class)
    expect(described_class::MetadataFinder).to be_a(Class)
  end

  it "has a VERSION constant" do
    expect(described_class::VERSION).to be_a(String)
    expect(described_class::VERSION).not_to be_empty
  end
end
