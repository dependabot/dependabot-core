require "spec_helper"
require "dependabot/file_fetchers/julia/project_file_fetcher"

RSpec.describe Dependabot::Julia::FileFetcher do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gps-testing/julia-tester"
    )
  end

  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com"
      }]
    )
  end

  it "fetches Project.toml and Manifest.toml" do
    allow(file_fetcher_instance).to receive(:repo_contents).
      and_return(["Project.toml", "Manifest.toml"])

    expect(file_fetcher_instance.files.map(&:name)).
      to match_array(["Project.toml", "Manifest.toml"])
  end

  it "handles case-insensitive and versioned manifests" do
    allow(file_fetcher_instance).to receive(:repo_contents).
      and_return([
        "PROJECT.toml",
        "Manifest-v1.6.toml"
      ])

    expect(file_fetcher_instance.files.map(&:name)).
      to match_array(["PROJECT.toml", "Manifest-v1.6.toml"])
  end
end
