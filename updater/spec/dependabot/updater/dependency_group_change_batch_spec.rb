# typed: false
# frozen_string_literal: true

require "dependabot/job"
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
        Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "../../oob"),
      ]
    end

    it "returns the current dependency files filtered by directory" do
      expect(described_class.new(initial_dependency_files: files).
        current_dependency_files('/').map { |f| f.name }).to eq(%w[Gemfile Gemfile.lock])
    end

    it "normalizes the directory" do
      expect(described_class.new(initial_dependency_files: files).
        current_dependency_files('/.').map { |f| f.name }).to eq(%w[Gemfile Gemfile.lock])

      expect(described_class.new(initial_dependency_files: files).
        current_dependency_files('/hello/..').map { |f| f.name }).to eq(%w[Gemfile Gemfile.lock])
    end

  end
end
