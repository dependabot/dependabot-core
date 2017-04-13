# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/update_checkers/python"

RSpec.describe Bump::UpdateCheckers::Python do
  before do
    stub_request(:get, "https://pypi.python.org/pypi/luigi/json").
      to_return(status: 200, body: fixture("pypi_response.json"))
  end

  let(:checker) do
    described_class.new(dependency: dependency, dependency_files: [])
  end

  let(:dependency) { Bump::Dependency.new(name: "luigi", version: "2.0.0") }

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      let(:dependency) { Bump::Dependency.new(name: "luigi", version: "2.6.0") }
      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq("2.6.0") }
  end

  describe "#updated_dependency" do
    subject { checker.updated_dependency }
    it "returns an instance of Dependency" do
      expect(subject.name).to eq("luigi")
      expect(subject.version).to eq("2.6.0")
      expect(subject.previous_version).to eq("2.0.0")
      expect(subject.language).to eq("python")
    end
  end
end
