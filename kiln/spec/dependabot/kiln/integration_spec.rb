# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"

require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe "kiln integration" do
  around(:each) do |example|
    WebMock.allow_net_connect!
    VCR.turned_off do
      example.run
    end
  end

  let(:repo_name) { "releen/kiln-fixtures" }
  let(:branch) { "master" }

  let(:source) do
    Dependabot::Source.new(
        provider: "github",
        repo: repo_name,
        directory: directory,
        branch: branch
    )
  end

  let(:directory) { "/" }
  let(:dependency_name) { "uaa" }
  let(:package_manager) { "kiln" }


  it "fetches and parses a kiln source" do

    ##############################
    # Fetch the dependency files #
    ##############################
    fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).
        new(source: source, credentials: github_credentials)

    files = fetcher.files
    commit = fetcher.commit

    ##############################
    # Parse the dependency files #
    ##############################
    parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
        dependency_files: files,
        source: source,
        credentials: github_credentials,
    )

    dependencies = parser.parse
    dep = dependencies.find { |d| d.name == dependency_name }
    # Temporary assertions until we implement next two steps
    expect(dep.name).to eq('uaa')
    expect(dep.requirements.first[:requirement]).to eq('~> 74.16.0')
  end
end
