# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/ruby/gemspec"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Gemspec do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [gemspec],
      github_access_token: "token"
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      requirement: old_requirement,
      package_manager: "gemspec",
      groups: []
    )
  end
  let(:gemspec) do
    Dependabot::DependencyFile.new(
      content: gemspec_body,
      name: "example.gemspec"
    )
  end
  let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }
  let(:old_requirement) { ">= 1.0.0" }

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
      let(:old_requirement) { "<= 1.3.0" }
      it { is_expected.to eq(true) }

      context "but we don't know how to fix it" do
        let(:old_requirement) { "!= 1.5.0" }
        it { is_expected.to eq(false) }
      end
    end
  end

  describe "#updated_requirement" do
    subject { checker.updated_requirement }

    context "when an = specifier was used" do
      let(:old_requirement) { "= 1.4.0" }
      it { is_expected.to eq(">= 1.4.0") }
    end

    context "when no specifier was used" do
      let(:old_requirement) { "1.4.0" }
      it { is_expected.to eq(">= 1.4.0") }
    end

    context "when a < specifier was used" do
      let(:old_requirement) { "< 1.4.0" }
      it { is_expected.to eq("< 1.6.0") }
    end

    context "when a <= specifier was used" do
      let(:old_requirement) { "<= 1.4.0" }
      it { is_expected.to eq("<= 1.6.0") }
    end

    context "when a ~> specifier was used" do
      let(:old_requirement) { "~> 1.4.0" }
      it { is_expected.to eq(">= 1.4, < 1.6") }

      context "with two zeros" do
        let(:old_requirement) { "~> 1.0.0" }
        it { is_expected.to eq(">= 1.0, < 1.6") }
      end

      context "with no zeros" do
        let(:old_requirement) { "~> 1.0.1" }
        it { is_expected.to eq(">= 1.0.1, < 1.6.0") }
      end

      context "with minor precision" do
        let(:old_requirement) { "~> 0.1" }
        it { is_expected.to eq(">= 0.1, < 2.0") }
      end
    end

    context "when there are multiple requirements" do
      let(:old_requirement) { "> 1.0.0, <= 1.4.0" }
      it { is_expected.to eq("> 1.0.0, <= 1.6.0") }
    end

    context "when a beta version was used in the old requirement" do
      let(:old_requirement) { "< 1.4.0.beta" }
      it { is_expected.to be_nil }
    end

    context "when a != specifier was used" do
      let(:old_requirement) { "!= 1.5.0" }
      it { is_expected.to be_nil }
    end

    context "when a >= specifier was used" do
      let(:old_requirement) { ">= 1.6.0" }
      it { is_expected.to be_nil }
    end

    context "when a > specifier was used" do
      let(:old_requirement) { "> 1.6.0" }
      it { is_expected.to be_nil }
    end
  end
end
