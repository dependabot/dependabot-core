# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_fetchers/ruby/bundler/gemspec_finder"

RSpec.describe Dependabot::FileFetchers::Ruby::Bundler::GemspecFinder do
  let(:finder) { described_class.new(gemfile: gemfile) }

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: gemfile_name)
  end
  let(:gemfile_name) { "Gemfile" }
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }

  describe "#gemspec_directories" do
    subject(:gemspec_directories) { finder.gemspec_directories }

    context "when the file does not include any gemspecs" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
      it { is_expected.to eq([]) }
    end

    context "with invalid Ruby in the Gemfile" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "invalid_ruby") }

      it "raises a helpful error" do
        expect { finder.gemspec_directories }.to raise_error do |error|
          expect(error).to be_a(Dependabot::DependencyFileNotParseable)
          expect(error.file_name).to eq("Gemfile")
        end
      end
    end

    context "when the file does include a gemspec reference" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "imports_gemspec") }
      it { is_expected.to eq([Pathname.new(".")]) }

      context "that has a path specified" do
        let(:gemfile_body) do
          fixture("ruby", "gemfiles", "imports_gemspec_from_path")
        end

        it { is_expected.to eq([Pathname.new("subdir")]) }

        context "when this Gemfile is already in a nested directory" do
          let(:gemfile_name) { "nested/Gemfile" }
          it { is_expected.to eq([Pathname.new("nested/subdir")]) }
        end
      end
    end
  end
end
