# typed: false
# frozen_string_literal: true

require "spec_helper"
require "base64"
require "dependabot/dependency"
require "dependabot/gradle/file_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::WrapperUpdater do
  subject(:command_args) do
    Dependabot::Gradle::FileUpdater::Wrapper::CommandBuilder.new(
      requirements: target_requirements,
      original_properties: nil,
      gradle_version: nil
    ).build
  end

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency
    )
  end
  let(:dependency_files) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "gradle-wrapper",
      version: "9.0.0",
      requirements: [
        {
          file: "gradle/wrapper/gradle-wrapper.properties",
          requirement: "9.0.0",
          groups: [],
          source: {
            type: "gradle-distribution",
            url: "https://services.gradle.org/distributions/gradle-9.0.0-bin.zip",
            property: "distributionUrl"
          }
        },
        {
          file: "subproject/gradle/wrapper/gradle-wrapper.properties",
          requirement: "9.0.0",
          groups: [],
          source: {
            type: "gradle-distribution",
            url: "https://services.gradle.org/distributions/gradle-9.0.0-all.zip",
            property: "distributionUrl"
          }
        },
        {
          file: "subproject/gradle/wrapper/gradle-wrapper.properties",
          requirement: "f759b8dd5204e2e3fa4ca3e73f452f087153cf81bac9561eeb854229cc2c5365",
          groups: [],
          source: {
            type: "gradle-distribution",
            url: "https://services.gradle.org/distributions/gradle-9.0.0-all.zip.sha256",
            property: "distributionSha256Sum"
          }
        }
      ],
      package_manager: "gradle"
    )
  end

  context "when the current wrapper file has no checksum requirement" do
    let(:target_requirements) do
      dependency.requirements.select do |req|
        req[:file] == "gradle/wrapper/gradle-wrapper.properties"
      end
    end

    it "does not crash and does not include a checksum argument from another wrapper file" do
      expect(command_args).not_to include("--gradle-distribution-sha256-sum")
      expect(command_args).to include("--distribution-type", "bin")
    end
  end

  describe "#local_wrapper_files" do
    subject(:local_wrapper_file_names) do
      updater.send(:local_wrapper_files, build_file).map(&:name)
    end

    let(:build_file) do
      Dependabot::DependencyFile.new(
        name: "gradle/wrapper/gradle-wrapper.properties",
        content: "",
        directory: "/test-project"
      )
    end
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "gradle/wrapper/gradle-wrapper.properties",
          content: "",
          directory: "/test-project"
        ),
        Dependabot::DependencyFile.new(
          name: "gradle/wrapper/gradle-wrapper.jar",
          content: Base64.encode64("root jar"),
          directory: "/test-project",
          content_encoding: Dependabot::DependencyFile::ContentEncoding::BASE64
        ),
        Dependabot::DependencyFile.new(
          name: "../buildLogic/gradle/wrapper/gradle-wrapper.jar",
          content: Base64.encode64("included build jar"),
          directory: "/test-project",
          content_encoding: Dependabot::DependencyFile::ContentEncoding::BASE64
        ),
        Dependabot::DependencyFile.new(
          name: "../buildLogic/gradle/wrapper/gradle-wrapper.properties",
          content: "",
          directory: "/test-project"
        )
      ]
    end

    it "only includes wrapper files from the build root being updated" do
      expect(local_wrapper_file_names).to contain_exactly(
        "gradle/wrapper/gradle-wrapper.properties",
        "gradle/wrapper/gradle-wrapper.jar"
      )
    end

    context "when updating an included build" do
      let(:build_file) do
        Dependabot::DependencyFile.new(
          name: "../buildLogic/gradle/wrapper/gradle-wrapper.properties",
          content: "",
          directory: "/test-project"
        )
      end

      it "only includes wrapper files from the included build root" do
        expect(local_wrapper_file_names).to contain_exactly(
          "../buildLogic/gradle/wrapper/gradle-wrapper.jar",
          "../buildLogic/gradle/wrapper/gradle-wrapper.properties"
        )
      end
    end
  end

  describe "binary wrapper file handling" do
    let(:raw_jar_content) { "PK\x03\x04binary jar content".b }
    let(:updated_raw_jar_content) { "PK\x03\x04updated binary jar content".b }
    let(:jar_file) do
      Dependabot::DependencyFile.new(
        name: "gradle/wrapper/gradle-wrapper.jar",
        content: Base64.encode64(raw_jar_content),
        content_encoding: Dependabot::DependencyFile::ContentEncoding::BASE64
      )
    end
    let(:dependency_files) { [jar_file] }

    it "writes decoded binary content to the temporary directory" do
      Dir.mktmpdir do |temp_dir|
        updater.send(:populate_temp_directory, temp_dir)

        expect(File.binread(File.join(temp_dir, "gradle/wrapper/gradle-wrapper.jar")))
          .to eq(raw_jar_content)
      end
    end

    it "stores updated binary content as base64 encoded dependency file content" do
      Dir.mktmpdir do |temp_dir|
        wrapper_path = File.join(temp_dir, "gradle/wrapper/gradle-wrapper.jar")
        FileUtils.mkdir_p(File.dirname(wrapper_path))
        File.binwrite(wrapper_path, updated_raw_jar_content)

        updated_files = [jar_file]
        updater.send(:update_files_content, temp_dir, [jar_file], updated_files)

        expect(updated_files.first.content).to eq(Base64.encode64(updated_raw_jar_content))
        expect(updated_files.first.decoded_content).to eq(updated_raw_jar_content)
      end
    end
  end

  describe "#update_files reconciliation" do
    subject(:updated_properties) do
      updater.update_files(properties_file)
             .find { |f| f.name == "gradle/wrapper/gradle-wrapper.properties" }
             &.content
    end

    let(:dependency_files) { [properties_file] }
    let(:properties_file) do
      Dependabot::DependencyFile.new(
        name: "gradle/wrapper/gradle-wrapper.properties",
        content: original_properties,
        directory: "/"
      )
    end

    let(:original_properties) do
      <<~PROPS
        # Keep my settings - managed by the platform team
        distributionBase=GRADLE_USER_HOME
        distributionPath=wrapper/dists
        distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.2-bin.zip
        networkTimeout=30000
        retries=3
        retryBackOffMs=1000
        validateDistributionUrl=true
        zipStoreBase=GRADLE_USER_HOME
        zipStorePath=wrapper/dists
        myCompany.customKey=keep-me
      PROPS
    end

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "gradle-wrapper",
        version: "9.0.0",
        requirements: [{
          file: "gradle/wrapper/gradle-wrapper.properties",
          requirement: "9.0.0",
          groups: [],
          source: {
            type: "gradle-distribution",
            url: "https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip",
            property: "distributionUrl"
          }
        }],
        package_manager: "gradle"
      )
    end

    # Simulate Gradle's wrapper task regenerating the file from hardcoded defaults
    # (https://github.com/gradle/gradle/issues/36172): comments, ordering, custom keys and
    # user-customized values are all lost, recognized keys reset to defaults.
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:, **|
        File.write(
          File.join(cwd, "gradle/wrapper/gradle-wrapper.properties"),
          <<~DEFAULTS
            distributionBase=GRADLE_USER_HOME
            distributionPath=wrapper/dists
            distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip
            networkTimeout=10000
            retries=0
            retryBackOffMs=500
            validateDistributionUrl=false
            zipStoreBase=GRADLE_USER_HOME
            zipStorePath=wrapper/dists
          DEFAULTS
        )
        ""
      end
    end

    it "updates the distribution URL to the target version" do
      expect(updated_properties)
        .to include("distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip")
      expect(updated_properties).not_to include("gradle-8.14.2-bin.zip")
    end

    it "restores user values reset by the wrapper task (#15312)" do
      expect(updated_properties).to include("retries=3")
      expect(updated_properties).to include("retryBackOffMs=1000")
      expect(updated_properties).to include("networkTimeout=30000")
      expect(updated_properties).to include("validateDistributionUrl=true")
    end

    it "preserves comments, custom keys and structural keys" do
      expect(updated_properties).to include("# Keep my settings - managed by the platform team")
      expect(updated_properties).to include("myCompany.customKey=keep-me")
      expect(updated_properties).to include("distributionBase=GRADLE_USER_HOME")
      expect(updated_properties).to include("zipStorePath=wrapper/dists")
    end

    it "preserves the original key ordering" do
      expect(updated_properties.index("networkTimeout"))
        .to be < updated_properties.index("validateDistributionUrl")
      expect(updated_properties.index("# Keep my settings")).to eq(0)
    end
  end
end
