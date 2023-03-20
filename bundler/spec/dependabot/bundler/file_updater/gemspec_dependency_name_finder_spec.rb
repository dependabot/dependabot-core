# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/bundler/file_updater/gemspec_dependency_name_finder"

RSpec.describe Dependabot::Bundler::FileUpdater::GemspecDependencyNameFinder do
  let(:finder) { described_class.new(gemspec_content: gemspec_content) }
  let(:gemspec_content) do
    bundler_project_dependency_file("gemfile_small_example", filename: "example.gemspec").content
  end

  describe "#dependency_name" do
    subject(:dependency_name) { finder.dependency_name }

    it { is_expected.to eq("example") }

    context "with an unevaluatable gemspec name" do
      let(:gemspec_content) do
        bundler_project_dependency_file("gemfile_function_name", filename: "example.gemspec").content
      end
      it { is_expected.to be_nil }
    end
  end
end
