# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_fetcher/path_gemspec_finder"

RSpec.describe Dependabot::Bundler::FileFetcher::PathGemspecFinder do
  let(:finder) { described_class.new(gemfile: gemfile) }

  let(:gemfile) { bundler_project_dependency_file("gemfile", filename: "Gemfile") }

  describe "#path_gemspec_paths" do
    subject(:path_gemspec_paths) { finder.path_gemspec_paths }

    context "when the file does not include any path gemspecs" do
      it { is_expected.to eq([]) }
    end

    context "with invalid Ruby in the Gemfile" do
      let(:gemfile) { bundler_project_dependency_file("invalid_ruby", filename: "Gemfile") }

      it "raises a helpful error" do
        expect { finder.path_gemspec_paths }.to raise_error do |error|
          expect(error).to be_a(Dependabot::DependencyFileNotParseable)
          expect(error.file_name).to eq("Gemfile")
        end
      end
    end

    context "when the file does include a path gemspec" do
      let(:gemfile) { bundler_project_dependency_file("path_source", filename: "Gemfile") }
      it { is_expected.to eq([Pathname.new("plugins/example")]) }

      context "whose path must be eval-ed" do
        let(:gemfile) { bundler_project_dependency_file("path_source_eval", filename: "Gemfile") }

        it "raises a helpful error" do
          expect { finder.path_gemspec_paths }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotParseable)
            expect(error.file_name).to eq("Gemfile")
          end
        end
      end

      context "when this Gemfile is already in a nested directory" do
        let(:gemfile) do
          bundler_project_dependency_file("nested_path_source", filename: "nested/Gemfile")
        end

        it { is_expected.to eq([Pathname.new("nested/plugins/example")]) }
      end

      context "that is behind a conditional that is false" do
        let(:gemfile) { bundler_project_dependency_file("path_source_if", filename: "Gemfile") }
        it { is_expected.to eq([Pathname.new("plugins/example")]) }
      end
    end
  end
end
