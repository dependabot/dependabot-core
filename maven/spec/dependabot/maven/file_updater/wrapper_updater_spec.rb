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
          property: "distributionUrl",
          replace_string: "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip"
        },
        groups: []
      }],
      previous_requirements: [{
        requirement: "3.9.8",
        file: ".mvn/wrapper/maven-wrapper.properties",
        source: {
          type: "maven-distribution",
          url: "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.8/apache-maven-3.9.8-bin.zip",
          property: "distributionUrl",
          replace_string: "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.8/apache-maven-3.9.8-bin.zip"
        },
        groups: []
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

      it "writes the new distributionUrl into the properties file" do
        new_url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip"
        props = updater.update_files(buildfile)
                       .find { |f| f.name == ".mvn/wrapper/maven-wrapper.properties" }
        expect(props.content).to include(new_url)
      end

      it "removes the old version from the properties file" do
        props = updater.update_files(buildfile)
                       .find { |f| f.name == ".mvn/wrapper/maven-wrapper.properties" }
        expect(props.content).not_to include("3.9.8")
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
                property: "wrapperVersion",
                replace_string: "3.3.4"
              },
              groups: []
            },
            {
              requirement: "3.9.9",
              file: ".mvn/wrapper/maven-wrapper.properties",
              source: {
                type: "maven-distribution",
                property: "distributionUrl",
                url: dist_url,
                replace_string: dist_url
              },
              groups: []
            }
          ],
          previous_requirements: [
            {
              requirement: "3.3.3",
              file: ".mvn/wrapper/maven-wrapper.properties",
              source: {
                type: "maven-distribution",
                property: "wrapperVersion",
                replace_string: "3.3.3"
              },
              groups: []
            },
            {
              requirement: "3.9.9",
              file: ".mvn/wrapper/maven-wrapper.properties",
              source: {
                type: "maven-distribution",
                property: "distributionUrl",
                url: dist_url,
                replace_string: dist_url
              },
              groups: []
            }
          ],
          package_manager: "maven"
        )
      end

      it "writes the new wrapperVersion into the properties file" do
        props = updater.update_files(buildfile)
                       .find { |f| f.name == ".mvn/wrapper/maven-wrapper.properties" }
        expect(props.content).to include("wrapperVersion=3.3.4")
        expect(props.content).not_to include("wrapperVersion=3.3.3")
      end
    end

    context "when distributionUrl uses \\: Java-Properties escaping" do
      include_context "with native helpers stubbed"

      let(:escaped_old) do
        "https\\://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.8/apache-maven-3.9.8-bin.zip"
      end
      let(:escaped_new) do
        "https\\://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip"
      end
      let(:properties_content) do
        "distributionUrl=#{escaped_old}\ndistributionType=only-script\nwrapperVersion=3.3.4\n"
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
              property: "distributionUrl",
              replace_string: escaped_new
            },
            groups: []
          }],
          previous_requirements: [{
            requirement: "3.9.8",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              property: "distributionUrl",
              replace_string: escaped_old
            },
            groups: []
          }],
          package_manager: "maven"
        )
      end

      it "preserves the \\: escape in the updated properties file" do
        props = updater.update_files(buildfile)
                       .find { |f| f.name == ".mvn/wrapper/maven-wrapper.properties" }
        expect(props.content).to include(escaped_new)
        expect(props.content).to include("\\:")
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

    context "when the distribution URL points to the Maven daemon (mvnd)" do
      let(:mvnd_url) do
        "https://archive.apache.org/dist/maven/mvnd/1.0.2/maven-mvnd-1.0.2-bin.zip"
      end
      let(:properties_content) do
        "distributionUrl=#{mvnd_url}\ndistributionType=bin\nwrapperVersion=3.3.4\n"
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.apache.maven:apache-maven",
          version: "1.0.2",
          previous_version: "1.0.1",
          requirements: [{
            requirement: "1.0.2",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              url: mvnd_url,
              property: "distributionUrl",
              replace_string: mvnd_url
            },
            groups: []
          }],
          previous_requirements: [{
            requirement: "1.0.1",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              url: "https://archive.apache.org/dist/maven/mvnd/1.0.1/maven-mvnd-1.0.1-bin.zip",
              property: "distributionUrl",
              replace_string: "https://archive.apache.org/dist/maven/mvnd/1.0.1/maven-mvnd-1.0.1-bin.zip"
            },
            groups: []
          }],
          package_manager: "maven"
        )
      end

      it "returns an empty array" do
        expect(updater.update_files(buildfile)).to eq([])
      end

      it "logs a warning that mvnd is not supported" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/Maven daemon \(mvnd\) distribution is not supported/)
        updater.update_files(buildfile)
      end
    end

    context "when the distribution URL points to a Takari distribution" do
      let(:takari_url) do
        "https://repo.example.com/takari/io/takari/maven/takari-maven-3.9.9-bin.zip"
      end
      let(:properties_content) do
        "distributionUrl=#{takari_url}\ndistributionType=bin\nwrapperVersion=3.3.4\n"
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
              url: takari_url,
              property: "distributionUrl",
              replace_string: takari_url
            },
            groups: []
          }],
          previous_requirements: [{
            requirement: "3.9.8",
            file: ".mvn/wrapper/maven-wrapper.properties",
            source: {
              type: "maven-distribution",
              url: "https://repo.example.com/takari/io/takari/maven/takari-maven-3.9.8-bin.zip",
              property: "distributionUrl",
              replace_string: "https://repo.example.com/takari/io/takari/maven/takari-maven-3.9.8-bin.zip"
            },
            groups: []
          }],
          package_manager: "maven"
        )
      end

      it "returns an empty array" do
        expect(updater.update_files(buildfile)).to eq([])
      end

      it "logs a warning that Takari is not supported" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/Takari distribution is not supported/)
        updater.update_files(buildfile)
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
  end
end
