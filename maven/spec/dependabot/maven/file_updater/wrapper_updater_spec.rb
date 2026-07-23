# typed: false
# frozen_string_literal: true

require "base64"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/maven/file_updater/wrapper_updater"
require "dependabot/maven/native_helpers"
require "dependabot/maven/distributions"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Maven::FileUpdater::WrapperUpdater do
  def make_file(name, content)
    Dependabot::DependencyFile.new(name: name, content: content, directory: "/")
  end

  def fixture_content(filename)
    fixture("wrapper_files", filename)
  end

  subject(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency,
      credentials: credentials
    )
  end

  let(:properties_content) { fixture_content("maven-wrapper-3.9.9-only-script.properties") }
  let(:properties_file) { make_file(".mvn/wrapper/maven-wrapper.properties", properties_content) }
  let(:mvnw_file) do
    make_file("mvnw", "#!/bin/sh\n# Apache Maven Wrapper startup script, version 3.3.4\nexec mvn \"$@\"\n")
  end
  let(:dependency_files) { [properties_file, mvnw_file] }
  let(:credentials) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "org.apache.maven:apache-maven",
      version: "3.9.9",
      previous_version: "3.9.8",
      requirements: [{
        requirement: "3.9.9",
        file: ".mvn/wrapper/maven-wrapper.properties",
        source: {
          type: "maven-distribution",
          url: "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip",
          property: "distributionUrl"
        },
        groups: [],
        metadata: { packaging_type: "pom", wrapper_version: "3.3.4", distribution_type: "only-script",
                    distribution_version: "3.9.9", include_debug_script: false }
      }],
      previous_requirements: [{
        requirement: "3.9.8",
        file: ".mvn/wrapper/maven-wrapper.properties",
        source: {
          type: "maven-distribution",
          url: "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.8/apache-maven-3.9.8-bin.zip",
          property: "distributionUrl"
        },
        groups: [],
        metadata: { packaging_type: "pom", wrapper_version: "3.3.4", distribution_type: "only-script",
                    distribution_version: "3.9.8" }
      }],
      package_manager: "maven"
    )
  end

  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: "<project></project>",
      directory: "/"
    )
  end

  describe "#update_files" do
    context "when dependency is not a wrapper dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "com.google.guava:guava",
          version: "32.0.0-jre",
          previous_version: "31.0.0-jre",
          requirements: [{
            requirement: "32.0.0-jre",
            file: "pom.xml",
            source: nil,
            groups: []
          }],
          previous_requirements: [{
            requirement: "31.0.0-jre",
            file: "pom.xml",
            source: nil,
            groups: []
          }],
          package_manager: "maven"
        )
      end

      it "returns empty array" do
        expect(updater.update_files(buildfile)).to eq([])
      end
    end

    context "when no properties file is present" do
      let(:dependency_files) { [mvnw_file] }

      it "returns empty array" do
        expect(updater.update_files(buildfile)).to eq([])
      end
    end

    # Shared setup for tests that drive the full update_files path.
    # Stubs the native Maven command and provides HTTPS_PROXY which the
    # env-builder reads unconditionally.
    shared_context "with native helpers stubbed" do
      around do |example|
        saved = ENV.fetch("HTTPS_PROXY", nil)
        ENV["HTTPS_PROXY"] = "http://proxy.example.test"
        example.run
        saved ? (ENV["HTTPS_PROXY"] = saved) : ENV.delete("HTTPS_PROXY")
      end

      before do
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvnw_wrapper)
      end
    end

    context "when updating the distributionUrl" do
      include_context "with native helpers stubbed"

      # Properties file starts at the OLD version so the gsub actually fires.
      let(:old_dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.8/apache-maven-3.9.8-bin.zip"
      end
      let(:properties_content) do
        "distributionUrl=#{old_dist_url}\ndistributionType=only-script\nwrapperVersion=3.3.4\n"
      end

      it "returns a non-empty array of updated files" do
        expect(updater.update_files(buildfile)).not_to be_empty
      end

      it "includes the properties file" do
        names = updater.update_files(buildfile).map(&:name)
        expect(names).to include(".mvn/wrapper/maven-wrapper.properties")
      end
    end

    context "when updating the wrapperVersion" do
      include_context "with native helpers stubbed"

      let(:dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip"
      end
      let(:properties_content) do
        "distributionUrl=#{dist_url}\ndistributionType=only-script\nwrapperVersion=3.3.3\n"
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.apache.maven.wrapper:maven-wrapper",
          version: "3.3.4",
          previous_version: "3.3.3",
          requirements: [
            {
              requirement: "3.3.4",
              file: ".mvn/wrapper/maven-wrapper.properties",
              source: {
                type: "maven-distribution",
                property: "wrapperVersion"
              },
              groups: [],
              metadata: { wrapper_version: "3.3.4", distribution_version: "3.9.9", distribution_type: "only-script",
                          include_debug_script: false }
            },
            {
              requirement: "3.9.9",
              file: ".mvn/wrapper/maven-wrapper.properties",
              source: {
                type: "maven-distribution",
                property: "distributionUrl",
                url: dist_url
              },
              groups: [],
              metadata: { packaging_type: "pom", wrapper_version: "3.3.4", distribution_type: "only-script",
                          distribution_version: "3.9.9", include_debug_script: false }
            }
          ],
          previous_requirements: [
            {
              requirement: "3.3.3",
              file: ".mvn/wrapper/maven-wrapper.properties",
              source: {
                type: "maven-distribution",
                property: "wrapperVersion"
              },
              groups: [],
              metadata: { wrapper_version: "3.3.3", distribution_version: "3.9.9", include_debug_script: false }
            },
            {
              requirement: "3.9.9",
              file: ".mvn/wrapper/maven-wrapper.properties",
              source: {
                type: "maven-distribution",
                property: "distributionUrl",
                url: dist_url
              },
              groups: [],
              metadata: { packaging_type: "pom", wrapper_version: "3.3.4", distribution_type: "only-script",
                          distribution_version: "3.9.9", include_debug_script: false }
            }
          ],
          package_manager: "maven"
        )
      end
    end

    context "when scripts are present in dependency_files" do
      include_context "with native helpers stubbed"

      let(:old_dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.8/apache-maven-3.9.8-bin.zip"
      end
      let(:properties_content) do
        "distributionUrl=#{old_dist_url}\ndistributionType=only-script\nwrapperVersion=3.3.4\n"
      end
      let(:mvnw_cmd_file) { make_file("mvnw.cmd", "@echo off\r\n") }
      let(:dependency_files) { [properties_file, mvnw_file, mvnw_cmd_file] }

      it "includes the Unix script in the returned files" do
        names = updater.update_files(buildfile).map(&:name)
        expect(names).to include("mvnw")
      end

      it "marks Unix scripts as EXECUTABLE" do
        f = updater.update_files(buildfile).find { |file| file.name == "mvnw" }
        expect(f&.mode).to eq(Dependabot::DependencyFile::Mode::EXECUTABLE)
      end

      it "includes the Windows script in the returned files" do
        names = updater.update_files(buildfile).map(&:name)
        expect(names).to include("mvnw.cmd")
      end

      it "does not mark Windows scripts as EXECUTABLE" do
        f = updater.update_files(buildfile).find { |file| file.name == "mvnw.cmd" }
        expect(f&.mode).not_to eq(Dependabot::DependencyFile::Mode::EXECUTABLE)
      end
    end

    context "with bin distribution type" do
      include_context "with native helpers stubbed"

      let(:old_dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.8/apache-maven-3.9.8-bin.zip"
      end
      let(:properties_content) do
        "distributionUrl=#{old_dist_url}\ndistributionType=bin\nwrapperVersion=3.3.4\n"
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.apache.maven:apache-maven",
          version: "3.9.9",
          previous_version: "3.9.8",
          requirements: [{
            requirement: "3.9.9",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              url: "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip",
              property: "distributionUrl"
            },
            groups: [],
            metadata: { packaging_type: "pom", wrapper_version: "3.3.4", distribution_type: "bin",
                        distribution_version: "3.9.9", include_debug_script: false }
          }],
          previous_requirements: [{
            requirement: "3.9.8",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              url: old_dist_url,
              property: "distributionUrl"
            },
            groups: [],
            metadata: {
              packaging_type: "pom",
              wrapper_version: "3.3.4",
              distribution_type: "bin",
              distribution_version: "3.9.8"
            }
          }],
          package_manager: "maven"
        )
      end

      let(:jar_file) do
        f = make_file(".mvn/wrapper/maven-wrapper.jar", Base64.strict_encode64("fake-jar-bytes"))
        f.content_encoding = Dependabot::DependencyFile::ContentEncoding::BASE64
        f
      end
      let(:dependency_files) { [properties_file, mvnw_file, jar_file] }

      it "includes the JAR file in the returned files" do
        names = updater.update_files(buildfile).map(&:name)
        expect(names).to include(".mvn/wrapper/maven-wrapper.jar")
      end

      it "returns the JAR file with BASE64 content encoding" do
        jar = updater.update_files(buildfile)
                     .find { |f| f.name == ".mvn/wrapper/maven-wrapper.jar" }
        expect(jar&.content_encoding).to eq(Dependabot::DependencyFile::ContentEncoding::BASE64)
      end
    end

    context "with source distribution type" do
      include_context "with native helpers stubbed"

      let(:old_dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.8/apache-maven-3.9.8-bin.zip"
      end
      let(:properties_content) do
        "distributionUrl=#{old_dist_url}\ndistributionType=source\nwrapperVersion=3.3.4\n"
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.apache.maven:apache-maven",
          version: "3.9.9",
          previous_version: "3.9.8",
          requirements: [{
            requirement: "3.9.9",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              url: "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip",
              property: "distributionUrl"
            },
            groups: [],
            metadata: { packaging_type: "pom", wrapper_version: "3.3.4", distribution_type: "source",
                        distribution_version: "3.9.9", include_debug_script: false }
          }],
          previous_requirements: [{
            requirement: "3.9.8",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              url: old_dist_url,
              property: "distributionUrl"
            },
            groups: [],
            metadata: { packaging_type: "pom", wrapper_version: "3.3.4", distribution_type: "source",
                        distribution_version: "3.9.8" }
          }],
          package_manager: "maven"
        )
      end

      let(:downloader_content) { "public class MavenWrapperDownloader {}\n" }
      let(:downloader_file) do
        make_file(".mvn/wrapper/MavenWrapperDownloader.java", downloader_content)
      end
      let(:dependency_files) { [properties_file, mvnw_file, downloader_file] }

      it "includes MavenWrapperDownloader.java in the returned files" do
        names = updater.update_files(buildfile).map(&:name)
        expect(names).to include(".mvn/wrapper/MavenWrapperDownloader.java")
      end

      it "does not include a JAR file" do
        names = updater.update_files(buildfile).map(&:name)
        expect(names).not_to include(".mvn/wrapper/maven-wrapper.jar")
      end
    end

    # Integrity checksums are restored from the URLs in the regenerated properties file, independently
    # of which coordinate was bumped, so a wrapperVersion-only bump still keeps the
    # distributionSha256Sum / wrapperSha256Sum that the original file tracked.
    context "when the wrapper plugin is bumped and the original tracked checksums" do
      include_context "with native helpers stubbed"

      let(:artifact_bytes) { "fake-artifact-bytes" }
      let(:expected_sha) { Digest::SHA256.hexdigest(artifact_bytes) }
      let(:dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip"
      end
      let(:wrapper_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.4/maven-wrapper-3.3.4.jar"
      end
      let(:properties_content) do
        <<~PROPS
          distributionUrl=#{dist_url}
          distributionType=only-script
          wrapperUrl=#{wrapper_url}
          wrapperVersion=3.3.3
          distributionSha256Sum=0000000000000000000000000000000000000000000000000000000000000000
          wrapperSha256Sum=1111111111111111111111111111111111111111111111111111111111111111
        PROPS
      end

      # A wrapper-plugin (wrapperVersion) dependency carries neither checksum in its requirements.
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.apache.maven.wrapper:maven-wrapper",
          version: "3.3.4",
          previous_version: "3.3.3",
          requirements: [{
            requirement: "3.3.4",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: { type: "maven-distribution", property: "wrapperVersion" },
            groups: [],
            metadata: { wrapper_version: "3.3.4", distribution_version: "3.9.9", distribution_type: "only-script",
                        include_debug_script: false }
          }],
          package_manager: "maven"
        )
      end

      before do
        response = Struct.new(:status, :body).new(200, artifact_bytes)
        allow(Dependabot::RegistryClient).to receive(:get).and_return(response)
      end

      it "restores the distribution checksum recomputed from the artifact" do
        props = updater.update_files(buildfile)
                       .find { |f| f.name == ".mvn/wrapper/maven-wrapper.properties" }
        expect(props&.content).to include("distributionSha256Sum=#{expected_sha}")
      end

      it "restores the wrapper checksum recomputed from the artifact" do
        props = updater.update_files(buildfile)
                       .find { |f| f.name == ".mvn/wrapper/maven-wrapper.properties" }
        expect(props&.content).to include("wrapperSha256Sum=#{expected_sha}")
      end
    end

    context "when the original properties file had no checksums" do
      include_context "with native helpers stubbed"

      let(:properties_content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/" \
          "3.9.8/apache-maven-3.9.8-bin.zip\ndistributionType=only-script\nwrapperVersion=3.3.4\n"
      end

      it "does not add any checksum properties" do
        props = updater.update_files(buildfile)
                       .find { |f| f.name == ".mvn/wrapper/maven-wrapper.properties" }
        expect(props&.content).not_to match(/Sha256Sum/)
      end

      it "never downloads an artifact to compute a checksum" do
        allow(Dependabot::RegistryClient).to receive(:get)
        updater.update_files(buildfile)
        expect(Dependabot::RegistryClient).not_to have_received(:get)
      end
    end

    # A wrapper that lives beside a child pom is regenerated in place, not at the repo root.
    context "when the wrapper lives in a module (non-root)" do
      include_context "with native helpers stubbed"

      let(:properties_content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/" \
          "3.9.8/apache-maven-3.9.8-bin.zip\ndistributionType=only-script\nwrapperVersion=3.3.4\n"
      end
      let(:properties_file) { make_file("module/.mvn/wrapper/maven-wrapper.properties", properties_content) }
      let(:mvnw_file) { make_file("module/mvnw", "#!/bin/sh\nexec mvn \"$@\"\n") }
      let(:dependency_files) { [properties_file, mvnw_file] }
      let(:buildfile) { make_file("module/pom.xml", "<project></project>") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.apache.maven:apache-maven",
          version: "3.9.9",
          previous_version: "3.9.8",
          requirements: [{
            requirement: "3.9.9",
            file: "module/.mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              url: "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/" \
                   "3.9.9/apache-maven-3.9.9-bin.zip",
              property: "distributionUrl"
            },
            groups: [],
            metadata: { packaging_type: "pom", wrapper_version: "3.3.4", distribution_type: "only-script",
                        distribution_version: "3.9.9", include_debug_script: false }
          }],
          package_manager: "maven"
        )
      end

      it "runs the native command in the module directory" do
        received = {}
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvnw_wrapper) { |**kwargs| received = kwargs }
        updater.update_files(buildfile)
        expect(received[:cwd]).to eq("module")
      end

      it "emits module-prefixed file names" do
        names = updater.update_files(buildfile).map(&:name)
        expect(names).to include("module/.mvn/wrapper/maven-wrapper.properties")
      end
    end

    # The plugin's user property is `includeDebug` (the internal field is includeDebugScript). Passing
    # the wrong flag would silently drop the user's mvnwDebug scripts on every update.
    context "when the wrapper includes debug scripts" do
      include_context "with native helpers stubbed"

      let(:properties_content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/" \
          "3.9.8/apache-maven-3.9.8-bin.zip\ndistributionType=only-script\nwrapperVersion=3.3.4\n"
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.apache.maven:apache-maven",
          version: "3.9.9",
          previous_version: "3.9.8",
          requirements: [{
            requirement: "3.9.9",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              url: "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/" \
                   "3.9.9/apache-maven-3.9.9-bin.zip",
              property: "distributionUrl"
            },
            groups: [],
            metadata: { packaging_type: "pom", wrapper_version: "3.3.4", distribution_type: "only-script",
                        distribution_version: "3.9.9", include_debug_script: true }
          }],
          package_manager: "maven"
        )
      end

      it "passes the plugin's includeDebug user property" do
        received = {}
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvnw_wrapper) { |**kwargs| received = kwargs }
        updater.update_files(buildfile)
        expect(received[:extra_args]).to include("-DincludeDebug=true")
      end
    end
  end
end
