# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/registry_client"
require "dependabot/kotlin_toolchain/file_updater"

RSpec.describe Dependabot::KotlinToolchain::FileUpdater::WrapperUpdater do
  let(:repository) { "https://packages.jetbrains.team/maven/p/amper/amper" }
  let(:unix_wrapper) do
    Dependabot::DependencyFile.new(name: "kotlin", content: kotlin_wrapper("0.11.1"))
  end
  let(:windows_wrapper) do
    Dependabot::DependencyFile.new(name: "kotlin.bat", content: kotlin_wrapper("0.11.1", windows: true))
  end
  let(:dependency_files) { [unix_wrapper, windows_wrapper] }
  let(:source) { { type: "maven_repo", url: repository } }
  let(:dependency) do
    requirements = dependency_files.map do |file|
      { file: file.name, requirement: "0.12.0", groups: ["toolchain"], source: source, metadata: { kind: "wrapper" } }
    end

    Dependabot::Dependency.new(
      name: "org.jetbrains.kotlin:kotlin-cli",
      version: "0.12.0",
      previous_version: "0.11.1",
      requirements: requirements,
      previous_requirements: requirements.map { |req| req.merge(requirement: "0.11.1") },
      package_manager: "kotlin_toolchain",
      metadata: { wrapper: true }
    )
  end
  let(:updater) do
    described_class.new(dependency: dependency, dependency_files: dependency_files, credentials: [])
  end
  let(:status) { 200 }
  let(:downloaded) { ->(url) { kotlin_wrapper("0.12.0", windows: url.end_with?(".bat"), sha: "b" * 64) } }

  before do
    allow(Dependabot::RegistryClient).to receive(:get) do |url:, **|
      instance_double(Excon::Response, status: status, body: downloaded.call(url))
    end
  end

  it "downloads both wrappers from the versioned artifact path" do
    expect(updater.updated_files.map(&:name)).to contain_exactly("kotlin", "kotlin.bat")
    expect(Dependabot::RegistryClient).to have_received(:get)
      .with(url: "#{repository}/org/jetbrains/kotlin/kotlin-cli/0.12.0/kotlin-cli-0.12.0-wrapper", headers: {})
    expect(Dependabot::RegistryClient).to have_received(:get)
      .with(url: "#{repository}/org/jetbrains/kotlin/kotlin-cli/0.12.0/kotlin-cli-0.12.0-wrapper.bat", headers: {})
  end

  context "when the wrapper points at a mirror" do
    let(:repository) { "https://repo.example.test/amper" }
    let(:source) { { type: "maven_repo", url: "https://packages.jetbrains.team/maven/p/amper/amper" } }
    let(:unix_wrapper) do
      Dependabot::DependencyFile.new(
        name: "kotlin",
        content: kotlin_wrapper("0.11.1").sub(
          "https://packages.jetbrains.team/maven/p/amper/amper",
          repository
        )
      )
    end
    let(:windows_wrapper) do
      Dependabot::DependencyFile.new(
        name: "kotlin.bat",
        content: kotlin_wrapper("0.11.1", windows: true).sub(
          "https://packages.jetbrains.team/maven/p/amper/amper",
          repository
        )
      )
    end

    it "downloads from the mirror rather than the repository that served the version" do
      updater.updated_files

      expect(Dependabot::RegistryClient).to have_received(:get)
        .with(url: "#{repository}/org/jetbrains/kotlin/kotlin-cli/0.12.0/kotlin-cli-0.12.0-wrapper", headers: {})
    end

    it "keeps the mirror in the new wrappers" do
      updated = updater.updated_files.to_h { |file| [file.name, file.content] }

      expect(updated.fetch("kotlin")).to include("kotlin_cli_version=0.12.0")
      expect(updated.fetch("kotlin")).to include("{KOTLIN_CLI_DOWNLOAD_ROOT:-#{repository}}")
      expect(updated.fetch("kotlin.bat")).to include("set KOTLIN_CLI_DOWNLOAD_ROOT=#{repository}")
      expect(updated.values.join).not_to include("packages.jetbrains.team")
    end

    context "when the downloaded wrapper has no download root line" do
      let(:downloaded) do
        lambda { |url|
          kotlin_wrapper("0.12.0", windows: url.end_with?(".bat"), sha: "b" * 64).lines.grep_v(/DOWNLOAD_ROOT/).join
        }
      end

      it "refuses rather than silently pointing the wrapper at JetBrains" do
        expect { updater.updated_files }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          "Downloaded kotlin has no distribution repository line to point at #{repository}"
        )
      end
    end
  end

  context "when the artifact is not published" do
    let(:status) { 404 }

    it "refuses the update and names the URL" do
      expect { updater.updated_files }.to raise_error(
        Dependabot::DependencyFileNotResolvable,
        %r{Unable to download kotlin for Kotlin Toolchain 0\.12\.0 from #{repository}/.*-wrapper \(HTTP 404\)}
      )
    end
  end

  context "when the download carries the wrong version" do
    let(:downloaded) { ->(url) { kotlin_wrapper("0.11.9", windows: url.end_with?(".bat")) } }

    it "refuses the update and names the file" do
      expect { updater.updated_files }.to raise_error(
        Dependabot::DependencyFileNotParseable,
        /Downloaded kotlin(\.bat)? does not contain Kotlin Toolchain 0\.12\.0 and a SHA-256/
      )
    end
  end

  context "when the download has no checksum" do
    let(:downloaded) do
      lambda { |url|
        kotlin_wrapper("0.12.0", windows: url.end_with?(".bat")).lines.reject do |l|
          l.include?("sha256")
        end.join
      }
    end

    it "refuses the update" do
      expect { updater.updated_files }
        .to raise_error(
          Dependabot::DependencyFileNotParseable,
          /does not contain Kotlin Toolchain 0\.12\.0 and a SHA-256/
        )
    end
  end

  context "when the two wrappers disagree on the checksum" do
    let(:downloaded) do
      lambda do |url|
        windows = url.end_with?(".bat")
        kotlin_wrapper("0.12.0", windows: windows, sha: (windows ? "c" : "b") * 64)
      end
    end

    it "refuses the update rather than writing mismatched wrappers" do
      expect { updater.updated_files }.to raise_error(
        Dependabot::DependencyFileNotResolvable,
        "Updated Kotlin Toolchain wrappers contain different checksums"
      )
    end
  end
end
