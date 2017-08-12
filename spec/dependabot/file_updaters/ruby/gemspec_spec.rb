# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/ruby/gemspec"
require "dependabot/shared_helpers"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Ruby::Gemspec do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: [gemspec],
      dependency: dependency,
      github_access_token: "token"
    )
  end
  let(:gemspec) do
    Dependabot::DependencyFile.new(
      content: gemspec_body,
      name: "example.gemspec"
    )
  end
  let(:gemspec_body) do
    fixture("ruby", "gemspecs", "example")
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "octokit",
      version: "5.0.0",
      requirement: Gem::Requirement.new(">= 4.6", "< 6.0"),
      package_manager: "gemspec"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated gemspec" do
      subject(:updated_gemspec) do
        updated_files.find { |f| f.name == "example.gemspec" }
      end

      its(:content) do
        is_expected.to include "octokit\", \"< 6.0\", \">= 4.6\"\n"
      end
    end
  end
end
