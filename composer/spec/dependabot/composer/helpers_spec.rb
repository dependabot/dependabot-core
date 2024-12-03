# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/composer/package_manager"
require "dependabot/composer/language"
require "dependabot/composer/helpers"

RSpec.describe Dependabot::Composer::Helpers do
  describe ".composer_version" do
    let(:composer_v2_content) do
      <<~JSON
        {
          "name": "valid/name",
          "version": "3.1.7",
          "dist": {
            "url": "https://www.example.net/files/3.1.7.zip",
            "type": "zip"
          },
          "require": {
            "monolog/monolog" : "1.0.1",
            "symfony/polyfill-mbstring": "1.0.1",
            "php": "*",
            "lib-foo": "*",
            "ext-bar": "*"
          }
        }
      JSON
    end

    let(:composer_v1_content) do
      <<~JSON
        {
          "name": "valid/name",
          "version": "3.1.7",
          "dist": {
            "url": "https://www.example.net/files/3.1.7.zip",
            "type": "zip"
          },
          "require": {
            "monolog/monolog" : "1.0.1",
            "symfony/polyfill-mbstring": "1.0.1",
            "php": "*",
            "invalid-package-name": "*"
          }
        }
      JSON
    end

    it "uses '2' for a manifest that specifies a platform dependency without lockfile" do
      composer_json = JSON.parse(composer_v2_content)

      expect(described_class.composer_version(composer_json)).to eq("2")
    end

    it "uses '2' when one of the packages has an invalid name" do
      composer_json = JSON.parse(composer_v1_content)

      expect(described_class.composer_version(composer_json)).to eq("2")
    end
  end

  describe ".package_manager_run_command" do
    let(:command) { "--version" }
    let(:fingerprint) { nil }
    let(:output) { "Composer version 2.7.7\nPHP version 7.4.33" }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return(output)
    end

    it "runs the given composer command and returns the output" do
      expect(described_class.package_manager_run_command(command)).to eq(output.strip)
    end

    it "logs the command execution and success" do
      expect(Dependabot.logger).to receive(:info).with("Running composer command: composer --version")
      expect(Dependabot.logger).to receive(:info).with("Command executed successfully: composer --version")
      described_class.package_manager_run_command(command)
    end

    it "logs and raises an error if the command fails" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(StandardError, "Command failed")
      expect(Dependabot.logger).to receive(:error).with(/Error running composer command/)
      expect { described_class.package_manager_run_command(command) }.to raise_error(StandardError, "Command failed")
    end
  end

  describe ".fetch_composer_and_php_versions" do
    let(:output) do
      "Composer version 2.7.7 2024-06-10 22:11:12\nPHP version 7.4.33 (/usr/bin/php7.4)"
    end

    before do
      allow(described_class).to receive(:package_manager_run_command).and_return(output)
    end

    it "fetches and parses composer and PHP versions correctly" do
      expect(described_class.fetch_composer_and_php_versions).to eq({
        composer: "2.7.7",
        php: "7.4.33"
      })
    end

    it "logs the composer and PHP versions" do
      expect(Dependabot.logger).to receive(:info).with(/Dependabot running with Composer version/)
      expect(Dependabot.logger).to receive(:info).with(/Dependabot running with PHP version/)
      described_class.fetch_composer_and_php_versions
    end

    it "logs and returns an empty hash on failure" do
      allow(described_class).to receive(:package_manager_run_command).and_raise(StandardError, "Command failed")
      expect(Dependabot.logger).to receive(:error).with(/Error fetching versions/)
      expect(described_class.fetch_composer_and_php_versions).to eq({})
    end
  end

  describe ".capture_version" do
    let(:output) { "Composer version 2.7.7\nPHP version 7.4.33" }

    it "captures the version from the output using the provided regex" do
      expect(described_class.capture_version(output, /Composer version (?<version>\d+\.\d+\.\d+)/)).to eq("2.7.7")
      expect(described_class.capture_version(output, /PHP version (?<version>\d+\.\d+\.\d+)/)).to eq("7.4.33")
    end

    it "returns nil if the regex does not match" do
      expect(described_class.capture_version(output, /Unknown version (?<version>\d+\.\d+\.\d+)/)).to be_nil
    end
  end

  describe ".capture_platform_php" do
    let(:parsed_composer_json) do
      {
        "config" => {
          "platform" => {
            "php" => "7.4.33"
          }
        }
      }
    end

    it "captures the PHP version from the composer.json config" do
      expect(described_class.capture_platform_php(parsed_composer_json)).to eq("7.4.33")
    end

    it "returns nil if the platform key is not present" do
      expect(described_class.capture_platform_php({})).to be_nil
    end
  end

  describe ".capture_platform" do
    let(:parsed_composer_json) do
      {
        "config" => {
          "platform" => {
            "ext-json" => "1.5.0"
          }
        }
      }
    end

    it "captures the platform extension version from composer.json" do
      expect(described_class.capture_platform(parsed_composer_json, "ext-json")).to eq("1.5.0")
    end

    it "returns nil if the platform or extension name is not present" do
      expect(described_class.capture_platform({}, "ext-json")).to be_nil
    end
  end

  describe ".php_constraint" do
    let(:parsed_composer_json) do
      {
        "require" => {
          "php" => ">=7.4 <8.0"
        }
      }
    end

    it "captures the PHP version constraint from composer.json" do
      expect(described_class.php_constraint(parsed_composer_json)).to eq(">=7.4 <8.0")
    end

    it "returns nil if the PHP constraint is not specified" do
      expect(described_class.php_constraint({})).to be_nil
    end
  end

  describe ".dependency_constraint" do
    let(:parsed_composer_json) do
      {
        "require" => {
          "ext-json" => ">=1.5.0",
          "php" => ">=7.4 <8.0"
        }
      }
    end

    it "captures the version constraint for the given dependency" do
      expect(described_class.dependency_constraint(parsed_composer_json, "ext-json")).to eq(">=1.5.0")
    end

    it "returns nil if the dependency is not specified" do
      expect(described_class.dependency_constraint(parsed_composer_json, "ext-mbstring")).to be_nil
    end
  end
end
