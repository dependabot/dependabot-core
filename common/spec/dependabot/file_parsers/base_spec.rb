# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_parsers/base"

RSpec.describe Dependabot::FileParsers::Base do
  let(:child_class) do
    Class.new(described_class) do
      def check_required_files
        %w(Gemfile).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end
    end
  end
  let(:parser_instance) do
    child_class.new(dependency_files: files, source: source)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      content: "a",
      name: "Gemfile",
      directory: "/path/to"
    )
  end
  let(:files) { [gemfile] }

  describe ".new" do
    context "when the required file is present" do
      let(:files) { [gemfile] }

      it "doesn't raise" do
        expect { parser_instance }.not_to raise_error
      end
    end

    context "when the required file is missing" do
      let(:files) { [] }

      it "raises" do
        expect { parser_instance }.to raise_error(/No Gemfile/)
      end
    end
  end

  describe "#get_original_file" do
    subject { parser_instance.send(:get_original_file, filename) }

    context "when the requested file is present" do
      let(:filename) { "Gemfile" }

      it { is_expected.to eq(gemfile) }
    end

    context "when the requested file is not present" do
      let(:filename) { "Unknown.file" }

      it { is_expected.to be_nil }
    end
  end
end
