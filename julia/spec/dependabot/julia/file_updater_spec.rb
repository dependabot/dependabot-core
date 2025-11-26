# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia"

RSpec.describe Dependabot::Julia::FileUpdater do
  let(:project_file) do
    Dependabot::DependencyFile.new(
      name: "Project.toml",
      content: fixture("projects", "basic", "Project.toml")
    )
  end

  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "Manifest.toml",
      content: fixture("projects", "basic", "Manifest.toml")
    )
  end

  describe "#updated_dependency_files" do
    subject(:updater) do
      described_class.new(
        dependencies: [dependency],
        dependency_files: dependency_files,
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }]
      )
    end

    let(:dependency_files) { [project_file, manifest_file] }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "Example",
        version: "0.5.5",
        previous_version: "0.4.1",
        package_manager: "julia",
        requirements: [{
          requirement: "0.4, 0.5",
          file: "Project.toml",
          groups: ["deps"],
          source: nil
        }],
        previous_requirements: [{
          requirement: "0.4",
          file: "Project.toml",
          groups: ["deps"],
          source: nil
        }],
        metadata: { julia_uuid: "7876af07-990d-54b4-ab0e-23690620f79a" }
      )
    end

    it "updates dependency files" do
      updated_files = updater.updated_dependency_files
      expect(updated_files).not_to be_empty

      # Check that we get both Project.toml and Manifest.toml files back
      project_toml = updated_files.find { |f| f.name == "Project.toml" }
      manifest_toml = updated_files.find { |f| f.name == "Manifest.toml" }

      expect(project_toml).to be_a(Dependabot::DependencyFile)
      expect(manifest_toml).to be_a(Dependabot::DependencyFile)

      # Check that Project.toml has the updated requirement
      expect(project_toml.content).to include('Example = "0.4, 0.5"')

      # Check that Manifest.toml has the updated version
      expect(manifest_toml.content).to include('version = "0.5.5"')
    end

    context "when only Project.toml exists" do
      let(:dependency_files) { [project_file] }

      it "updates only Project.toml" do
        updated_files = updater.updated_dependency_files
        expect(updated_files.length).to eq(1)

        project_toml = updated_files.first
        expect(project_toml.name).to eq("Project.toml")
        expect(project_toml.content).to include('Example = "0.4, 0.5"')
      end
    end

    context "when preserving UUID in [deps] section" do
      let(:project_file_content) do
        <<~TOML
          name = "TestProject"
          uuid = "1234e567-e89b-12d3-a456-789012345678"
          version = "0.1.0"

          [deps]
          Example = "7876af07-990d-54b4-ab0e-23690620f79a"
          StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"

          [compat]
          Example = "0.4"
          StatsBase = "0.34.6"
          julia = "1.10"
        TOML
      end

      let(:project_file) do
        Dependabot::DependencyFile.new(
          name: "Project.toml",
          content: project_file_content
        )
      end

      let(:dependency_files) { [project_file] }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "StatsBase",
          version: "0.35.0",
          previous_version: "0.34.6",
          package_manager: "julia",
          requirements: [{
            requirement: "0.34.6, 0.35",
            file: "Project.toml",
            groups: ["deps"],
            source: nil
          }],
          previous_requirements: [{
            requirement: "0.34.6",
            file: "Project.toml",
            groups: ["deps"],
            source: nil
          }],
          metadata: { julia_uuid: "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91" }
        )
      end

      it "preserves UUID in [deps] section" do
        updated_files = updater.updated_dependency_files
        project_toml = updated_files.first

        # UUID in [deps] section should remain unchanged
        expect(project_toml.content).to include('StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"')
        # But compat entry should be updated
        expect(project_toml.content).to match(/\[compat\].*StatsBase = "0.34.6, 0.35"/m)
        # Make sure UUID wasn't replaced with version in [deps] section
        deps_section = project_toml.content.match(/\[deps\](.*?)\[compat\]/m)[1]
        expect(deps_section).not_to match(/StatsBase\s*=\s*"0\./)
      end

      it "updates only the [compat] section" do
        updated_files = updater.updated_dependency_files
        project_toml = updated_files.first

        # Count occurrences of StatsBase
        deps_match = project_toml.content.match(/\[deps\].*?(StatsBase\s*=\s*"[^"]+").*?\[compat\]/m)
        compat_match = project_toml.content.match(/\[compat\].*?(StatsBase\s*=\s*"[^"]+").*?(?:\z|\[)/m)

        # [deps] should have UUID
        expect(deps_match[1]).to include("2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91")
        # [compat] should have version spec
        expect(compat_match[1]).to include("0.34.6, 0.35")
      end
    end
  end

  describe "#updated_files_with_julia_helper" do
    subject(:updater) do
      described_class.new(
        dependencies: [dependency],
        dependency_files: dependency_files,
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }]
      )
    end

    let(:dependency_files) { [project_file, manifest_file] }
    let(:registry_client_double) { instance_double(Dependabot::Julia::RegistryClient) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "JSON",
        version: "1.2.0",
        previous_version: "0.21.0",
        package_manager: "julia",
        requirements: [{
          requirement: "0.21, 1.2",
          file: "Project.toml",
          groups: ["deps"],
          source: nil
        }],
        previous_requirements: [{
          requirement: "0.21",
          file: "Project.toml",
          groups: ["deps"],
          source: nil
        }],
        metadata: { julia_uuid: "682c06a0-de6a-54ab-a142-c8b1cf79cde6" }
      )
    end

    before do
      allow(Dependabot::Julia::RegistryClient).to receive(:new).and_return(registry_client_double)
    end

    context "when Julia helper successfully updates manifest" do
      let(:updated_manifest_content) do
        <<~TOML
          # This file is machine-generated
          [[deps.JSON]]
          version = "1.2.0"
        TOML
      end

      before do
        allow(registry_client_double).to receive(:update_manifest).and_return(
          {
            "manifest_content" => updated_manifest_content,
            "manifest_path" => "Manifest.toml"
          }
        )
      end

      it "returns both updated Project.toml and Manifest.toml" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.length).to eq(2)

        project = updated_files.find { |f| f.name == "Project.toml" }
        manifest = updated_files.find { |f| f.name == "Manifest.toml" }

        expect(project).not_to be_nil
        expect(manifest).not_to be_nil
        expect(manifest.content).to include('version = "1.2.0"')
      end
    end

    context "when workspace has manifest in parent directory" do
      let(:project_file) do
        Dependabot::DependencyFile.new(
          name: "Project.toml",
          content: fixture("projects", "basic", "Project.toml"),
          directory: "/SubPackage"
        )
      end

      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Manifest.toml",
          content: fixture("projects", "basic", "Manifest.toml"),
          directory: "/"
        )
      end

      let(:updated_manifest_content) do
        <<~TOML
          # This file is machine-generated
          [[deps.JSON]]
          version = "1.2.0"
        TOML
      end

      before do
        allow(registry_client_double).to receive(:update_manifest).and_return(
          {
            "manifest_content" => updated_manifest_content,
            "manifest_path" => "../Manifest.toml"
          }
        )
      end

      it "handles relative manifest path from workspace" do
        updated_files = updater.updated_dependency_files

        manifest = updated_files.find { |f| f.name == "../Manifest.toml" }
        expect(manifest).not_to be_nil
        expect(manifest.content).to include('version = "1.2.0"')
      end
    end

    context "when manifest has version-specific name" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Manifest-v1.12.toml",
          content: fixture("projects", "basic", "Manifest.toml")
        )
      end

      let(:updated_manifest_content) do
        <<~TOML
          # This file is machine-generated
          [[deps.JSON]]
          version = "1.2.0"
        TOML
      end

      before do
        allow(registry_client_double).to receive(:update_manifest).and_return(
          {
            "manifest_content" => updated_manifest_content,
            "manifest_path" => "Manifest-v1.12.toml"
          }
        )
      end

      it "updates version-specific manifest correctly" do
        updated_files = updater.updated_dependency_files

        manifest = updated_files.find { |f| f.name == "Manifest-v1.12.toml" }
        expect(manifest).not_to be_nil
        expect(manifest.content).to include('version = "1.2.0"')
      end
    end

    context "when Julia helper returns a resolver error" do
      before do
        allow(registry_client_double).to receive(:update_manifest).and_return(
          {
            "error" => "Unsatisfiable requirements detected for package JSON"
          }
        )
      end

      it "adds a notice and returns updated Project.toml only" do
        updated_files = updater.updated_dependency_files

        # Check that only Project.toml is updated
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.name).to eq("Project.toml")

        # Check that a notice was added
        expect(updater.notices.length).to eq(1)
        notice = updater.notices.first
        expect(notice.mode).to eq(Dependabot::Notice::NoticeMode::WARN)
        expect(notice.type).to eq("julia_manifest_not_updated")
        expect(notice.show_in_pr).to be true
        expect(notice.description).to include("Manifest.toml")
        expect(notice.description).to include("Unsatisfiable requirements")
      end
    end

    context "when adding a new compat entry to existing [compat] section" do
      let(:project_file_content) do
        <<~TOML
          name = "TestProject"
          uuid = "1234e567-e89b-12d3-a456-789012345678"
          version = "0.1.0"

          [deps]
          Aqua = "4c88cf16-eb10-579e-8560-4a9242c79595"
          CUDA = "052768ef-5323-5732-b1bb-66c8b64840ba"
          Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

          [compat]
          Aqua = "0.8"
          CUDA = "5"
          julia = "1.10"
        TOML
      end

      let(:project_file) do
        Dependabot::DependencyFile.new(
          name: "Project.toml",
          content: project_file_content
        )
      end

      let(:dependency_files) { [project_file] }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Statistics",
          version: "1.11.1",
          previous_version: nil,
          package_manager: "julia",
          requirements: [{
            requirement: "<0.0.1, 1",
            file: "Project.toml",
            groups: ["deps"],
            source: nil
          }],
          previous_requirements: [],
          metadata: { julia_uuid: "10745b16-79ce-11e8-11f9-7d13ad32a3b2" }
        )
      end

      it "inserts the new entry in alphabetical order" do
        updated_files = updater.updated_dependency_files
        project_toml = updated_files.first

        compat_section = project_toml.content.match(/\[compat\]\n(.*?)(?:\n\[|\z)/m)[1]
        lines = compat_section.split("\n").reject(&:empty?)

        expect(lines[0]).to include("Aqua")
        expect(lines[1]).to include("CUDA")
        expect(lines[2]).to include("Statistics")
        expect(lines[3]).to include("julia")
      end

      it "maintains alphabetical order when adding entry at the beginning" do
        dependency = Dependabot::Dependency.new(
          name: "Statistics",
          version: "1.11.1",
          previous_version: nil,
          package_manager: "julia",
          requirements: [{
            requirement: "<0.0.1, 1",
            file: "Project.toml",
            groups: ["deps"],
            source: nil
          }],
          previous_requirements: [],
          metadata: { julia_uuid: "10745b16-79ce-11e8-11f9-7d13ad32a3b2" }
        )

        updater = described_class.new(
          dependencies: [dependency],
          dependency_files: dependency_files,
          credentials: [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        )

        updated_files = updater.updated_dependency_files
        project_toml = updated_files.first

        compat_section = project_toml.content.match(/\[compat\]\n(.*?)(?:\n\[|\z)/m)[1]
        entry_names = compat_section.scan(/^([A-Za-z_]+)\s*=/).flatten

        expect(entry_names).to eq(%w(Aqua CUDA Statistics julia))
      end
    end
  end

  describe "#manifest_file_for_path" do
    subject(:updater) do
      described_class.new(
        dependencies: [],
        dependency_files: dependency_files,
        credentials: [{
          "type" => "git_source",
          "host" => "github.com"
        }]
      )
    end

    let(:dependency_files) { [project_file, manifest_file] }

    context "when manifest path matches originally fetched file" do
      it "returns the original manifest file" do
        result = updater.send(:manifest_file_for_path, "Manifest.toml")

        expect(result).to eq(manifest_file)
      end
    end

    context "when manifest path is different (workspace case)" do
      it "creates new DependencyFile with correct path" do
        result = updater.send(:manifest_file_for_path, "../Manifest.toml")

        expect(result.name).to eq("../Manifest.toml")
        expect(result.directory).to eq(project_file.directory)
      end
    end

    context "when no manifest was originally fetched" do
      let(:dependency_files) { [project_file] }

      it "creates new DependencyFile for the path" do
        result = updater.send(:manifest_file_for_path, "Manifest.toml")

        expect(result.name).to eq("Manifest.toml")
        expect(result.directory).to eq(project_file.directory)
      end
    end
  end

  private

  def fixture(*path)
    File.read(File.join(__dir__, "..", "..", "fixtures", *path))
  end
end
