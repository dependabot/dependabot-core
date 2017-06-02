# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency_file"

RSpec.describe Dependabot::DependencyFile do
  let(:file) { described_class.new(name: "Gemfile", content: "a") }

  describe "#path" do
    subject { file.path }

    context "without a directory specified" do
      it { is_expected.to eq("/Gemfile") }
    end

    context "with a directory specified" do
      let(:file) do
        described_class.new(name: "Gemfile", content: "a", directory: directory)
      end

      context "that starts and ends with a slash" do
        let(:directory) { "/path/to/files/" }
        it { is_expected.to eq("/path/to/files/Gemfile") }
      end

      context "that doesn't start or end with a slash" do
        let(:directory) { "path/to/files" }
        it { is_expected.to eq("/path/to/files/Gemfile") }
      end
    end
  end

  describe "#directory" do
    subject { file.directory }

    context "without a directory specified" do
      it { is_expected.to eq("/") }
    end

    context "with a directory specified" do
      let(:file) do
        described_class.new(name: "Gemfile", content: "a", directory: directory)
      end

      context "that starts and ends with a slash" do
        let(:directory) { "/path/to/files" }
        it { is_expected.to eq("/path/to/files") }
      end

      context "that doesn't start or end with a slash" do
        let(:directory) { "path/to/files" }
        it { is_expected.to eq("/path/to/files") }
      end
    end
  end
end
