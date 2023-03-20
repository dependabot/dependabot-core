# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/replace_stubber"

RSpec.describe Dependabot::GoModules::ReplaceStubber do
  subject(:stubbed) { described_class.new(repo_contents_path).stub_paths(manifest, directory) }

  let(:directory) { "/" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }

  let(:manifest) do
    Dir.chdir("#{repo_contents_path}#{directory}") do
      JSON.parse(`go mod edit -json`)
    end
  end

  describe "#stub_paths" do
    context "replaced module as child" do
      let(:project_name) { "monorepo" }
      it { is_expected.to eq({}) }
    end

    context "replaced module as sibling" do
      let(:project_name) { "monorepo" }
      let(:directory) { "/cmd" }
      it { is_expected.to eq({}) }
    end

    context "replaced module outside of checkout" do
      let(:project_name) { "replace" }
      it {
        expected = { "../../../../../../foo" => "./381363a4e394c2f6ca00811041688e9d27392a475483e843808b32a2f01a1088" }
        is_expected.to eq(expected)
      }
    end
  end
end
