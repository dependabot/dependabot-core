# typed: false
# frozen_string_literal: true

require "dependabot/dependency_snapshot"
require "dependabot/dependency_file"
require "dependabot/job"
require "dependabot/source"
require "dependabot/dependency_group"
require "spec_helper"

RSpec.describe Dependabot::DependencySnapshot, "Enhanced Handled Dependencies" do
  let(:job) do
    instance_double(
      Dependabot::Job,
      package_manager: "bundler",
      security_updates_only?: false,
      repo_contents_path: nil,
      credentials: [],
      reject_external_code?: false,
      source: source,
      dependency_groups: dependency_groups,
      allowed_update?: true,
      dependency_group_to_refresh: nil,
      dependencies: nil,
      experiments: { group_membership_enforcement: group_enforcement_enabled }
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "test/repo",
      directory: "/"
    )
  end

  let(:dependency_groups) do
    [
      Dependabot::DependencyGroup.new(
        name: "backend",
        rules: { "patterns" => ["rails*", "pg"] }
      )
    ]
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: "source 'https://rubygems.org'\ngem 'rails'\ngem 'pg'",
        directory: "/"
      )
    ]
  end

  let(:job_definition) do
    {
      "base_commit_sha" => "abc123",
      "base64_dependency_files" => encode_dependency_files(dependency_files)
    }
  end

  let(:group_enforcement_enabled) { true }

  def encode_dependency_files(files)
    files.map do |file|
      {
        "name" => file.name,
        "content" => Base64.encode64(file.content),
        "directory" => file.directory
      }
    end
  end

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:group_membership_enforcement).and_return(group_enforcement_enabled)
    allow(Dependabot::FileParsers).to receive(:for_package_manager)
      .and_return(double(new: double(parse: [])))
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#add_handled_dependencies_with_group" do
    let(:snapshot) do
      described_class.create_from_job_definition(
        job: job,
        job_definition: job_definition
      )
    end

    context "when group membership enforcement is enabled" do
      let(:group_enforcement_enabled) { true }

      it "adds dependencies to both traditional and enhanced tracking" do
        snapshot.add_handled_dependencies_with_group(%w(rails pg), "backend")

        # Traditional tracking
        expect(snapshot.handled_dependencies).to include("rails", "pg")

        # Enhanced tracking
        expect(snapshot.dependency_handled_with_group?("rails", "backend")).to be true
        expect(snapshot.dependency_handled_with_group?("pg", "backend")).to be true
      end

      it "tracks dependencies with group and directory context" do
        snapshot.current_directory = "/api"
        snapshot.add_handled_dependencies_with_group("rails", "backend")

        expect(snapshot.dependency_handled_with_group?("rails", "backend")).to be true

        # Different directory should not be handled
        snapshot.current_directory = "/web"
        expect(snapshot.dependency_handled_with_group?("rails", "backend")).to be false
      end

      it "handles arrays of dependency names" do
        dependencies = %w(rails pg sidekiq)
        snapshot.add_handled_dependencies_with_group(dependencies, "backend")

        dependencies.each do |dep|
          expect(snapshot.dependency_handled_with_group?(dep, "backend")).to be true
        end
      end

      it "logs enhanced tracking information" do
        expect(Dependabot.logger).to receive(:debug)
          .with("Enhanced tracking: [backend, /, rails]")

        snapshot.add_handled_dependencies_with_group("rails", "backend")
      end
    end

    context "when group membership enforcement is disabled" do
      let(:group_enforcement_enabled) { false }

      it "only adds to traditional tracking" do
        snapshot.add_handled_dependencies_with_group(%w(rails pg), "backend")

        # Traditional tracking should work
        expect(snapshot.handled_dependencies).to include("rails", "pg")

        # Enhanced tracking should fall back to traditional
        expect(snapshot.dependency_handled_with_group?("rails", "backend")).to be true
        expect(snapshot.dependency_handled_with_group?("pg", "backend")).to be true
      end
    end

    context "when group_name is nil" do
      it "only adds to traditional tracking" do
        snapshot.add_handled_dependencies_with_group(["rails"], nil)

        expect(snapshot.handled_dependencies).to include("rails")
        expect(snapshot.dependency_handled_with_group?("rails")).to be true
      end
    end
  end

  describe "#dependency_handled_with_group?" do
    let(:snapshot) do
      described_class.create_from_job_definition(
        job: job,
        job_definition: job_definition
      )
    end

    context "when group membership enforcement is enabled" do
      let(:group_enforcement_enabled) { true }

      before do
        snapshot.add_handled_dependencies_with_group("rails", "backend")
      end

      it "returns true for handled dependencies with matching group" do
        expect(snapshot.dependency_handled_with_group?("rails", "backend")).to be true
      end

      it "returns false for handled dependencies with different group" do
        expect(snapshot.dependency_handled_with_group?("rails", "frontend")).to be false
      end

      it "returns false for unhandled dependencies" do
        expect(snapshot.dependency_handled_with_group?("sidekiq", "backend")).to be false
      end

      it "falls back to traditional tracking when group_name is nil" do
        expect(snapshot.dependency_handled_with_group?("rails")).to be true
      end
    end

    context "when group membership enforcement is disabled" do
      let(:group_enforcement_enabled) { false }

      before do
        snapshot.add_handled_dependencies(["rails"])
      end

      it "falls back to traditional tracking regardless of group" do
        expect(snapshot.dependency_handled_with_group?("rails", "backend")).to be true
        expect(snapshot.dependency_handled_with_group?("rails", "frontend")).to be true
      end
    end
  end

  describe "multi-directory handling" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: "gem 'rails'",
          directory: "/api"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: "gem 'rails'",
          directory: "/web"
        )
      ]
    end

    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "test/repo",
        directories: ["/api", "/web"]
      )
    end

    let(:snapshot) do
      described_class.create_from_job_definition(
        job: job,
        job_definition: job_definition
      )
    end

    it "tracks dependencies per directory with group context" do
      # Handle rails in api directory for backend group
      snapshot.current_directory = "/api"
      snapshot.add_handled_dependencies_with_group("rails", "backend")

      # Handle rails in web directory for frontend group
      snapshot.current_directory = "/web"
      snapshot.add_handled_dependencies_with_group("rails", "frontend")

      # Verify directory-specific tracking
      snapshot.current_directory = "/api"
      expect(snapshot.dependency_handled_with_group?("rails", "backend")).to be true
      expect(snapshot.dependency_handled_with_group?("rails", "frontend")).to be false

      snapshot.current_directory = "/web"
      expect(snapshot.dependency_handled_with_group?("rails", "backend")).to be false
      expect(snapshot.dependency_handled_with_group?("rails", "frontend")).to be true
    end
  end
end
