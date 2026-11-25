# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/subprocess_error_context"

RSpec.describe Dependabot::NpmAndYarn::SubprocessErrorContext do
  describe ".attach" do
    let(:error) do
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "failed", error_context: {})
    end

    def attach(command:, version: "10.9.2", registry: "https://user:secret@npm.example.com/private/path")
      described_class.attach(error, package_manager: "npm", command: command, version: version, registry: registry)
      Dependabot::ErrorReportContext.build(error: error)
    end

    it "reports the allowlisted subcommand, version and registry host only" do
      context = attach(command: "install --ignore-scripts @private/pkg@1.0.0")

      expect(context).to include(
        "command-name" => "npm install",
        "package-manager-version" => "10.9.2",
        "registry-host" => "npm.example.com"
      )
      expect(context.values.join(" ")).not_to include("secret", "private", "--ignore-scripts")
    end

    it "reports only the package manager for unknown subcommands" do
      expect(attach(command: "--prefix /tmp/secret install")).to include("command-name" => "npm")
    end

    it "omits a registry host that cannot be parsed safely" do
      expect(attach(command: "install", registry: "not a url")).not_to have_key("registry-host")
    end

    it "omits a version that is not a whole semver version" do
      expect(attach(command: "install", version: "10.9.2 warning: https://user:token@npm.example.com/private"))
        .not_to have_key("package-manager-version")
    end

    it "omits unknown version and registry" do
      expect(attach(command: "install", version: nil, registry: nil))
        .not_to include("package-manager-version", "registry-host")
    end
  end
end
