# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_parsers/base"

RSpec.describe Dependabot::FileParsers::Base do
  let(:package_manager_instance) { nil } # Default value

  let(:child_class) do
    pm_instance = package_manager_instance

    Class.new(described_class) do
      define_method(:check_required_files) do
        %w(Gemfile).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      define_method(:parse) { [] }

      define_method(:package_manager) { pm_instance }
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

  let(:concrete_package_manager_class) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize
        detected_version = "1.0.0"
        raw_version = "1.0.0"
        super(
          "bundler", # name
          Dependabot::Version.new(detected_version), # version
          Dependabot::Version.new(raw_version), # version
          [Dependabot::Version.new("1.0.0")], # deprecated_versions
          [Dependabot::Version.new("1.1.0"), Dependabot::Version.new("2.0.0")] # supported_versions
        )
      end

      def support_later_versions?
        true
      end
    end
  end

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

  describe "#package_manager" do
    context "when called on the base class" do
      it "returns nil" do
        expect(parser_instance.package_manager).to be_nil
      end
    end

    context "when called on a concrete class" do
      let(:package_manager_instance) { concrete_package_manager_class.new }

      it "returns an instance of Ecosystem::VersionManager" do
        expect(parser_instance.package_manager).to be_a(Dependabot::Ecosystem::VersionManager)
      end

      it "returns the correct package manager details" do
        pm = parser_instance.package_manager
        expect(pm.name).to eq("bundler")
        expect(pm.version).to eq(Dependabot::Version.new("1.0.0"))
        expect(pm.deprecated_versions).to eq([Dependabot::Version.new("1.0.0")])
        expect(pm.supported_versions).to eq([Dependabot::Version.new("1.1.0"), Dependabot::Version.new("2.0.0")])
        expect(pm.support_later_versions?).to be true
      end
    end
  end
end
