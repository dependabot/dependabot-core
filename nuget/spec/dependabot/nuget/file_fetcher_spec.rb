# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/nuget/file_fetcher"
require "dependabot/nuget/native_discovery/native_discovery_json_reader"
require "json"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Nuget::FileFetcher do
  subject(:fetched_file_paths) do
    files = file_fetcher_instance.fetch_files
    files.map do |f|
      Dependabot::Nuget::NativeDiscoveryJsonReader.dependency_file_path(repo_contents_path: repo_contents_path,
                                                                        dependency_file: f)
    end
  end
  let(:report_stub_debug_information) { false } # set to `true` to write method stubbing information to the screen

  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials, repo_contents_path: repo_contents_path)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "some/repo",
      directory: directory
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:repo_contents_path) { File.join(Dir.tmpdir, ".dependabot", "unit-test") }

  it_behaves_like "a dependency file fetcher"

  def clean_common_files
    Dependabot::Nuget::NativeDiscoveryJsonReader.testonly_clear_discovery_files
  end

  def clean_repo_files
    FileUtils.rm_rf(repo_contents_path)
  end

  # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
  def run_fetch_test(files_on_disk:, discovery_content_hash:, &_block)
    clean_common_files
    clean_repo_files
    ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "true"
    ENV["DEPENDABOT_JOB_PATH"] = File.join(repo_contents_path, "job.json")
    FileUtils.mkdir_p(File.dirname(ENV.fetch("DEPENDABOT_JOB_PATH", nil)))
    File.write(ENV.fetch("DEPENDABOT_JOB_PATH", nil), "unused")
    begin
      # stub call to native tool
      Dependabot::Nuget::NativeDiscoveryJsonReader.testonly_clear_caches
      allow(Dependabot::Nuget::NativeHelpers)
        .to receive(:run_nuget_discover_tool)
        .and_wrap_original do |_original_method, *args, &_block|
          discovery_json_path = args[0][:output_path]
          FileUtils.mkdir_p(File.dirname(discovery_json_path))
          if report_stub_debug_information
            puts "stubbing call to `run_nuget_discover_tool` with args #{args}; writing prefabricated discovery " \
                 "response to discovery.json to #{discovery_json_path}"
          end
          discovery_json_content = discovery_content_hash.to_json
          File.write(discovery_json_path, discovery_json_content)
        end
      # stub call to `fetch_file_from_host` because it expects an empty directory and other things that make the test
      # more difficult than it needs to be
      allow(file_fetcher_instance)
        .to receive(:fetch_file_from_host)
        .and_wrap_original do |_original_method, *args, &_block|
          filename = args[0]
          Dependabot::DependencyFile.new(
            name: filename,
            directory: directory,
            content: "unused"
          )
        end
      # ensure test files exist
      files_on_disk.each do |f|
        FileUtils.mkdir_p(File.join(repo_contents_path, File.dirname(f)))
        FileUtils.touch(File.join(repo_contents_path, f))
      end
      # run the test
      yield
    ensure
      clean_common_files
      clean_repo_files
      ENV.delete("DEPENDABOT_JOB_PATH")
      ENV.delete("DEPENDABOT_NUGET_CACHE_DISABLED")
    end
  end
  # rubocop:enable Metrics/AbcSize,Metrics/MethodLength

  context "when discovery JSON contents are properly reported" do
    describe "when the starting directory is the root" do
      let(:directory) { "/" }

      it "reports the correct files" do
        run_fetch_test(
          files_on_disk: [
            "Directory.Packages.props",
            "src/project1/packages.config",
            "src/project1/project1.csproj",
            "src/project2/packages.config",
            "src/project2/project2.csproj",
            "src/project2/unrelated-file.cs"
          ],
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [{
              FilePath: "src/project1/project1.csproj",
              IsSuccess: true,
              Dependencies: [], # not relevant for this test
              Properties: [], # not relevant for this test
              TargetFrameworks: [], # not relevant for this test
              ReferencedProjectPaths: [], # not relevant for this test
              ImportedFiles: [
                "../../Directory.Packages.props"
              ],
              AdditionalFiles: [
                "packages.config"
              ]
            }, {
              FilePath: "src/project2/project2.csproj",
              IsSuccess: true,
              Dependencies: [], # not relevant for this test
              Properties: [], # not relevant for this test
              TargetFrameworks: [], # not relevant for this test
              ReferencedProjectPaths: [], # not relevant for this test
              ImportedFiles: [
                "../../Directory.Packages.props"
              ],
              AdditionalFiles: [
                "packages.config"
              ]
            }],
            GlobalJson: nil,
            DotNetToolsJson: nil,
            ErrorType: nil,
            ErrorDetails: nil
          }
        ) do
          expect(fetched_file_paths).to contain_exactly("/Directory.Packages.props",
                                                        "/src/project1/packages.config",
                                                        "/src/project1/project1.csproj",
                                                        "/src/project2/packages.config",
                                                        "/src/project2/project2.csproj")
        end
      end
    end

    describe "when the starting directory is not the root" do
      let(:directory) { "/src" }

      it "reports the correct files" do
        run_fetch_test(
          files_on_disk: [
            "Directory.Packages.props",
            "src/project1/packages.config",
            "src/project1/project1.csproj",
            "src/project2/packages.config",
            "src/project2/project2.csproj",
            "src/project2/unrelated-file.cs"
          ],
          discovery_content_hash: {
            Path: "/src",
            IsSuccess: true,
            Projects: [{
              FilePath: "project1/project1.csproj",
              IsSuccess: true,
              Dependencies: [], # not relevant for this test
              Properties: [], # not relevant for this test
              TargetFrameworks: [], # not relevant for this test
              ReferencedProjectPaths: [], # not relevant for this test
              ImportedFiles: [
                "../../Directory.Packages.props"
              ],
              AdditionalFiles: [
                "packages.config"
              ]
            }, {
              FilePath: "project2/project2.csproj",
              IsSuccess: true,
              Dependencies: [], # not relevant for this test
              Properties: [], # not relevant for this test
              TargetFrameworks: [], # not relevant for this test
              ReferencedProjectPaths: [], # not relevant for this test
              ImportedFiles: [
                "../../Directory.Packages.props"
              ],
              AdditionalFiles: [
                "packages.config"
              ]
            }],
            GlobalJson: nil,
            DotNetToolsJson: nil,
            ErrorType: nil,
            ErrorDetails: nil
          }
        ) do
          expect(fetched_file_paths).to contain_exactly("/Directory.Packages.props",
                                                        "/src/project1/packages.config",
                                                        "/src/project1/project1.csproj",
                                                        "/src/project2/packages.config",
                                                        "/src/project2/project2.csproj")
        end
      end
    end

    describe "when global.json and dotnet-tools.json are present" do
      let(:directory) { "/src" }

      it "reports the correct files" do
        run_fetch_test(
          files_on_disk: [
            "global.json",
            ".config/dotnet-tools.json",
            "src/unrelated-file.cs"
          ],
          discovery_content_hash: {
            Path: "/src",
            IsSuccess: true,
            Projects: [], # unused in this test
            GlobalJson: {
              FilePath: "global.json",
              Dependencies: []
            },
            DotNetToolsJson: {
              FilePath: ".config/dotnet-tools.json",
              Dependencies: []
            },
            ErrorType: nil,
            ErrorDetails: nil
          }
        ) do
          expect(fetched_file_paths).to contain_exactly("/.config/dotnet-tools.json", "/global.json")
        end
      end
    end

    context "when there is a private source authentication failure" do
      let(:directory) { "/" }

      it "raises the correct error" do
        run_fetch_test(
          files_on_disk: [],
          discovery_content_hash: {
            Path: "",
            IsSucess: false,
            Projects: [],
            GlobalJson: nil,
            DotNetToolsJson: nil,
            ErrorType: "AuthenticationFailure",
            ErrorDetails: "the-error-details"
          }
        ) do
          expect { fetched_file_paths }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
        end
      end
    end
  end
end
