# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/update_checkers/base"

RSpec.describe Bump::UpdateCheckers::Base do
  let(:updater_instance) do
    described_class.new(
      dependency: dependency,
      dependency_files: []
    )
  end
  let(:dependency) do
    Bump::Dependency.new(
      name: "business",
      version: "1.5.0",
      language: "ruby"
    )
  end
  let(:latest_version) { Gem::Version.new("1.0.0") }
  before do
    allow(updater_instance).
      to receive(:latest_version).
      and_return(latest_version)
  end

  describe "#needs_update?" do
    subject(:needs_update) { updater_instance.needs_update? }

    context "when the dependency is outdated" do
      let(:latest_version) { Gem::Version.new("1.6.0") }
      it { is_expected.to be_truthy }
    end

    context "when the dependency is up-to-date" do
      let(:latest_version) { Gem::Version.new("1.5.0") }
      it { is_expected.to be_falsey }
    end

    context "when the dependency couldn't be found" do
      let(:latest_version) { nil }
      it { is_expected.to be_falsey }
    end
  end

  describe "#updated_dependency" do
    subject(:updated_dependency) { updater_instance.updated_dependency }

    its(:version) { is_expected.to eq("1.0.0") }
    its(:previous_version) { is_expected.to eq("1.5.0") }
    its(:language) { is_expected.to eq(dependency.language) }
    its(:name) { is_expected.to eq(dependency.name) }
  end
end
