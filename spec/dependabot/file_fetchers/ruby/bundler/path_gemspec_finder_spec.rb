# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_fetchers/ruby/bundler/path_gemspec_finder"

RSpec.describe Dependabot::FileFetchers::Ruby::Bundler::PathGemspecFinder do
  let(:finder) { described_class.new(gemfile: gemfile) }

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: gemfile_name)
  end
  let(:gemfile_name) { "Gemfile" }
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }

  describe "#path_gemspec_paths" do
    subject(:path_gemspec_paths) { finder.path_gemspec_paths }

    context "when the file does not include any path gemspecs" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
      it { is_expected.to eq([]) }
    end

    context "when the file does include a path gemspec" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "path_source") }
      it { is_expected.to eq(["plugins/example/example.gemspec"]) }

      context "whose path must be eval-ed" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "path_source_eval") }
        it { is_expected.to eq(["plugins/example/example.gemspec"]) }
      end

      context "when this Gemfile is already in a nested directory" do
        let(:gemfile_name) { "nested/Gemfile" }

        it { is_expected.to eq(["nested/plugins/example/example.gemspec"]) }
      end

      context "that is behind a conditional that is false" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "path_source_if") }
        it { is_expected.to eq([]) }
      end
    end
  end
end
