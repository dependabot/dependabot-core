# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_updaters/java_script/npm_and_yarn/npmrc_builder"

RSpec.describe Dependabot::FileUpdaters::JavaScript::NpmAndYarn::NpmrcBuilder do
  let(:npmrc_builder) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_files) { [package_json, yarn_lock] }
  let(:credentials) do
    [{
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:package_json) do
    Dependabot::DependencyFile.new(
      content: fixture("javascript", "package_files", manifest_fixture_name),
      name: "package.json"
    )
  end
  let(:package_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("javascript", "npm_lockfiles", npm_lock_fixture_name)
    )
  end
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: fixture("javascript", "yarn_lockfiles", yarn_lock_fixture_name)
    )
  end
  let(:npmrc) do
    Dependabot::DependencyFile.new(
      name: ".npmrc",
      content: fixture("javascript", "npmrc", npmrc_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "package.json" }
  let(:npm_lock_fixture_name) { "package-lock.json" }
  let(:yarn_lock_fixture_name) { "yarn.lock" }
  let(:npmrc_fixture_name) { "auth_token" }

  describe "#npmrc_content" do
    subject(:npmrc_content) { npmrc_builder.npmrc_content }

    context "with a yarn.lock" do
      let(:dependency_files) { [package_json, yarn_lock] }

      context "with no private sources and no credentials" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "yarn.lock" }
        it { is_expected.to eq("") }

        context "and an npmrc file" do
          let(:dependency_files) { [package_json, yarn_lock, npmrc] }

          it "returns the npmrc file unaltered" do
            expect(npmrc_content).
              to eq(fixture("javascript", "npmrc", npmrc_fixture_name))
          end

          context "that needs an authToken sanitizing" do
            let(:npmrc_fixture_name) { "env_auth_token" }

            it "removes the env variable use" do
              expect(npmrc_content).
                to eq(
                  "@dependabot:registry=https://npm.fury.io/dependabot/\n\n"
                )
            end
          end

          context "that needs an auth sanitizing" do
            let(:npmrc_fixture_name) { "env_auth" }

            it "removes the env variable use" do
              expect(npmrc_content).
                to eq(
                  "@dependabot:registry=https://npm.fury.io/dependabot/\n\n"
                )
            end
          end
        end
      end

      context "with no private sources and some credentials" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "yarn.lock" }
        let(:credentials) do
          [
            {
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "registry" => "registry.npmjs.org",
              "token" => "my_token"
            }
          ]
        end
        it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

        context "that uses basic auth" do
          let(:credentials) do
            [
              {
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "registry" => "registry.npmjs.org",
                "token" => "my:token"
              }
            ]
          end
          it "includes Basic auth details" do
            expect(npmrc_content).to eq(
              "always-auth = true\n//registry.npmjs.org/:_auth=bXk6dG9rZW4="
            )
          end
        end

        context "and an npmrc file" do
          let(:dependency_files) { [package_json, yarn_lock, npmrc] }

          it "appends to the npmrc file" do
            expect(npmrc_content).
              to include(fixture("javascript", "npmrc", npmrc_fixture_name))
            expect(npmrc_content).
              to end_with("\n\n//registry.npmjs.org/:_authToken=my_token")
          end
        end
      end

      context "with a private source used for some dependencies" do
        let(:manifest_fixture_name) { "private_source.json" }
        let(:yarn_lock_fixture_name) { "private_source.lock" }
        it { is_expected.to eq("") }

        context "and some credentials" do
          let(:credentials) do
            [
              {
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "registry" => "registry.npmjs.org",
                "token" => "my_token"
              }
            ]
          end
          it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

          context "that match a scoped package" do
            let(:credentials) do
              [
                {
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                },
                {
                  "registry" => "npm.fury.io/dependabot",
                  "token" => "my_token"
                }
              ]
            end
            it "adds auth details, and scopes them correctly" do
              expect(npmrc_content).
                to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n"\
                      "//npm.fury.io/dependabot/:_authToken=my_token")
            end
          end
        end
      end

      context "with a private source used for all dependencies" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "all_private.lock" }
        it { is_expected.to eq("") }

        context "and credentials for the private source" do
          let(:credentials) do
            [
              {
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "registry" => "npm.fury.io/dependabot",
                "token" => "my_token"
              }
            ]
          end

          it "adds a global registry line, and auth details" do
            expect(npmrc_content).
              to eq("registry = https://npm.fury.io/dependabot\n"\
                    "_auth = my_token\n"\
                    "always-auth = true\n"\
                    "//npm.fury.io/dependabot/:_authToken=my_token")
          end

          context "and an npmrc file" do
            let(:dependency_files) { [package_json, yarn_lock, npmrc] }
            let(:npmrc_fixture_name) { "env_global_auth" }

            it "populates the already existing npmrc" do
              expect(npmrc_content).
                to eq("_auth = my_token\n"\
                      "always-auth = true\n"\
                      "strict-ssl = true\n"\
                      "//npm.fury.io/dependabot/:_authToken=secret_token\n\n"\
                      "//npm.fury.io/dependabot/:_authToken=my_token")
            end
          end
        end
      end
    end

    context "with a package-lock.json" do
      let(:dependency_files) { [package_json, package_lock] }

      context "with no private sources and no credentials" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "package-lock.json" }
        it { is_expected.to eq("") }

        context "and an npmrc file" do
          let(:dependency_files) { [package_json, package_lock, npmrc] }

          it "returns the npmrc file unaltered" do
            expect(npmrc_content).
              to eq(fixture("javascript", "npmrc", npmrc_fixture_name))
          end

          context "that need sanitizing" do
            let(:npmrc_fixture_name) { "env_auth_token" }

            it "removes the env variable use" do
              expect(npmrc_content).
                to eq(
                  "@dependabot:registry=https://npm.fury.io/dependabot/\n\n"
                )
            end
          end
        end
      end

      context "with no private sources and some credentials" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "package-lock.json" }
        let(:credentials) do
          [
            {
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "registry" => "registry.npmjs.org",
              "token" => "my_token"
            }
          ]
        end
        it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

        context "and an npmrc file" do
          let(:dependency_files) { [package_json, package_lock, npmrc] }

          it "appends to the npmrc file" do
            expect(npmrc_content).
              to include(fixture("javascript", "npmrc", npmrc_fixture_name))
            expect(npmrc_content).
              to end_with("\n\n//registry.npmjs.org/:_authToken=my_token")
          end
        end
      end

      context "with a private source used for some dependencies" do
        let(:manifest_fixture_name) { "private_source.json" }
        let(:npm_lock_fixture_name) { "private_source.json" }
        it { is_expected.to eq("") }

        context "and some credentials" do
          let(:credentials) do
            [
              {
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "registry" => "registry.npmjs.org",
                "token" => "my_token"
              }
            ]
          end
          it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

          context "that match a scoped package" do
            let(:credentials) do
              [
                {
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                },
                {
                  "registry" => "npm.fury.io/dependabot",
                  "token" => "my_token"
                }
              ]
            end
            it "adds auth details, and scopes them correctly" do
              expect(npmrc_content).
                to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n"\
                      "//npm.fury.io/dependabot/:_authToken=my_token")
            end
          end
        end
      end

      context "with a private source used for all dependencies" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "all_private.json" }
        it { is_expected.to eq("") }

        context "and credentials for the private source" do
          let(:credentials) do
            [
              {
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "registry" => "npm.fury.io/dependabot",
                "token" => "my_token"
              }
            ]
          end

          it "adds a global registry line, and auth details" do
            expect(npmrc_content).
              to eq("registry = https://npm.fury.io/dependabot\n"\
                    "_auth = my_token\n"\
                    "always-auth = true\n"\
                    "//npm.fury.io/dependabot/:_authToken=my_token")
          end

          context "and an npmrc file" do
            let(:dependency_files) { [package_json, package_lock, npmrc] }
            let(:npmrc_fixture_name) { "env_global_auth" }

            it "populates the already existing npmrc" do
              expect(npmrc_content).
                to eq("_auth = my_token\n"\
                      "always-auth = true\n"\
                      "strict-ssl = true\n"\
                      "//npm.fury.io/dependabot/:_authToken=secret_token\n\n"\
                      "//npm.fury.io/dependabot/:_authToken=my_token")
            end
          end
        end
      end
    end
  end
end
