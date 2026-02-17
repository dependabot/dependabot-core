# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/PreCommit/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::PreCommit::FileParser do
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
    <<~PreCommit
    PreCommit 
  end

  it_behaves_like "a dependency file parser"

  # TODO: Add test cases
  # Example:
  # it "Parses Dependencies in files" do
  #   # Test implementation
  # end
end
