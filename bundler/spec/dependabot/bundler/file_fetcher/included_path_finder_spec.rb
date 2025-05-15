# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_fetcher/included_path_finder"

RSpec.describe Dependabot::Bundler::FileFetcher::IncludedPathFinder do
  let(:finder) { described_class.new(file: file) }

  let(:file) do
    Dependabot::DependencyFile.new(content: file_body, name: file_name)
  end
  let(:file_name) { "Gemfile" }

  describe "#find_included_paths" do
    subject(:find_included_paths) { finder.find_included_paths }

    context "when the file does not include any relative paths" do
      let(:file_body) { bundler_project_dependency_file("gemfile", filename: "Gemfile").content }

      it { is_expected.to eq([]) }
    end

    context "with invalid Ruby in the Gemfile" do
      let(:file_body) { bundler_project_dependency_file("invalid_ruby", filename: "Gemfile").content }

      it "raises a helpful error" do
        suppress_output do
          expect { finder.find_included_paths }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotParseable)
            expect(error.file_name).to eq("Gemfile")
          end
        end
      end
    end

    context "when the file includes a require_relative path" do
      let(:file_body) do
        bundler_project_dependency_file("includes_require_relative_gemfile", filename: "nested/Gemfile").content
      end

      it { is_expected.to eq(["../some_other_file.rb"]) }

      context "when dealing with a file that includes a .rb suffix" do
        let(:file_body) do
          'require_relative "../some_other_file.rb"'
        end

        it { is_expected.to eq(["../some_other_file.rb"]) }
      end

      # rubocop:disable Lint/InterpolationCheck
      context "when the file body needs to be evaluated" do
        let(:file_body) do
          'require_relative "./my_file_#{raise %(hell)}"'
        end

        it { is_expected.to eq([]) }
      end

      context "when the file body can't be evaluated" do
        let(:file_body) do
          'require_relative "./my_file_#{unknown_var}"'
        end

        it { is_expected.to eq([]) }
      end
      # rubocop:enable Lint/InterpolationCheck
    end

    context "when the file includes an eval statement" do
      context "with File.read" do
        let(:file_body) do
          'eval File.read(File.expand_path("some_other_file.rb", __dir__))'
        end

        it { is_expected.to eq(["some_other_file.rb"]) }
      end

      context "when the eval does not read a file" do
        let(:file_body) do
          'eval "puts \'Hello, world!\'"'
        end

        it { is_expected.to eq([]) }
      end
    end
  end
end
