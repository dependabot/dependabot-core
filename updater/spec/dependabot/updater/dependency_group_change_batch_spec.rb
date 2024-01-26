# typed: false
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/job"
require "dependabot/source"
require "dependabot/updater/operations"

require "spec_helper"

RSpec.describe Dependabot::Updater::DependencyGroupChangeBatch do
  describe "current_dependency_files" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-gemfile", directory: "/"),
        Dependabot::DependencyFile.new(name: "Gemfile.lock", content: "mock-gemfile-lock", directory: "/hello/.."),
        Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "/elsewhere"),
        Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "unknown"),
        Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "../../oob")
      ]
    end

    let(:job) do
      instance_double(Dependabot::Job, source: source, package_manager: package_manager)
    end

    let(:package_manager) { "bundler" }

    let(:source) do
      Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: directory)
    end

    let(:directory) { "/" }

    it "returns the current dependency files filtered by directory" do
      expect(described_class.new(initial_dependency_files: files)
        .current_dependency_files(job).map(&:name)).to eq(%w(Gemfile Gemfile.lock))
    end

    context "when the directory has a dot" do
      let(:directory) { "/." }

      it "normalizes the directory" do
        expect(described_class.new(initial_dependency_files: files)
          .current_dependency_files(job).map(&:name)).to eq(%w(Gemfile Gemfile.lock))
      end
    end

    context "when the directory has a dot dot" do
      let(:directory) { "/hello/.." }

      it "normalizes the directory" do
        expect(described_class.new(initial_dependency_files: files)
          .current_dependency_files(job).map(&:name)).to eq(%w(Gemfile Gemfile.lock))
      end
    end
  end
end
