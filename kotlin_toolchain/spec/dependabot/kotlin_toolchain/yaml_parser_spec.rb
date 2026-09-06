# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/errors"
require "dependabot/kotlin_toolchain/yaml_parser"

RSpec.describe Dependabot::KotlinToolchain::YamlParser do
  let(:content) do
    <<~YAML
      tasks:
        testJvm:
          dependsOn: [ :backend:publishJvm, :cli:testJvm@windows ]
    YAML
  end

  it "parses Kotlin Toolchain task references without shifting source offsets" do
    sanitized = described_class.sanitize(content)
    parsed = described_class.load(content, filename: "module.yaml")

    expect(sanitized.bytesize).to eq(content.bytesize)
    expect(parsed.dig("tasks", "testJvm", "dependsOn"))
      .to eq(%w(_backend:publishJvm _cli:testJvm@windows))
  end

  it "keeps bare version numbers and dates as text" do
    parsed = described_class.load(<<~YAML, filename: "module.yaml")
      settings:
        springBoot:
          version: 3.2
        jvm:
          test:
            junitPlatformVersion: 1.10
          jdk:
            version: 21
      since: 2024-01-01
      dependsOn: :prepare
      flow: [ :prepare, :lib:build ]
    YAML

    expect(parsed.dig("settings", "springBoot", "version")).to eq("3.2")
    expect(parsed.dig("settings", "jvm", "test", "junitPlatformVersion")).to eq("1.10")
    expect(parsed.dig("settings", "jvm", "jdk", "version")).to eq(21)
    expect(parsed["since"]).to eq("2024-01-01")
    expect(parsed["dependsOn"]).to eq("_prepare")
    expect(parsed["flow"]).to eq(%w(_prepare _lib:build))
  end

  it "resolves aliases" do
    parsed = described_class.load("base: &v 1.0.0\nother: *v\n", filename: "module.yaml")

    expect(parsed).to eq("base" => "1.0.0", "other" => "1.0.0")
  end

  it "returns nil for an empty document" do
    expect(described_class.load("", filename: "module.yaml")).to be_nil
    expect(described_class.parse("", filename: "module.yaml")).to be_nil
  end

  context "with unparseable YAML" do
    let(:content) do
      <<~YAML
        dependencies:
          - "io.ktor:ktor-server-core:3.1.0
      YAML
    end

    it "reports the file name when loading" do
      expect { described_class.load(content, filename: "module.yaml") }
        .to raise_error(Dependabot::DependencyFileNotParseable, /\Amodule\.yaml: /)
    end

    it "reports the file name when parsing" do
      expect { described_class.parse(content, filename: "project.yaml") }
        .to raise_error(Dependabot::DependencyFileNotParseable, /\Aproject\.yaml: /)
    end
  end
end
