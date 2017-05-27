# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/dependency_file_updaters/base"

RSpec.describe Bump::DependencyFileUpdaters::Base do
  let(:child_class) do
    Class.new(described_class) do
      def required_files
        ["Gemfile"]
      end
    end
  end
  let(:updater_instance) do
    child_class.new(
      dependency_files: files,
      dependency: dependency,
      github_access_token: github_access_token
    )
  end

  let(:gemfile) do
    Bump::DependencyFile.new(
      content: "a",
      name: "Gemfile",
      directory: "/path/to"
    )
  end
  let(:dependency) do
    Bump::Dependency.new(
      name: "business",
      version: "1.5.0",
      package_manager: "bundler"
    )
  end
  let(:github_access_token) { "token" }
  let(:files) { [gemfile] }

  describe ".new" do
    subject { -> { updater_instance } }

    context "when the required file is present" do
      let(:files) { [gemfile] }
      it { is_expected.to_not raise_error }
    end

    context "when the required file is missing" do
      let(:files) { [] }
      it { is_expected.to raise_error(/No Gemfile/) }
    end
  end

  describe "#get_original_file" do
    subject { updater_instance.send(:get_original_file, filename) }

    context "when the requested file is present" do
      let(:filename) { "Gemfile" }
      it { is_expected.to eq(gemfile) }
    end

    context "when the requested file is not present" do
      let(:filename) { "Unknown.file" }
      it { is_expected.to be_nil }
    end
  end

  describe "#updated_file" do
    subject(:updated_file) do
      updater_instance.send(:updated_file, file: file, content: content)
    end
    let(:file) { gemfile }
    let(:content) { "codes" }

    it { is_expected.to be_a(Bump::DependencyFile) }
    its(:content) { is_expected.to eq("codes") }
    its(:directory) { is_expected.to eq(file.directory) }

    specify { expect { updated_file }.to_not(change { file.content }) }
  end
end
