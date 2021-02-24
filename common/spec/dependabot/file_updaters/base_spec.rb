# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/base"

RSpec.describe Dependabot::FileUpdaters::Base do
  let(:child_class) do
    Class.new(described_class) do
      def check_required_files
        %w(Gemfile).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end
    end
  end
  let(:updater_instance) do
    child_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com"
      }],
      source: source,
    )
  end
  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump")}

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      content: "a",
      name: "Gemfile",
      directory: "/path/to"
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      package_manager: "bundler",
      requirements:
        [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
    )
  end
  let(:files) { [gemfile] }

  describe ".new" do
    subject { -> { updater_instance } }

    context "when the required file is present" do
      let(:files) { [gemfile] }

      it "doesn't raise" do
        expect { updater_instance }.to_not raise_error
      end
    end

    context "when the required file is missing" do
      let(:files) { [] }

      it "raises" do
        expect { updater_instance }.to raise_error(/No Gemfile/)
      end
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

    it { is_expected.to be_a(Dependabot::DependencyFile) }
    its(:content) { is_expected.to eq("codes") }
    its(:directory) { is_expected.to eq(file.directory) }

    specify { expect { updated_file }.to_not(change { file.content }) }
  end

  describe "#pr_message" do
    subject(:message) { updater_instance.pr_message }

    before do
      allow(updater_instance).to receive(:updated_dependency_files).and_return([])
      allow(::Dependabot::PullRequestCreator::MessageBuilder).
        to receive(:new).and_return(dummy_message_builder)
      allow(dummy_message_builder).to receive(:pr_name).and_return(pr_name)
    end
    let(:dummy_message_builder) { instance_double(Dependabot::PullRequestCreator::MessageBuilder) }
    let(:pr_name) { "PR name"}

    its(:pr_name) { should eq(pr_name) }
  end
end
