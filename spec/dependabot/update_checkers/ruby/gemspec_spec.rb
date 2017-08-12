# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/ruby/gemspec"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Gemspec do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      github_access_token: "token"
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.3.0",
      requirement: old_requirement,
      package_manager: "gemspec"
    )
  end
  let(:old_requirement) { Gem::Requirement.new(">= 1.0.0") }

  before do
    stub_request(:get, "https://rubygems.org/api/v1/gems/business.json").
      to_return(status: 200, body: fixture("ruby", "rubygems_response.json"))
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it { is_expected.to eq(Gem::Version.new("1.5.0")) }

    it "only hits Rubygems once" do
      checker.latest_version

      expect(WebMock).
        to have_requested(
          :get,
          "https://rubygems.org/api/v1/gems/business.json"
        ).once
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(Gem::Version.new("1.5.0")) }
  end

  describe "needs_update?" do
    subject { checker.needs_update? }

    it { is_expected.to eq(false) }

    context "when the existing requirement blocks the latest version" do
      let(:old_requirement) { Gem::Requirement.new("<= 1.3.0") }
      it { is_expected.to eq(true) }
    end
  end

  describe "#updated_dependency" do
    subject { checker.updated_dependency }

    context "when an = specifier was used" do
      let(:old_requirement) { Gem::Requirement.new("= 1.4.0") }
      its(:requirement) { is_expected.to eq(Gem::Requirement.new("= 1.5.0")) }
    end

    context "when no specifier was used" do
      let(:old_requirement) { Gem::Requirement.new("1.4.0") }
      its(:requirement) { is_expected.to eq(Gem::Requirement.new("1.5.0")) }
    end

    context "when a < specifier was used" do
      let(:old_requirement) { Gem::Requirement.new("< 1.4.0") }
      its(:requirement) { is_expected.to eq(Gem::Requirement.new("< 1.6.0")) }
    end

    context "when a <= specifier was used" do
      let(:old_requirement) { Gem::Requirement.new("<= 1.4.0") }
      its(:requirement) { is_expected.to eq(Gem::Requirement.new("<= 1.6.0")) }
    end

    context "when a ~> specifier was used" do
      let(:old_requirement) { Gem::Requirement.new("~> 1.4.0") }
      its(:requirement) do
        is_expected.to eq(Gem::Requirement.new(">= 1.4.0", "< 1.6.0"))
      end
    end

    context "when there are multiple requirements" do
      let(:old_requirement) { Gem::Requirement.new("> 1.0.0", "<= 1.4.0") }
      its(:requirement) do
        is_expected.to eq(Gem::Requirement.new("> 1.0.0", "<= 1.6.0"))
      end
    end
  end
end
