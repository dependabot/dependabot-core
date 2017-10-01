# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_fetchers/ruby/bundler/child_gemfile_finder"

RSpec.describe Dependabot::FileFetchers::Ruby::Bundler::ChildGemfileFinder do
  let(:finder) do
    described_class.new(gemfile: gemfile)
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: gemfile_name)
  end
  let(:gemfile_name) { "Gemfile" }
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }

  describe "#child_gemfile_paths" do
    subject(:child_gemfile_paths) { finder.child_gemfile_paths }

    context "when the file does not include any child Gemfiles" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
      it { is_expected.to eq([]) }
    end

    context "when the file does include a child Gemfile" do
      context "whose path must be eval-ed" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "eval_gemfile") }
        it { is_expected.to eq(["backend/Gemfile"]) }
      end

      context "within a group block" do
        let(:gemfile_body) do
          "group :development do\neval_gemfile('some_gemfile')\nend"
        end
        it { is_expected.to eq(["some_gemfile"]) }
      end

      context "when this Gemfile is already in a nested directory" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "eval_gemfile") }
        let(:gemfile_name) { "nested/Gemfile" }

        it { is_expected.to eq(["nested/backend/Gemfile"]) }
      end
    end
  end
end
