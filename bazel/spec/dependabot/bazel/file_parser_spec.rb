# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/bazel/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Bazel::FileParser do
  subject(:parser) do
    described_class.new(
      dependency_files: dependency_files,
      source: source
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/bazel-project",
      directory: "/"
    )
  end

  let(:dependency_files) { bazel_project_dependency_files("simple_module") }

  describe "#parse" do
    it "returns the expected dependencies" do
      dependencies = parser.parse

      expect(dependencies.length).to eq(3)

      expect(dependencies.map(&:name)).to contain_exactly(
        "rules_cc",
        "platforms",
        "abseil-cpp"
      )

      rules_cc_dep = dependencies.find { |d| d.name == "rules_cc" }
      expect(rules_cc_dep.version).to eq("0.1.1")
      expect(rules_cc_dep.package_manager).to eq("bazel")
      expect(rules_cc_dep.requirements.first[:file]).to eq("MODULE.bazel")
    end
  end

  describe "#ecosystem" do
    it "returns the Bazel ecosystem with package manager and language" do
      ecosystem = parser.ecosystem

      expect(ecosystem.name).to eq("bazel")
      expect(ecosystem.package_manager.name).to eq("bazel")
      expect(ecosystem.language.name).to eq("bazel")
    end

    context "with .bazelversion file" do
      let(:dependency_files) { bazel_project_dependency_files("with_bazelversion") }

      it "uses the detected Bazel version" do
        ecosystem = parser.ecosystem

        expect(ecosystem.package_manager.version.to_s).to eq("6.4.0")
        expect(ecosystem.language.version.to_s).to eq("6.4.0")
      end
    end

    context "without .bazelversion file" do
      it "uses the default version for detected_version" do
        ecosystem = parser.ecosystem

        expect(ecosystem.package_manager.detected_version.to_s).to eq("8.4.2")
        expect(ecosystem.package_manager.version).to be_nil
        expect(ecosystem.language.version.to_s).to eq("8.4.2")
      end
    end
  end

  context "with WORKSPACE file" do
    let(:dependency_files) { bazel_project_dependency_files("simple_workspace") }

    it "parses WORKSPACE dependencies" do
      dependencies = parser.parse

      expect(dependencies.length).to eq(2)
      expect(dependencies.map(&:name)).to contain_exactly("rules_cc", "abseil-cpp")

      rules_cc_dep = dependencies.find { |d| d.name == "rules_cc" }
      expect(rules_cc_dep.version).to eq("0.1.1")
    end
  end

  context "with BUILD file" do
    let(:dependency_files) { bazel_project_dependency_files("with_build_files") }

    it "parses load statements from BUILD files" do
      dependencies = parser.parse

      # Should include MODULE.bazel deps plus load references
      expect(dependencies.length).to be >= 3

      load_deps = dependencies.select { |d| d.requirements.any? { |req| req[:groups] == ["load_references"] } }
      expect(load_deps.map(&:name)).to include("rules_go", "rules_cc")
    end
  end

  context "with .bazelversion file" do
    let(:dependency_files) { bazel_project_dependency_files("with_bazelversion") }

    it "detects the Bazel version" do
      expect(parser.send(:bazel_version)).to eq("6.4.0")
    end
  end

  context "with *.MODULE.bazel files" do
    let(:dependency_files) { bazel_project_dependency_files("with_additional_module_files") }

    it "parses dependencies from both MODULE.bazel and *.MODULE.bazel files" do
      dependencies = parser.parse

      expect(dependencies.length).to eq(3)

      expect(dependencies.map(&:name)).to contain_exactly(
        "rules_cc",
        "platforms",
        "abseil-cpp"
      )

      # Dependency from main MODULE.bazel
      rules_cc_dep = dependencies.find { |d| d.name == "rules_cc" }
      expect(rules_cc_dep.version).to eq("0.1.1")
      expect(rules_cc_dep.requirements.first[:file]).to eq("MODULE.bazel")

      # Dependencies from deps.MODULE.bazel
      platforms_dep = dependencies.find { |d| d.name == "platforms" }
      expect(platforms_dep.version).to eq("0.0.11")
      expect(platforms_dep.requirements.first[:file]).to eq("deps.MODULE.bazel")

      abseil_dep = dependencies.find { |d| d.name == "abseil-cpp" }
      expect(abseil_dep.version).to eq("20230125.3")
      expect(abseil_dep.requirements.first[:file]).to eq("deps.MODULE.bazel")
    end
  end

  context "with complex MODULE.bazel file" do
    let(:dependency_files) { bazel_project_dependency_files("complex_module") }

    it "parses complex MODULE.bazel with various patterns" do
      dependencies = parser.parse

      expect(dependencies.length).to eq(5)

      # Check specific dependency details
      rules_cc = dependencies.find { |d| d.name == "rules_cc" }
      expect(rules_cc.version).to eq("0.1.1")
      expect(rules_cc.package_manager).to eq("bazel")

      platforms = dependencies.find { |d| d.name == "platforms" }
      expect(platforms.version).to eq("0.0.11")

      abseil = dependencies.find { |d| d.name == "abseil-cpp" }
      expect(abseil.version).to eq("20230125.3")

      rules_python = dependencies.find { |d| d.name == "rules_python" }
      expect(rules_python.version).to eq("0.25.0")

      rules_go = dependencies.find { |d| d.name == "rules_go" }
      expect(rules_go.version).to eq("0.39.1")
    end
  end

  context "with WORKSPACE.bazel file" do
    let(:dependency_files) { bazel_project_dependency_files("workspace_bazel_complex") }

    it "parses WORKSPACE.bazel with http_archive and git_repository" do
      dependencies = parser.parse

      expect(dependencies.length).to eq(3)

      rules_go = dependencies.find { |d| d.name == "rules_go" }
      expect(rules_go.version).to eq("0.41.0")
      expect(rules_go.package_manager).to eq("bazel")

      protobuf = dependencies.find { |d| d.name == "com_google_protobuf" }
      expect(protobuf.version).to eq("v3.19.4")

      rules_docker = dependencies.find { |d| d.name == "io_bazel_rules_docker" }
      expect(rules_docker.version).to eq("0.25.0")
    end

    it "captures remote URL from git_repository dependencies" do
      dependencies = parser.parse

      protobuf = dependencies.find { |d| d.name == "com_google_protobuf" }
      expect(protobuf).not_to be_nil

      requirement = protobuf.requirements.first
      expect(requirement[:source][:type]).to eq("git_repository")
      expect(requirement[:source][:tag]).to eq("v3.19.4")
      expect(requirement[:source][:remote]).to eq("https://github.com/protocolbuffers/protobuf")
    end

    it "captures URLs from http_archive dependencies" do
      dependencies = parser.parse

      rules_go = dependencies.find { |d| d.name == "rules_go" }
      expect(rules_go).not_to be_nil

      requirement = rules_go.requirements.first
      expect(requirement[:source][:type]).to eq("http_archive")
      expect(requirement[:source][:url]).to include("github.com/bazelbuild/rules_go")
    end
  end

  context "with BUILD.bazel file" do
    let(:dependency_files) { bazel_project_dependency_files("build_bazel_complex") }

    it "parses load statements from BUILD.bazel files" do
      dependencies = parser.parse

      # Should include MODULE.bazel deps plus load references
      load_deps = dependencies.select { |d| d.requirements.any? { |req| req[:groups] == ["load_references"] } }

      expect(load_deps.map(&:name)).to include("rules_go", "rules_cc", "io_bazel_rules_docker")

      rules_go_load = load_deps.find { |d| d.name == "rules_go" }
      expect(rules_go_load.requirements.first[:file]).to eq("BUILD.bazel")
    end
  end

  context "with multiple dependency files" do
    let(:dependency_files) { bazel_project_dependency_files("multiple_files") }

    it "combines dependencies from all file types" do
      dependencies = parser.parse

      # MODULE.bazel deps
      module_deps = dependencies.select { |d| d.requirements.first[:file] == "MODULE.bazel" }
      expect(module_deps.map(&:name)).to include("rules_cc", "platforms", "abseil-cpp")

      # WORKSPACE deps
      workspace_deps = dependencies.select { |d| d.requirements.first[:file] == "WORKSPACE" }
      expect(workspace_deps.map(&:name)).to include("rules_python")

      # BUILD load deps
      load_deps = dependencies.select { |d| d.requirements.any? { |req| req[:groups] == ["load_references"] } }
      expect(load_deps.map(&:name)).to include("rules_cc")

      # Bazel version detection
      expect(parser.send(:bazel_version)).to eq("6.4.0")
    end
  end

  context "with edge case content" do
    let(:dependency_files) { bazel_project_dependency_files("edge_case_formatting") }

    it "handles edge cases in formatting and content" do
      dependencies = parser.parse

      expect(dependencies.length).to eq(3)

      names = dependencies.map(&:name)
      expect(names).to contain_exactly("rules_cc", "platforms", "final_dep")

      versions = dependencies.map(&:version)
      expect(versions).to contain_exactly("0.1.1", "0.0.11", "1.0.0")
    end
  end

  context "with invalid or malformed content" do
    let(:dependency_files) { bazel_project_dependency_files("malformed_content") }

    it "recovers from parsing errors and continues" do
      dependencies = parser.parse

      # Should parse the valid dependencies despite malformed ones
      valid_names = dependencies.map(&:name)
      expect(valid_names).to include("good_dep")

      # May or may not include the dependencies after malformed ones depending on error recovery
      good_dep = dependencies.find { |d| d.name == "good_dep" }
      expect(good_dep.version).to eq("1.0.0")

      # Error recovery may successfully parse some dependencies after malformed content
      expect(valid_names.length).to be >= 1
    end
  end

  context "with empty files" do
    let(:dependency_files) { bazel_project_dependency_files("empty_file") }

    it "handles empty files gracefully" do
      dependencies = parser.parse
      expect(dependencies).to be_empty
    end
  end

  context "with files containing only comments" do
    let(:dependency_files) { bazel_project_dependency_files("comments_only") }

    it "handles comment-only files gracefully" do
      dependencies = parser.parse
      expect(dependencies).to be_empty
    end
  end

  context "with bazel_dep parameter order variations" do
    let(:dependency_files) { bazel_project_dependency_files("parameter_order_variations") }

    it "parses bazel_dep regardless of parameter order" do
      dependencies = parser.parse

      expect(dependencies.length).to eq(4)

      # Verify each dependency was parsed correctly
      rules_cc = dependencies.find { |d| d.name == "rules_cc" }
      expect(rules_cc.version).to eq("0.1.1")

      rules_go = dependencies.find { |d| d.name == "rules_go" }
      expect(rules_go.version).to eq("0.39.1")

      abseil = dependencies.find { |d| d.name == "abseil-cpp" }
      expect(abseil.version).to eq("20230125.3")

      rules_python = dependencies.find { |d| d.name == "rules_python" }
      expect(rules_python.version).to eq("0.25.0")

      # All should be Bazel dependencies
      dependencies.each do |dep|
        expect(dep.package_manager).to eq("bazel")
        expect(dep.requirements.first[:file]).to eq("MODULE.bazel")
      end
    end
  end
end
