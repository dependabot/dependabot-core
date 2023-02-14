# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/bundler/file_updater/lockfile_updater"

RSpec.describe Dependabot::Bundler::FileUpdater::LockfileUpdater do
  include_context "stub rubygems compact index"

  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      dependency_files: [gemspec, other_gemspec, gemfile, lockfile],
      options: {},
      credentials: []
    )
  end
  let(:gemspec) do
    bundler_project_dependency_file("multiple_path_gems", filename: "vendor/net-imap/net-imap.gemspec")
  end
  let(:other_gemspec) do
    bundler_project_dependency_file("multiple_path_gems", filename: "vendor/couchrb/couchrb.gemspec")
  end
  let(:gemfile) do
    bundler_project_dependency_file("multiple_path_gems", filename: "Gemfile")
  end
  let(:lockfile) do
    bundler_project_dependency_file("multiple_path_gems", filename: "Gemfile.lock")
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "ice_nine",
      version: "0.11.2",
      previous_version: "0.11.1",
      requirements: [],
      previous_requirements: [],
      package_manager: "bundler"
    )
  end

  describe "#updated_lockfile_content" do
    let(:updated_lockfile_content) { updater.updated_lockfile_content }

    it "upgrades dependency" do
      expect(updated_lockfile_content).to  include("ice_nine (0.11.2)")
    end

    it "keeps correct versions of path dependencies" do
      expect(updated_lockfile_content).to  include("couchrb (0.9.0)")
      expect(updated_lockfile_content).to  include("net-imap (0.3.3)")
    end
  end
end
