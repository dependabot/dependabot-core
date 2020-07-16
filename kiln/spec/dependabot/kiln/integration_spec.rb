# frozen_string_literal: true

require "spec_helper"
require "dependabot/kiln/file_fetcher"
require "dependabot/kiln/file_parser"
require "dependabot/kiln/update_checker"
require "dependabot/kiln/file_updater"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/kiln/version"
require "dependabot/kiln/requirement"
require "dependabot/kiln/metadata_finder"

require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe "kiln integration" do
  around(:each) do |example|
    WebMock.allow_net_connect!
    VCR.turned_off do
      example.run
    end
  end

  let(:credentials) do
    [{
         "type" => "git_source",
         "host" => "github.com",
         "username" => "x-access-token",
         "password" => "token"
     }, {
         "type" => "kiln",
         "variables" => {
             "aws_access_key_id" => "foo",
             "aws_secret_access_key" => "foo"
         }
     }]
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
    lockfile_contents = files.find {|f| f.name == "Kilnfile.lock"}.content

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

    expect(dep.name).to eq('uaa')

    #########################################
    # Get update details for the dependency #
    #########################################
    checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
        dependency: dep,
        dependency_files: files,
        credentials: credentials,
    )

    updated_deps = checker.updated_dependencies(requirements_to_unlock: :own)

    expect(updated_deps[0].version).not_to eq(dep.version)

    #####################################
    # Generate updated dependency files #
    #####################################
    updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
        dependencies: updated_deps,
        dependency_files: files,
        credentials: credentials,
        )

    updated_files = updater.updated_dependency_files

    expect(updated_files.length).to eq(1)
    expect(updated_files[0].name).to eq("Kilnfile.lock")
    expect(updated_files[0].content).to_not eq(lockfile_contents)
    expect(updated_files[0].content).to eq(fixture("kiln/expected", "Kilnfile.lock"))


  end
end
