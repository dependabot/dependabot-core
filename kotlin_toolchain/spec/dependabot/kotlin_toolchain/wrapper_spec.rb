# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/kotlin_toolchain/wrapper"

RSpec.describe Dependabot::KotlinToolchain::Wrapper do
  let(:unix_file) do
    Dependabot::DependencyFile.new(
      name: "kotlin",
      content: kotlin_wrapper("0.11.1")
    )
  end

  let(:windows_file) do
    Dependabot::DependencyFile.new(
      name: "kotlin.bat",
      content: kotlin_wrapper("0.11.1", windows: true)
    )
  end

  it "detects matching versions from both wrappers" do
    expect(described_class.detect_version([unix_file, windows_file])).to eq("0.11.1")
  end

  it "rejects mismatched wrapper versions" do
    windows_file.content = kotlin_wrapper("0.12.0", windows: true)

    expect { described_class.detect_version([unix_file, windows_file]) }
      .to raise_error(Dependabot::DependencyFileNotParseable, /different versions/)
  end

  it "rejects mismatched wrapper checksums" do
    windows_file.content = kotlin_wrapper("0.11.1", windows: true, sha: "b" * 64)

    expect { described_class.detect_sha([unix_file, windows_file]) }
      .to raise_error(Dependabot::DependencyFileNotParseable, /different checksums/)
  end

  it "rejects mismatched distribution repositories" do
    windows_file.content = kotlin_wrapper("0.11.1", windows: true).sub(
      "https://packages.jetbrains.team/maven/p/amper/amper",
      "https://packages.example.test/toolchain"
    )

    expect { described_class.detect_repository([unix_file, windows_file]) }
      .to raise_error(Dependabot::DependencyFileNotParseable, /different distribution repositories/)
  end

  it "accepts checksums that differ only in case" do
    windows_file.content = kotlin_wrapper("0.11.1", windows: true, sha: "A" * 64)

    expect(described_class.detect_sha([unix_file, windows_file])).to eq("a" * 64)
  end

  it "reads a quoted Windows download root" do
    windows_file.content = kotlin_wrapper("0.11.1", windows: true).sub(
      "set KOTLIN_CLI_DOWNLOAD_ROOT=https://packages.jetbrains.team/maven/p/amper/amper",
      'set "KOTLIN_CLI_DOWNLOAD_ROOT=https://corp.example/mirror/"'
    )

    expect(described_class.repository_from_content(windows_file.content)).to eq("https://corp.example/mirror")
  end

  it "takes the download root from the wrapper that declares one" do
    unix_file.content = kotlin_wrapper("0.11.1").sub(
      "https://packages.jetbrains.team/maven/p/amper/amper",
      "https://corp.example/mirror"
    )
    windows_file.content = kotlin_wrapper("0.11.1", windows: true).lines.grep_v(/DOWNLOAD_ROOT/).join

    expect(described_class.detect_repository([unix_file, windows_file])).to eq("https://corp.example/mirror")
  end

  it "falls back to the JetBrains repository when no wrapper declares one" do
    unix_file.content = kotlin_wrapper("0.11.1").lines.grep_v(/DOWNLOAD_ROOT/).join

    expect(described_class.detect_repository([unix_file]))
      .to eq("https://packages.jetbrains.team/maven/p/amper/amper")
  end

  it "rewrites the download root in both wrapper flavours" do
    expect(described_class.with_repository(kotlin_wrapper("0.11.1"), "https://corp.example/mirror"))
      .to include('KOTLIN_CLI_DOWNLOAD_ROOT="${KOTLIN_CLI_DOWNLOAD_ROOT:-https://corp.example/mirror}"')
    expect(described_class.with_repository(kotlin_wrapper("0.11.1", windows: true), "https://corp.example/mirror"))
      .to include("set KOTLIN_CLI_DOWNLOAD_ROOT=https://corp.example/mirror")
    expect(described_class.with_repository("#!/bin/sh\n", "https://corp.example/mirror")).to be_nil
  end

  it "builds official wrapper artifact URLs" do
    expect(
      described_class.artifact_url(
        repository: "https://repo.example",
        version: "0.11.1",
        windows: false
      )
    ).to eq(
      "https://repo.example/org/jetbrains/kotlin/kotlin-cli/0.11.1/kotlin-cli-0.11.1-wrapper"
    )
  end
end
