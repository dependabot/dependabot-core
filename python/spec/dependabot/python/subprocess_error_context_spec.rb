# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/python/subprocess_error_context"

RSpec.describe Dependabot::Python::SubprocessErrorContext do
  describe ".attach" do
    let(:error) do
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "failed", error_context: {})
    end

    def attach(command:, dependency_files: [], credentials: [])
      described_class.attach(error, command: command, dependency_files: dependency_files, credentials: credentials)
      Dependabot::ErrorReportContext.build(error: error)
    end

    it "reports the allowlisted command name and index hosts only" do
      credentials = [
        Dependabot::Credential.new(
          "type" => "python_index",
          "index-url" => "https://user:secret@pypi.example.com/private/simple",
          "token" => "secret"
        )
      ]
      pyproject = Dependabot::DependencyFile.new(
        name: "pyproject.toml",
        content: <<~TOML
          [[tool.poetry.source]]
          name = "internal"
          url = "https://${USER}:${TOKEN}@poetry.example.com/private/simple"
        TOML
      )

      context = attach(
        command: "pyenv exec poetry update private-pkg --lock --no-interaction",
        dependency_files: [pyproject],
        credentials: credentials
      )

      expect(context).to include(
        "command-name" => "poetry update",
        "index-hosts" => ["pypi.example.com", "poetry.example.com"]
      )
      expect(context.values.flatten.join(" ")).not_to include("secret", "private", "TOKEN", "--lock")
    end

    it "reports index hosts from Pipfile and Pipfile.lock sources" do
      pipfile = Dependabot::DependencyFile.new(
        name: "Pipfile",
        content: "[[source]]\nname = \"internal\"\nurl = \"https://pipfile.example.com/simple\"\n"
      )
      lockfile = Dependabot::DependencyFile.new(
        name: "Pipfile.lock",
        content: JSON.generate("_meta" => { "sources" => [{ "url" => "https://lock.example.com/simple" }] })
      )

      expect(attach(command: "pyenv exec pipenv upgrade --verbose pkg==1.0", dependency_files: [pipfile, lockfile]))
        .to include("command-name" => "pipenv upgrade", "index-hosts" => ["pipfile.example.com", "lock.example.com"])
    end

    it "never reports query string or fragment contents as the host" do
      credentials = [
        Dependabot::Credential.new("type" => "python_index", "index-url" => "https://query.example.com?auth=user@token"),
        Dependabot::Credential.new("type" => "python_index", "index-url" => "https://fragment.example.com#user@token")
      ]

      context = attach(command: "pyenv exec poetry lock", credentials: credentials)

      expect(context).to include("index-hosts" => ["query.example.com", "fragment.example.com"])
      expect(context.values.flatten.join(" ")).not_to include("token")
    end

    it "falls back to PyPI when no index is configured or parsable" do
      pipfile = Dependabot::DependencyFile.new(name: "Pipfile", content: "not [valid toml")

      expect(attach(command: "pyenv exec pipenv sync --dev", dependency_files: [pipfile]))
        .to include("command-name" => "pipenv sync", "index-hosts" => ["pypi.org"])
    end

    it "reports only the tool for subcommands that are not allowlisted" do
      expect(attach(command: "pyenv exec poetry --directory /tmp/secret lock")).to include("command-name" => "poetry")
    end

    it "omits the command name for unknown tools" do
      expect(attach(command: "curl https://user:secret@example.com")).not_to have_key("command-name")
    end
  end
end
