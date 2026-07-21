# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/julia/file_parser"

RSpec.describe Dependabot::Julia::FileParser do
  describe "#parse with actual fixtures" do
    subject(:dependencies) { parser.parse }

    let(:parser) do
      described_class.new(
        dependency_files: dependency_files,
        source: source,
        credentials: credentials
      )
    end

    let(:dependency_files) { [project_file, manifest_file] }
    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "test/test",
        directory: "/"
      )
    end
    let(:credentials) { [] }

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

    it "parses dependencies correctly" do
      expect(dependencies.length).to eq(1)

      example_dep = dependencies.find { |d| d.name == "Example" }
      expect(example_dep).to be_a(Dependabot::Dependency)
      expect(example_dep.name).to eq("Example")
      expect(example_dep.version).to eq("0.4.1") # Installed version from Manifest.toml
      expect(example_dep.package_manager).to eq("julia")

      requirement = example_dep.requirements.first
      expect(requirement.requirement).to eq("0.4")
      expect(requirement.file).to eq("Project.toml")
      expect(requirement.groups).to eq(["deps"])
    end

    context "when only Project.toml exists (no Manifest.toml)" do
      let(:dependency_files) { [project_file] }

      it "parses dependencies without exact versions" do
        expect(dependencies.length).to eq(1)

        example_dep = dependencies.find { |d| d.name == "Example" }
        expect(example_dep.name).to eq("Example")
        expect(example_dep.version).to be_nil # No Manifest.toml to get exact version
        expect(example_dep.requirements.first.requirement).to eq("0.4")
      end
    end

    context "when project has extras/test dependencies" do
      let(:project_file) do
        Dependabot::DependencyFile.new(
          name: "Project.toml",
          content: fixture("projects", "with_extras", "Project.toml")
        )
      end

      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Manifest.toml",
          content: fixture("projects", "with_extras", "Manifest.toml")
        )
      end

      it "parses runtime and weak dependencies (matching CompatHelper.jl)" do
        # CompatHelper.jl only processes [deps] and [weakdeps], not [extras]
        expect(dependencies.length).to eq(2) # Example (deps), JSON (weakdeps)

        # deps dependency
        example_dep = dependencies.find { |d| d.name == "Example" }
        expect(example_dep).to be_a(Dependabot::Dependency)
        expect(example_dep.name).to eq("Example")
        expect(example_dep.version).to eq("0.4.1") # Installed version from Manifest.toml
        expect(example_dep.requirements.first.groups).to eq(["deps"])
        expect(example_dep.requirements.first.requirement).to eq("0.4")

        # Weak dependency with compat entry
        json_dep = dependencies.find { |d| d.name == "JSON" }
        expect(json_dep).to be_a(Dependabot::Dependency)
        expect(json_dep.name).to eq("JSON")
        expect(json_dep.version).to eq("0.21.4") # Weakdeps also get manifest versions
        expect(json_dep.requirements.first.groups).to eq(["weakdeps"])
        expect(json_dep.requirements.first.requirement).to eq("0.21")
      end
    end

    context "when a project file name contains ../ (workspace root from member dir)" do
      let(:dependency_files) { [parent_project_file] }
      let(:parent_project_file) do
        Dependabot::DependencyFile.new(
          name: "../Project.toml",
          directory: "/docs",
          content: fixture("projects", "basic", "Project.toml")
        )
      end

      it "parses without writing outside the temp directory" do
        expect(dependencies.map(&:name)).to eq(["Example"])
      end
    end

    context "when two project files declare the same name with different UUIDs" do
      let(:dependency_files) { [project_file, conflicting_project_file] }
      let(:conflicting_project_file) do
        Dependabot::DependencyFile.new(
          name: "sub/Project.toml",
          content: <<~TOML
            name = "SubProject"
            uuid = "9999e567-e89b-12d3-a456-789012345678"
            version = "0.1.0"

            [deps]
            Example = "00000000-1111-2222-3333-444444444444"

            [compat]
            Example = "2"
          TOML
        )
      end

      it "keeps the first package and does not merge the conflicting UUID" do
        example_dep = dependencies.find { |d| d.name == "Example" }
        expect(example_dep.metadata[:julia_uuid]).to eq("7876af07-990d-54b4-ab0e-23690620f79a")
        expect(example_dep.requirements.length).to eq(1)
      end
    end

    describe "#ecosystem" do
      it "returns the Julia ecosystem with package manager and language" do
        ecosystem = parser.ecosystem

        expect(ecosystem.name).to eq("julia")
        expect(ecosystem.package_manager.name).to eq("julia")
        expect(ecosystem.language.name).to eq("julia")
      end
    end

    context "when workspace has multiple Project.toml files with same dependency" do
      # This tests issue #13865: Julia: dependabot only updates top-level Project.toml
      # if workspaces have different compat specifiers
      let(:main_project_file) do
        Dependabot::DependencyFile.new(
          name: "Project.toml",
          content: fixture("projects", "workspace_different_compat", "Project.toml")
        )
      end

      let(:docs_project_file) do
        Dependabot::DependencyFile.new(
          name: "docs/Project.toml",
          content: fixture("projects", "workspace_different_compat", "docs", "Project.toml")
        )
      end

      let(:test_project_file) do
        Dependabot::DependencyFile.new(
          name: "test/Project.toml",
          content: fixture("projects", "workspace_different_compat", "test", "Project.toml")
        )
      end

      let(:workspace_manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Manifest.toml",
          content: fixture("projects", "workspace_different_compat", "Manifest.toml")
        )
      end

      let(:dependency_files) do
        [main_project_file, docs_project_file, test_project_file, workspace_manifest_file]
      end

      it "parses dependencies from all Project.toml files" do
        json_dep = dependencies.find { |d| d.name == "JSON" }
        expect(json_dep).not_to be_nil

        # Should have requirements from all 3 Project.toml files
        expect(json_dep.requirements.length).to eq(3)

        # Verify requirements point to the correct files
        main_req = json_dep.requirements.find { |r| r.file == "Project.toml" }
        expect(main_req).not_to be_nil
        expect(main_req.requirement).to eq("0.21.4")

        docs_req = json_dep.requirements.find { |r| r.file == "docs/Project.toml" }
        expect(docs_req).not_to be_nil
        expect(docs_req.requirement).to eq("0.21")

        test_req = json_dep.requirements.find { |r| r.file == "test/Project.toml" }
        expect(test_req).not_to be_nil
        expect(test_req.requirement).to eq("0.21")
      end

      it "parses dependencies unique to specific Project.toml files" do
        # Documenter should only be in docs/Project.toml
        documenter_dep = dependencies.find { |d| d.name == "Documenter" }
        expect(documenter_dep).not_to be_nil
        expect(documenter_dep.requirements.length).to eq(1)
        expect(documenter_dep.requirements.first.file).to eq("docs/Project.toml")
        expect(documenter_dep.requirements.first.requirement).to eq("1")

        # Test should only be in test/Project.toml (but has no compat entry)
        test_dep = dependencies.find { |d| d.name == "Test" }
        expect(test_dep).not_to be_nil
        expect(test_dep.requirements.length).to eq(1)
        expect(test_dep.requirements.first.file).to eq("test/Project.toml")
        expect(test_dep.requirements.first.requirement).to be_nil # No compat entry
      end
    end
  end

  private

  def fixture(type, *names)
    File.read(File.join("spec", "fixtures", type, *names))
  end
end
