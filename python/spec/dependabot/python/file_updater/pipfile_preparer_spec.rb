# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/pipfile_preparer"

RSpec.describe Dependabot::Python::FileUpdater::PipfilePreparer do
  let(:preparer) do
    described_class.new(pipfile_content: pipfile_content)
  end

  let(:pipfile_content) do
    fixture("pipfile_files", pipfile_fixture_name)
  end
  let(:pipfile_fixture_name) { "version_not_specified" }

  describe "#replace_sources" do
    subject(:updated_content) { preparer.replace_sources(credentials) }

    let(:credentials) do
      [Dependabot::Credential.new({
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }), Dependabot::Credential.new({
        "type" => "python_index",
        "index-url" => "https://username:password@pypi.posrip.com/pypi/"
      })]
    end
    let(:pipfile_fixture_name) { "version_not_specified" }

    it "adds the source" do
      expect(updated_content).to include(
        "[[source]]\n" \
        "name = \"dependabot-inserted-index-0\"\n" \
        "url = \"https://username:password@pypi.posrip.com/pypi/\"\n"
      )
    end

    context "with auth details provided as a token" do
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }), Dependabot::Credential.new({
          "type" => "python_index",
          "index-url" => "https://pypi.posrip.com/pypi/",
          "token" => "username:password"
        })]
      end

      it "adds the source" do
        expect(updated_content).to include(
          "[[source]]\n" \
          "name = \"dependabot-inserted-index-0\"\n" \
          "url = \"https://username:password@pypi.posrip.com/pypi/\"\n"
        )
      end
    end

    context "with auth details provided in Pipfile" do
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }), Dependabot::Credential.new({
          "type" => "python_index",
          "index-url" => "https://pypi.posrip.com/pypi/",
          "token" => "username:password"
        })]
      end

      let(:pipfile_fixture_name) { "private_source_auth" }

      it "keeps source config" do
        expect(updated_content).to include(
          "[[source]]\n" \
          "name = \"internal-pypi\"\n" \
          "url = \"https://username:password@pypi.posrip.com/pypi/\"\n" \
          "verify_ssl = true\n"
        )
      end
    end
  end
end
