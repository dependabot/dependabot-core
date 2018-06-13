# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_fetchers/ruby/bundler/require_relative_finder"

RSpec.describe Dependabot::FileFetchers::Ruby::Bundler::RequireRelativeFinder do
  let(:finder) { described_class.new(file: file) }

  let(:file) do
    Dependabot::DependencyFile.new(content: file_body, name: file_name)
  end
  let(:file_name) { "Gemfile" }
  let(:file_body) { fixture("ruby", "gemfiles", "includes_require_relative") }

  describe "#require_relative_paths" do
    subject(:require_relative_paths) { finder.require_relative_paths }

    context "when the file does not include any relative paths" do
      let(:file_body) { fixture("ruby", "gemfiles", "Gemfile") }
      it { is_expected.to eq([]) }
    end

    context "with invalid Ruby in the Gemfile" do
      let(:file_body) { fixture("ruby", "gemfiles", "invalid_ruby") }

      it "raises a helpful error" do
        expect { finder.require_relative_paths }.to raise_error do |error|
          expect(error).to be_a(Dependabot::DependencyFileNotParseable)
          expect(error.file_name).to eq("Gemfile")
        end
      end
    end

    context "when the file does include a relative path" do
      let(:file_body) do
        fixture("ruby", "gemfiles", "includes_require_relative")
      end

      it { is_expected.to eq(["../some_other_file.rb"]) }

      # rubocop:disable Lint/InterpolationCheck
      context "that needs to be evaled" do
        let(:file_body) { 'require_relative "./my_file_#{1+1}"' }
        it { is_expected.to eq(["my_file_2.rb"]) }

        context "but can't be" do
          let(:file_body) { 'require_relative "./my_file_#{unknown_var}"' }
          it { is_expected.to eq([]) }
        end
      end
      # rubocop:enable Lint/InterpolationCheck
    end
  end
end
