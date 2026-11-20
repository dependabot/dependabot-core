# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/bazel/file_fetcher/module_path_extractor"

RSpec.describe Dependabot::Bazel::FileFetcher::ModulePathExtractor do
  describe "#extract_paths" do
    subject(:file_paths) { described_class.new(module_file: module_file).extract_paths.first }

    let(:module_file) { Dependabot::DependencyFile.new(name: "MODULE.bazel", content: content) }

    context "with a gazelle go_deps.from_file tag spread over several lines" do
      let(:content) do
        <<~STARLARK
          go_deps = use_extension("@gazelle//:extensions.bzl", "go_deps")
          go_deps.from_file(
              go_mod = "//services/api:go.mod",
          )
        STARLARK
      end

      it "returns the go.mod named by the go_mod attribute" do
        expect(file_paths).to include("services/api/go.mod")
      end
    end
  end
end
