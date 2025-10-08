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

  let(:dependency_files) { [module_file] }

  let(:module_file) do
    Dependabot::DependencyFile.new(
      name: "MODULE.bazel",
      content: module_file_content
    )
  end

  let(:module_file_content) do
    <<~BAZEL
      module(name = "my-module", version = "1.0")

      bazel_dep(name = "rules_cc", version = "0.1.1")
      bazel_dep(name = "platforms", version = "0.0.11")
      bazel_dep(name = "abseil-cpp", version = "20230125.3")
    BAZEL
  end

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

  context "with WORKSPACE file" do
    let(:dependency_files) { [workspace_file] }

    let(:workspace_file) do
      Dependabot::DependencyFile.new(
        name: "WORKSPACE",
        content: workspace_file_content
      )
    end

    let(:workspace_file_content) do
      <<~BAZEL
        load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

        http_archive(
            name = "rules_cc",
            urls = ["https://github.com/bazelbuild/rules_cc/archive/v0.1.1.tar.gz"],
            sha256 = "abc123...",
        )

        http_archive(
            name = "abseil-cpp",
            urls = ["https://github.com/abseil/abseil-cpp/archive/20230125.3.tar.gz"],
            sha256 = "def456...",
        )
      BAZEL
    end

    it "parses WORKSPACE dependencies" do
      dependencies = parser.parse

      expect(dependencies.length).to eq(2)
      expect(dependencies.map(&:name)).to contain_exactly("rules_cc", "abseil-cpp")

      rules_cc_dep = dependencies.find { |d| d.name == "rules_cc" }
      expect(rules_cc_dep.version).to eq("0.1.1")
    end
  end

  context "with BUILD file" do
    let(:dependency_files) { [module_file, build_file] }

    let(:build_file) do
      Dependabot::DependencyFile.new(
        name: "BUILD",
        content: build_file_content
      )
    end

    let(:build_file_content) do
      <<~BAZEL
        load("@rules_go//go:def.bzl", "go_library", "go_binary")
        load("@rules_cc//cc:defs.bzl", "cc_library")

        cc_library(
            name = "my_lib",
            srcs = ["lib.cc"],
            deps = [
                "@abseil-cpp//absl/strings",
            ],
        )
      BAZEL
    end

    it "parses load statements from BUILD files" do
      dependencies = parser.parse

      # Should include MODULE.bazel deps plus load references
      expect(dependencies.length).to be >= 3

      load_deps = dependencies.select { |d| d.requirements.first[:groups] == ["load_references"] }
      expect(load_deps.map(&:name)).to include("rules_go", "rules_cc")
    end
  end

  context "with .bazelversion file" do
    let(:dependency_files) { [module_file, bazelversion_file] }

    let(:bazelversion_file) do
      Dependabot::DependencyFile.new(
        name: ".bazelversion",
        content: "6.4.0"
      )
    end

    it "detects the Bazel version" do
      expect(parser.send(:bazel_version)).to eq("6.4.0")
    end
  end
end
