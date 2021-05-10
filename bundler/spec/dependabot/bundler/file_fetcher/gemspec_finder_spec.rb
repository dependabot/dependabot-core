# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_fetcher/gemspec_finder"

RSpec.describe Dependabot::Bundler::FileFetcher::GemspecFinder do
  let(:finder) { described_class.new(gemfile: gemfile) }

  describe "#gemspec_directories" do
    subject(:gemspec_directories) { finder.gemspec_directories }

    context "when the file does not include any gemspecs" do
      let(:gemfile) { bundler_project_dependency_file("gemfile", filename: "Gemfile") }
      it { is_expected.to eq([]) }
    end

    context "with invalid Ruby in the Gemfile" do
      let(:gemfile) { bundler_project_dependency_file("invalid_ruby", filename: "Gemfile") }

      it "raises a helpful error" do
        expect { finder.gemspec_directories }.to raise_error do |error|
          expect(error).to be_a(Dependabot::DependencyFileNotParseable)
          expect(error.file_name).to eq("Gemfile")
        end
      end
    end

    context "when the file does include a gemspec reference" do
      let(:gemfile) { bundler_project_dependency_file("imports_gemspec", filename: "Gemfile") }
      it { is_expected.to eq([Pathname.new(".")]) }

      context "that has a path specified" do
        let(:gemfile) { bundler_project_dependency_file("imports_gemspec_from_path", filename: "Gemfile") }

        it { is_expected.to eq([Pathname.new("subdir")]) }

        context "when this Gemfile is already in a nested directory" do
          let(:gemfile) do
            bundler_project_dependency_file("imports_gemspec_from_nested_path", filename: "nested/Gemfile")
          end

          it { is_expected.to eq([Pathname.new("nested/subdir")]) }
        end
      end
    end
  end
end
