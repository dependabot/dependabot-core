# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/pipfile_preparer"

RSpec.describe Dependabot::Python::FileUpdater::PipfilePreparer do
  let(:preparer) do
    described_class.new(pipfile_content: pipfile_content, lockfile: lockfile)
  end

  let(:pipfile_content) do
    fixture("pipfiles", pipfile_fixture_name)
  end
  let(:pipfile_fixture_name) { "version_not_specified" }

  describe "#freeze_top_level_dependencies_except" do
    subject(:updated_content) do
      preparer.freeze_top_level_dependencies_except(dependencies)
    end

    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      ]
    end
    let(:dependency_name) { "requests" }
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "Pipfile.lock",
        content: fixture("lockfiles", lockfile_fixture_name)
      )
    end
    let(:pipfile_fixture_name) { "version_not_specified" }
    let(:lockfile_fixture_name) { "version_not_specified.lock" }

    context "with a dev dependency that needs locking" do
      let(:dependency_name) { "requests" }
      it "locks the dependency" do
        expect(updated_content).to include('pytest = "==3.2.3"')
      end
    end

    context "with a production dependency that needs locking" do
      let(:dependency_name) { "pytest" }
      it "locks the dependency" do
        expect(updated_content).to include('requests = "==2.18.0"')
      end

      context "and appears as a string in the lockfile" do
        # Requests has been edited to use a string, rather than hash of details
        # in its lockfile
        let(:lockfile_fixture_name) { "edited.lock" }

        it "locks the dependency" do
          expect(updated_content).to include('requests = "==2.18.0"')
        end
      end

      context "and appears as an array in the lockfile (i.e., unusable)" do
        let(:lockfile_fixture_name) { "edited_array.lock" }

        it "does not lock the dependency" do
          expect(updated_content).to include('requests = "*"')
        end
      end

      context "that is a git dependency" do
        let(:pipfile_fixture_name) { "git_source_no_ref" }
        let(:lockfile_fixture_name) { "git_source_no_ref.lock" }

        it "locks the dependency" do
          expect(updated_content).to include(
            "[packages.pythonfinder]\n" \
            "git = \"https://github.com/sarugaku/pythonfinder.git\"\n" \
            "ref = \"9ee85b83290850f99dec2c0ec58a084305047347\"\n"
          )
        end

        context "but already has a reference" do
          let(:pipfile_fixture_name) { "git_source" }
          let(:lockfile_fixture_name) { "git_source.lock" }

          it "leaves the dependency alone" do
            expect(updated_content).to include(
              "[packages.pythonfinder]\n" \
              "git = \"https://github.com/sarugaku/pythonfinder.git\"\n" \
              "ref = \"v0.1.2\"\n"
            )
          end
        end
      end
    end
  end

  describe "#replace_sources" do
    subject(:updated_content) { preparer.replace_sources(credentials) }

    let(:credentials) do
      [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }, {
        "type" => "python_index",
        "index-url" => "https://username:password@pypi.posrip.com/pypi/"
      }]
    end
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "Pipfile.lock",
        content: fixture("lockfiles", lockfile_fixture_name)
      )
    end
    let(:pipfile_fixture_name) { "version_not_specified" }
    let(:lockfile_fixture_name) { "version_not_specified.lock" }

    it "adds the source" do
      expect(updated_content).
        to include("https://username:password@pypi.posrip.com/pypi/")
    end

    context "with auth details provided as a token" do
      let(:credentials) do
        [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }, {
          "type" => "python_index",
          "index-url" => "https://pypi.posrip.com/pypi/",
          "token" => "username:password"
        }]
      end

      it "adds the source" do
        expect(updated_content).
          to include("https://username:password@pypi.posrip.com/pypi/")
      end
    end

    context "with auth details provided in Pipfile" do
      let(:credentials) do
        [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }, {
          "type" => "python_index",
          "index-url" => "https://pypi.posrip.com/pypi/",
          "token" => "username:password"
        }]
      end

      let(:pipfile_fixture_name) { "private_source_auth" }

      it "keeps source config" do
        expect(updated_content).to include(
          "[[source]]\n" \
          "name = \"pypi\"\n" \
          "url = \"https://username:password@pypi.posrip.com/pypi/\"\n" \
          "verify_ssl = true\n"
        )
      end
    end
  end
end
