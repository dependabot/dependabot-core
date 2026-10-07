# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/maven/file_parser/wrapper_mojo"

RSpec.describe Dependabot::Maven::FileParser::WrapperMojo do
  def make_properties_file(name, content)
    Dependabot::DependencyFile.new(name: name, content: content)
  end

  def fixture_content(filename)
    fixture("wrapper_files", filename)
  end

  describe ".load_properties" do
    subject(:props) { described_class.load_properties(content) }

    context "with only-script mode (≥ 3.3.4)" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-only-script.properties") }

      it "parses distributionUrl" do
        expect(props.distribution_url).to eq(
          "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip"
        )
      end

      it "parses distributionSha256Sum" do
        expect(props.distribution_sha256_sum).to eq("a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5cdbba7861a1498407")
      end

      it "parses wrapperVersion" do
        expect(props.wrapper_version).to eq("3.3.4")
      end

      it "parses distributionType" do
        expect(props.distribution_type).to eq("only-script")
      end
    end

    context "with bin mode (< 3.3.0)" do
      let(:content) { fixture_content("maven-wrapper-3.9.6-bin.properties") }

      it "decodes Java properties escapes in distributionUrl" do
        expect(props.distribution_url).to eq(
          "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.6/apache-maven-3.9.6-bin.zip"
        )
      end

      it "parses wrapperUrl for wrapper version" do
        expect(props.wrapper_version).to eq("3.2.0")
        expect(props.wrapper_url).to include("maven-wrapper-3.2.0.jar")
      end

      it "defaults distributionType to bin" do
        expect(props.distribution_type).to eq("bin")
      end
    end

    context "with bin mode with checksum and explicit wrapperVersion" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-bin-checksum.properties") }

      it "prefers wrapperVersion over wrapperUrl" do
        expect(props.wrapper_version).to eq("3.3.4")
      end
    end

    context "with a pre-release version in distributionUrl" do
      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/" \
          "3.9.0-alpha-1/apache-maven-3.9.0-alpha-1-bin.zip\n" \
          "wrapperVersion=3.3.4\n"
      end

      it "parses the pre-release version from distributionUrl" do
        expect(props.distribution_url).to include("3.9.0-alpha-1")
      end
    end

    context "with all properties present" do
      let(:dist_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip" }
      let(:wrap_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.4/maven-wrapper-3.3.4.jar" }
      let(:dist_sha) { "a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5cdbba7861a1498407" }
      let(:wrap_sha) { "e3b0c44298fc1c149afbf4c8996fb924" * 2 }
      let(:content) do
        "distributionUrl=#{dist_url}\n" \
          "distributionSha256Sum=#{dist_sha}\n" \
          "distributionType=bin\n" \
          "wrapperVersion=3.3.4\n" \
          "wrapperUrl=#{wrap_url}\n" \
          "wrapperSha256Sum=#{wrap_sha}\n"
      end

      it "parses distributionUrl" do
        expect(props.distribution_url).to eq(dist_url)
      end

      it "parses distribution_version from the URL path" do
        expect(props.distribution_version).to eq("3.9.9")
      end

      it "parses distributionSha256Sum" do
        expect(props.distribution_sha256_sum).to eq(dist_sha)
      end

      it "parses distributionType" do
        expect(props.distribution_type).to eq("bin")
      end

      it "parses wrapperVersion" do
        expect(props.wrapper_version).to eq("3.3.4")
      end

      it "parses wrapperUrl" do
        expect(props.wrapper_url).to include("maven-wrapper-3.3.4.jar")
      end

      it "parses wrapperSha256Sum" do
        expect(props.wrapper_sha256_sum).to eq(wrap_sha)
      end
    end

    context "with missing checksums" do
      let(:base_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip" }
      let(:content) { "distributionUrl=#{base_url}\ndistributionType=only-script\nwrapperVersion=3.3.4\n" }

      it "sets distribution_sha256_sum to nil" do
        expect(props.distribution_sha256_sum).to be_nil
      end

      it "sets wrapper_sha256_sum to nil" do
        expect(props.wrapper_sha256_sum).to be_nil
      end
    end

    context "with missing distributionType and wrapperVersion" do
      subject(:props) { described_class.load_properties(content, script_files: [mvnw_file]) }

      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip\n"
      end
      let(:script_content) { fixture("wrapper_files", "mvnw-3.3.0") }
      let(:mvnw_file) { make_properties_file("mvnw", script_content) }

      it "defaults distributionType to the plugin default (only-script) when no wrapperUrl is present" do
        expect(props.distribution_type).to eq("only-script")
      end

      it "reads wrapper_version from the script file" do
        expect(props.wrapper_version).to eq("3.3.0")
      end
    end

    context "with missing distributionType but a legacy wrapperUrl (JAR-based setup)" do
      subject(:props) { described_class.load_properties(content, script_files: [mvnw_file]) }

      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/" \
          "3.9.6/apache-maven-3.9.6-bin.zip\n" \
          "wrapperUrl=https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/" \
          "maven-wrapper/3.2.0/maven-wrapper-3.2.0.jar\n"
      end
      let(:script_content) { fixture("wrapper_files", "mvnw-3.3.0") }
      let(:mvnw_file) { make_properties_file("mvnw", script_content) }

      it "defaults distributionType to bin for legacy wrapperUrl setups" do
        expect(props.distribution_type).to eq("bin")
      end
    end

    context "when distributionUrl is missing" do
      let(:content) { "wrapperVersion=3.3.4\n" }

      it "returns nil so the wrapper is skipped rather than aborting parsing" do
        expect(props).to be_nil
      end

      it "logs that the wrapper was skipped" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/distributionUrl property is missing, skipping Maven Wrapper update/)
        props
      end
    end

    context "when no wrapper version source is available" do
      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip\n"
      end

      it "returns nil so the wrapper is skipped rather than aborting parsing" do
        expect(props).to be_nil
      end

      it "logs that the wrapper version could not be determined" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/could not determine Maven Wrapper version.*skipping Maven Wrapper update/)
        props
      end
    end
  end

  describe ".extract_distribution_version" do
    it "extracts the version from a standard bin zip URL" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("3.9.9")
    end

    it "extracts the version from a custom mirror layout" do
      url = "https://downloads.apache.org/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("3.9.9")
    end

    it "extracts an alpha pre-release version" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.0-alpha-1/apache-maven-3.9.0-alpha-1-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("3.9.0-alpha-1")
    end

    it "extracts an alpha pre-release version with a double-digit number" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/4.0.0-alpha-10/apache-maven-4.0.0-alpha-10-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("4.0.0-alpha-10")
    end

    it "extracts a beta pre-release version" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/4.0.0-beta-3/apache-maven-4.0.0-beta-3-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("4.0.0-beta-3")
    end

    it "extracts a release candidate version" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/4.0.0-rc-2/apache-maven-4.0.0-rc-2-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("4.0.0-rc-2")
    end

    it "extracts the version from a tar.gz URL" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.8.6/apache-maven-3.8.6-bin.tar.gz"
      expect(described_class.extract_distribution_version(url)).to eq("3.8.6")
    end

    it "returns nil when the URL contains no recognizable version path segment" do
      expect(described_class.extract_distribution_version("https://example.com/some-artifact.zip")).to be_nil
    end
  end

  describe ".resolve_dependencies" do
    let(:properties_file) { make_properties_file(".mvn/wrapper/maven-wrapper.properties", content) }

    context "with only-script mode" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-only-script.properties") }

      it "returns two dependencies" do
        deps = described_class.resolve_dependencies(properties_file)
        expect(deps.length).to eq(2)
      end

      it "returns apache-maven dependency" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven:apache-maven" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.9.9")
        expect(dep.requirements.first[:source][:type]).to eq("maven-distribution")
        expect(dep.requirements.first[:source][:property]).to eq("distributionUrl")
      end

      it "returns maven-wrapper dependency" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.3.4")
      end
    end

    context "with bin mode (< 3.3.0)" do
      let(:content) { fixture_content("maven-wrapper-3.9.6-bin.properties") }

      it "returns maven-wrapper with wrapperUrl property" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.2.0")
      end
    end

    context "with 3.3.0 gap (no wrapperVersion, no wrapperUrl)" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-no-wrapper-version.properties") }
      let(:script_content) { fixture("wrapper_files", "mvnw-3.3.0") }
      let(:mvnw_file) { make_properties_file("mvnw", script_content) }

      it "falls back to script comment for wrapper version" do
        deps = described_class.resolve_dependencies(properties_file, script_files: [mvnw_file])
        wrapper_dep = deps.find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(wrapper_dep).not_to be_nil
        expect(wrapper_dep.version).to eq("3.3.0")
      end
    end

    context "with source distribution type" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-source.properties") }

      it "returns two dependencies" do
        deps = described_class.resolve_dependencies(properties_file)
        expect(deps.length).to eq(2)
      end

      it "returns the apache-maven dependency" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven:apache-maven" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.9.9")
      end

      it "returns the maven-wrapper dependency" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep).not_to be_nil
      end
    end

    context "when the distribution URL points to the Maven daemon (mvnd)" do
      let(:content) do
        "distributionUrl=https://archive.apache.org/dist/maven/mvnd/1.0.2/maven-mvnd-1.0.2-bin.zip\n" \
          "distributionType=bin\nwrapperVersion=3.3.4\n"
      end

      it "returns an empty array" do
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end

      it "logs a warning that mvnd is not supported" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/Maven daemon \(mvnd\) distribution is not supported/)
        described_class.resolve_dependencies(properties_file)
      end
    end

    context "when the distribution URL uses a custom archive filename" do
      let(:content) do
        "distributionUrl=https://downloads.example.test/maven/current.zip\n" \
          "distributionType=only-script\nwrapperVersion=3.3.4\n"
      end

      it "skips wrapper dependencies instead of failing Maven parsing" do
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end

      it "logs that wrapper tracking was skipped" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/could not extract Maven version from distributionUrl, skipping Maven Wrapper update/)
        described_class.resolve_dependencies(properties_file)
      end
    end

    context "when the wrapperUrl points to a non-Apache wrapper (e.g. legacy Takari)" do
      let(:wrapper_url) { "https://repo.maven.apache.org/maven2/io/takari/maven-wrapper/0.5.6/maven-wrapper-0.5.6.jar" }
      let(:dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.6.3/apache-maven-3.6.3-bin.zip"
      end
      let(:content) { "distributionUrl=#{dist_url}\nwrapperUrl=#{wrapper_url}\n" }

      it "returns an empty array" do
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end

      it "logs a warning that the wrapper is not an Apache Maven Wrapper" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/wrapperUrl is not an Apache Maven Wrapper/)
        described_class.resolve_dependencies(properties_file)
      end
    end

    context "when a non-Apache wrapperUrl carries the Apache coordinate only in its query string" do
      let(:dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.6.3/apache-maven-3.6.3-bin.zip"
      end
      let(:wrapper_url) do
        "https://evil.example.com/io/takari/maven-wrapper/0.5.6/maven-wrapper-0.5.6.jar" \
          "?redirect=/org/apache/maven/wrapper/maven-wrapper/"
      end
      let(:content) { "distributionUrl=#{dist_url}\nwrapperUrl=#{wrapper_url}\n" }

      it "skips the wrapper because the coordinate is not in the URL path" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/wrapperUrl is not an Apache Maven Wrapper/)
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end
    end

    context "when a foreign JAR is hosted under the Apache maven-wrapper artifact directory" do
      let(:dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.6.3/apache-maven-3.6.3-bin.zip"
      end
      let(:wrapper_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.4/foreign-3.3.4.jar"
      end
      let(:content) { "distributionUrl=#{dist_url}\nwrapperUrl=#{wrapper_url}\n" }

      it "skips the wrapper because the filename is not the maven-wrapper artifact" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/wrapperUrl is not an Apache Maven Wrapper/)
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end
    end

    context "when a non-artifact filename sits under the Apache maven-wrapper version directory" do
      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/" \
          "apache-maven-3.9.9-bin.zip\nwrapperVersion=3.3.4\n" \
          "wrapperUrl=https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/" \
          "3.3.4/maven-wrapper-foreign.jar\n"
      end

      it "skips the wrapper even though a valid wrapperVersion is present" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/wrapperUrl is not an Apache Maven Wrapper/)
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end
    end

    context "when the wrapperUrl version directory and filename version disagree" do
      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/" \
          "apache-maven-3.9.9-bin.zip\n" \
          "wrapperUrl=https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/" \
          "3.3.4/maven-wrapper-9.9.9.jar\n"
      end

      it "skips the wrapper because the coordinate version is inconsistent" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/wrapperUrl is not an Apache Maven Wrapper/)
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end
    end

    context "when a legacy wrapper omits wrapperVersion, wrapperUrl, and a script banner" do
      let(:dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.6.0/apache-maven-3.6.0-bin.zip"
      end
      let(:content) { "distributionUrl=#{dist_url}\n" }
      let(:mvnw_file) do
        make_properties_file(
          "mvnw",
          "#!/bin/sh\njarUrl=\"https://repo.maven.apache.org/maven2/io/takari/maven-wrapper/0.4.2/" \
          "maven-wrapper-0.4.2.jar\"\n"
        )
      end

      it "skips the wrapper without raising" do
        expect(described_class.resolve_dependencies(properties_file, script_files: [mvnw_file])).to eq([])
      end
    end

    context "when an Apache wrapper is served from a private registry" do
      let(:content) do
        "distributionUrl=https://nexus.corp.example/repository/maven/org/apache/maven/apache-maven/" \
          "3.9.9/apache-maven-3.9.9-bin.zip\n" \
          "wrapperUrl=https://nexus.corp.example/repository/maven/org/apache/maven/wrapper/maven-wrapper/" \
          "3.3.4/maven-wrapper-3.3.4.jar\n"
      end

      it "recognises the wrapper by its artifact path and tracks both dependencies" do
        deps = described_class.resolve_dependencies(properties_file)
        expect(deps.map(&:name)).to contain_exactly(
          "org.apache.maven:apache-maven",
          "org.apache.maven.wrapper:maven-wrapper"
        )
      end
    end

    context "when a supported Apache wrapper retains a commented-out wrapperUrl" do
      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/" \
          "apache-maven-3.9.9-bin.zip\ndistributionType=only-script\nwrapperVersion=3.3.4\n" \
          "#wrapperUrl=https://repo.maven.apache.org/maven2/io/takari/maven-wrapper/0.4.2/" \
          "maven-wrapper-0.4.2.jar\n"
      end

      it "ignores the commented-out line and still tracks both dependencies" do
        deps = described_class.resolve_dependencies(properties_file)
        expect(deps.map(&:name)).to contain_exactly(
          "org.apache.maven:apache-maven",
          "org.apache.maven.wrapper:maven-wrapper"
        )
      end
    end

    context "when the wrapper has only a distributionUrl and a non-banner mvnw script" do
      let(:content) do
        "distributionUrl=https://repo1.maven.org/maven2/org/apache/maven/apache-maven/3.5.3/" \
          "apache-maven-3.5.3-bin.zip\n"
      end
      let(:mvnw_file) do
        make_properties_file(
          "mvnw",
          "#!/bin/sh\nexec \"$JAVACMD\" -classpath \"$BASE/.mvn/wrapper/maven-wrapper.jar\" \"$@\"\n"
        )
      end

      it "skips the wrapper instead of aborting Maven parsing" do
        expect(described_class.resolve_dependencies(properties_file, script_files: [mvnw_file])).to eq([])
      end

      it "logs that the wrapper version could not be determined" do
        allow(Dependabot.logger).to receive(:warn)
        described_class.resolve_dependencies(properties_file, script_files: [mvnw_file])
        expect(Dependabot.logger).to have_received(:warn)
          .with(/could not determine Maven Wrapper version.*skipping Maven Wrapper update/)
      end
    end

    context "with the apache-maven distribution dependency" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-only-script.properties") }

      it "sets packaging_type to pom in the requirement metadata" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven:apache-maven" }
        dist_req = dep.requirements.find { |r| r[:source][:property] == "distributionUrl" }
        expect(dist_req[:metadata]).to eq(
          {
            packaging_type: "pom",
            wrapper_version: "3.3.4",
            distribution_type: "only-script",
            distribution_version: "3.9.9",
            include_debug_script: false,
            distribution_sha256_sum: "a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5cdbba7861a1498407"
          }
        )
      end
    end

    context "with wrapper checksum present" do
      let(:dist_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip" }
      let(:wrap_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.4/maven-wrapper-3.3.4.jar" }
      let(:dist_sha) { "a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5cdbba7861a1498407" }
      let(:wrap_sha) { "e3b0c44298fc1c149afbf4c8996fb924" * 2 }
      let(:content) do
        "distributionUrl=#{dist_url}\n" \
          "distributionSha256Sum=#{dist_sha}\n" \
          "wrapperVersion=3.3.4\n" \
          "wrapperUrl=#{wrap_url}\n" \
          "wrapperSha256Sum=#{wrap_sha}\n"
      end

      it "captures wrapper_sha256_sum in the wrapperUrl requirement metadata" do
        deps = described_class.resolve_dependencies(properties_file)
        wrapper_req = deps.find { |d| d.requirements.any? { |r| r[:source][:property] == "wrapperUrl" } }
                          &.requirements
                          &.find { |r| r[:source][:property] == "wrapperUrl" }
        expect(wrapper_req[:metadata]).to eq({ wrapper_sha256_sum: wrap_sha })
      end
    end
  end
end
