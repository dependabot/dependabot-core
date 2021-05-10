# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_fetcher/require_relative_finder"

RSpec.describe Dependabot::Bundler::FileFetcher::RequireRelativeFinder do
  let(:finder) { described_class.new(file: file) }

  let(:file) do
    Dependabot::DependencyFile.new(content: file_body, name: file_name)
  end
  let(:file_name) { "Gemfile" }

  describe "#require_relative_paths" do
    subject(:require_relative_paths) { finder.require_relative_paths }

    context "when the file does not include any relative paths" do
      let(:file_body) { bundler_project_dependency_file("gemfile", filename: "Gemfile").content }
      it { is_expected.to eq([]) }
    end

    context "with invalid Ruby in the Gemfile" do
      let(:file_body) { bundler_project_dependency_file("invalid_ruby", filename: "Gemfile").content }

      it "raises a helpful error" do
        expect { finder.require_relative_paths }.to raise_error do |error|
          expect(error).to be_a(Dependabot::DependencyFileNotParseable)
          expect(error.file_name).to eq("Gemfile")
        end
      end
    end

    context "when the file does include a relative path" do
      let(:file_body) do
        bundler_project_dependency_file("includes_require_relative_gemfile", filename: "nested/Gemfile").content
      end

      it { is_expected.to eq(["../some_other_file.rb"]) }

      context "for a file that includes a .rb suffix" do
        let(:file_body) do
          'require_relative "../some_other_file.rb"'
        end
        it { is_expected.to eq(["../some_other_file.rb"]) }
      end

      # rubocop:disable Lint/InterpolationCheck
      context "that needs to be evaled" do
        let(:file_body) do
          'require_relative "./my_file_#{raise %(hell)}"'
        end
        it { is_expected.to eq([]) }

        context "but can't be" do
          let(:file_body) do
            'require_relative "./my_file_#{unknown_var}"'
          end
          it { is_expected.to eq([]) }
        end
      end
      # rubocop:enable Lint/InterpolationCheck

      context "for a file that is already nested" do
        let(:file_name) { "deeply/nested/Gemfile" }
        it { is_expected.to eq(["deeply/some_other_file.rb"]) }
      end
    end
  end
end
