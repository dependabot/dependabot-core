# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_updater/npmrc_builder"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::NpmrcBuilder do
  let(:npmrc_builder) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: credentials,
      dependencies: dependencies
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end

  let(:dependencies) do
    []
  end

  describe "#npmrc_content" do
    subject(:npmrc_content) { npmrc_builder.npmrc_content }

    context "with an npmrc file" do
      let(:dependency_files) { project_dependency_files("generic/npmrc_auth_token") }

      it "returns the npmrc file unaltered" do
        expect(npmrc_content)
          .to eq(fixture("projects", "generic", "npmrc_auth_token", ".npmrc"))
      end

      context "when it needs to sanitize the authToken" do
        let(:dependency_files) { project_dependency_files("generic/npmrc_env_auth_token") }

        it "removes the env variable use" do
          expect(npmrc_content)
            .to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n")
        end
      end

      context "when it needs auth sanitizing" do
        let(:dependency_files) { project_dependency_files("generic/npmrc_env_auth") }

        it "removes the env variable use" do
          expect(npmrc_content)
            .to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n")
        end
      end
    end

    context "with no private sources and some credentials" do
      let(:dependency_files) { project_dependency_files("generic/simple") }

      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }), Dependabot::Credential.new({
          "type" => "npm_registry",
          "registry" => "registry.npmjs.org",
          "token" => "my_token"
        })]
      end

      it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

      context "when using basic auth" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }), Dependabot::Credential.new({
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "my:token"
          })]
        end

        it "includes Basic auth details" do
          expect(npmrc_content).to eq(
            "always-auth = true\n//registry.npmjs.org/:_auth=bXk6dG9rZW4="
          )
        end
      end

      context "when dealing with an npmrc file" do
        let(:dependency_files) { project_dependency_files("generic/npmrc_auth_token") }

        it "appends to the npmrc file" do
          expect(npmrc_content)
            .to include(fixture("projects", "generic", "npmrc_auth_token", ".npmrc"))
          expect(npmrc_content)
            .to end_with("\n\n//registry.npmjs.org/:_authToken=my_token")
        end
      end
    end

    context "with a yarn.lock" do
      context "with no private sources and no credentials" do
        let(:dependency_files) { project_dependency_files("yarn/simple") }

        it { is_expected.to eq("") }

        context "when dealing with a yarnrc file" do
          let(:dependency_files) { project_dependency_files("yarn/yarnrc_global_registry") }

          it "uses the yarnrc file registry" do
            expect(npmrc_content).to eq(
              "registry = https://npm-proxy.fury.io/password/dependabot/\n"
            )
          end
        end
      end

      context "with no private sources and credentials cleared" do
        let(:dependency_files) { project_dependency_files("yarn/simple") }
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com"
          }), Dependabot::Credential.new({
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org"
          })]
        end

        it { is_expected.to eq("") }
      end

      context "with a private source used for some dependencies" do
        let(:dependency_files) { project_dependency_files("yarn/private_source") }

        it { is_expected.to eq("") }

        context "when dealing with some credentials" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org",
              "token" => "my_token"
            })]
          end

          it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

          context "when the registry has a trailing slash" do
            let(:credentials) do
              [Dependabot::Credential.new({
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }), Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "artifactory.jfrog.com" \
                              "/artifactory/api/npm/dependabot/",
                "token" => "my_token"
              })]
            end

            it "only adds a single trailing slash" do
              expect(npmrc_content)
                .to eq("//artifactory.jfrog.com/" \
                       "artifactory/api/npm/dependabot/:_authToken=my_token")
            end
          end

          context "when it matches a scoped package" do
            let(:credentials) do
              [Dependabot::Credential.new({
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }), Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot",
                "token" => "my_token"
              }), Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dep",
                "token" => "my_other_token"
              })]
            end

            it "adds auth details, and scopes them correctly" do
              expect(npmrc_content)
                .to eq("@dependabot:registry=https://npm.fury.io/dependabot\n" \
                       "//npm.fury.io/dependabot/:_authToken=my_token\n" \
                       "//npm.fury.io/dep/:_authToken=my_other_token")
            end

            context "when using bintray" do
              let(:credentials) do
                [Dependabot::Credential.new({
                  "type" => "git_source",
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                }), Dependabot::Credential.new({
                  "type" => "npm_registry",
                  "registry" => "api.bintray.com/npm/dependabot/npm-private",
                  "token" => "my_token"
                })]
              end

              it "adds auth details, and scopes them correctly" do
                expect(npmrc_content)
                  .to eq(
                    "@dependabot:registry=https://api.bintray.com/npm/" \
                    "dependabot/npm-private\n" \
                    "//api.bintray.com/npm/dependabot/" \
                    "npm-private/:_authToken=my_token"
                  )
              end
            end

            context "with scoped registry configured in npmrc" do
              let(:dependency_files) { project_dependency_files("yarn/scoped_private_source_with_npmrc") }

              let(:credentials) do
                [Dependabot::Credential.new({
                  "type" => "git_source",
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                }), Dependabot::Credential.new({
                  "type" => "npm_registry",
                  "registry" => "registry.dependabot.com/npm-private",
                  "token" => "my_token"
                })]
              end

              it "adds auth details without replacing the global registry" do
                expect(npmrc_content)
                  .to eq(
                    "registry=https://registry.yarnpkg.com\n" \
                    "@dependabot:always-auth=true\n" \
                    "@dependabot:registry=https://registry.dependabot.com\n" \
                    "\n" \
                    "//registry.dependabot.com/npm-private/:_authToken=my_token"
                  )
              end
            end

            context "with an irrelevant package-lock.json" do
              let(:dependency_files) { project_dependency_files("npm6_and_yarn/private_source_empty_npm_lock") }

              it "adds auth details, and scopes them correctly" do
                expect(npmrc_content)
                  .to eq(
                    "@dependabot:registry=https://npm.fury.io/dependabot\n" \
                    "//npm.fury.io/dependabot/:_authToken=my_token\n" \
                    "//npm.fury.io/dep/:_authToken=my_other_token"
                  )
              end
            end
          end
        end
      end

      context "with a private source used for some deps and creds cleared" do
        let(:dependency_files) { project_dependency_files("yarn/private_source") }

        context "when dealing with some credentials" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org"
            })]
          end

          it { is_expected.to eq("") }
        end

        context "when it matches a scoped package" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dep"
            })]
          end

          it "adds auth details, and scopes them correctly" do
            expect(npmrc_content)
              .to eq("@dependabot:registry=https://npm.fury.io/dependabot")
          end
        end
      end

      context "with a private source used for all dependencies" do
        let(:dependency_files) { project_dependency_files("yarn/all_private") }

        it { is_expected.to eq("") }

        context "when dealing with credentials for the private source" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot",
              "token" => "my_token"
            })]
          end

          it "adds a global registry line, and auth details" do
            expect(npmrc_content)
              .to eq("registry = https://npm.fury.io/dependabot\n" \
                     "//npm.fury.io/dependabot/:_authToken=my_token\n" \
                     "always-auth = true")
          end

          context "when dealing with an npmrc file" do
            let(:dependency_files) { project_dependency_files("yarn/all_private_env_global_auth") }

            it "extends the already existing npmrc" do
              expect(npmrc_content)
                .to eq("always-auth = true\n" \
                       "strict-ssl = true\n" \
                       "//npm.fury.io/dependabot/:_authToken=secret_token\n" \
                       "registry = https://npm.fury.io/dependabot\n" \
                       "//npm.fury.io/dependabot/:_authToken=my_token\n" \
                       "always-auth = true\n")
            end

            context "when it uses environment variables everywhere" do
              let(:dependency_files) { project_dependency_files("yarn/all_private_env_registry") }

              it "extends the already existing npmrc" do
                expect(npmrc_content)
                  .to eq("//dependabot.jfrog.io/dependabot/api/npm/" \
                         "platform-npm/:always-auth=true\n" \
                         "always-auth = true\n" \
                         "registry = https://npm.fury.io/dependabot\n" \
                         "//npm.fury.io/dependabot/:_authToken=my_token\n" \
                         "always-auth = true\n")
              end
            end
          end

          context "when dealing with a yarnrc file" do
            let(:dependency_files) { project_dependency_files("yarn/all_private_global_registry") }

            it "uses the yarnrc file registry" do
              expect(npmrc_content).to eq(
                "registry = https://npm-proxy.fury.io/password/dependabot/\n\n" \
                "//npm.fury.io/dependabot/:_authToken=my_token"
              )
            end

            context "when it doesn't contain details of the registry" do
              let(:dependency_files) { project_dependency_files("yarn/all_private_offline_mirror") }

              it "adds a global registry line based on the lockfile details" do
                expect(npmrc_content)
                  .to eq("registry = https://npm.fury.io/dependabot\n" \
                         "//npm.fury.io/dependabot/:_authToken=my_token\n" \
                         "always-auth = true")
              end
            end
          end
        end
      end

      context "with a private source used for all deps with creds cleared" do
        let(:dependency_files) { project_dependency_files("yarn/all_private") }

        it { is_expected.to eq("") }

        context "when dealing with credentials for the private source" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot"
            })]
          end

          it "adds a global registry line, and auth details" do
            expect(npmrc_content)
              .to eq("registry = https://npm.fury.io/dependabot\n" \
                     "always-auth = true")
          end

          context "when dealing with an npmrc file" do
            let(:dependency_files) { project_dependency_files("yarn/all_private_env_global_auth") }

            it "extends the already existing npmrc" do
              expect(npmrc_content)
                .to eq("always-auth = true\n" \
                       "strict-ssl = true\n" \
                       "//npm.fury.io/dependabot/:_authToken=secret_token\n" \
                       "registry = https://npm.fury.io/dependabot\n" \
                       "always-auth = true\n")
            end

            context "when it uses environment variables everywhere" do
              let(:dependency_files) { project_dependency_files("yarn/all_private_env_registry") }

              it "extends the already existing npmrc" do
                expect(npmrc_content)
                  .to eq("//dependabot.jfrog.io/dependabot/api/npm/" \
                         "platform-npm/:always-auth=true\n" \
                         "always-auth = true\n" \
                         "registry = https://npm.fury.io/dependabot\n" \
                         "always-auth = true\n")
              end
            end
          end

          context "when dealing with a yarnrc file" do
            let(:dependency_files) { project_dependency_files("yarn/all_private_global_registry") }

            it "uses the yarnrc file registry" do
              expect(npmrc_content).to eq(
                "registry = https://npm-proxy.fury.io/password/dependabot/\n"
              )
            end

            context "when it doesn't contain details of the registry" do
              let(:dependency_files) { project_dependency_files("yarn/all_private_offline_mirror") }

              it "adds a global registry line based on the lockfile details" do
                expect(npmrc_content)
                  .to eq("registry = https://npm.fury.io/dependabot\n" \
                         "always-auth = true")
              end
            end
          end
        end
      end
    end

    context "with an npm-shrinkwrap.json" do
      let(:dependency_files) do
        project_dependency_files("npm6/private_source_shrinkwrap")
      end
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "git_source",
          "host" => "github.com"
        }), Dependabot::Credential.new({
          "type" => "npm_registry",
          "registry" => "host.docker.internal"
        })]
      end

      it "creates npmrc file with inferred registry" do
        expect(npmrc_content)
          .to include("registry = https://host.docker.internal")
      end
    end

    context "with a package-lock.json" do
      context "with no private sources and credentials cleared" do
        let(:dependency_files) { project_dependency_files("npm6/private_source") }

        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com"
          }), Dependabot::Credential.new({
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org"
          })]
        end

        it { is_expected.to eq("") }

        context "when dealing with an npmrc file" do
          let(:dependency_files) { project_dependency_files("npm6/private_source_npmrc") }

          it "does not append to the npmrc file" do
            expect(npmrc_content)
              .to eq(fixture("projects", "npm6", "private_source_npmrc", ".npmrc"))
          end
        end
      end

      context "with a private source used for some dependencies" do
        let(:dependency_files) { project_dependency_files("npm6/private_source") }

        it { is_expected.to eq("") }

        context "when dealing with some credentials" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org",
              "token" => "my_token"
            })]
          end

          it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

          context "when it matches a scoped package" do
            let(:credentials) do
              [Dependabot::Credential.new({
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }), Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot",
                "token" => "my_token"
              })]
            end

            it "adds auth details, and scopes them correctly" do
              expect(npmrc_content)
                .to eq("@dependabot:registry=https://npm.fury.io/dependabot\n" \
                       "//npm.fury.io/dependabot/:_authToken=my_token")
            end
          end
        end

        context "with scoped registry configured in npmrc" do
          let(:dependency_files) { project_dependency_files("npm8/scoped_private_source_with_npmrc") }

          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "registry.dependabot.com/npm-private",
              "token" => "my_token"
            })]
          end

          it "adds auth details without replacing the global registry" do
            expect(npmrc_content)
              .to eq(
                "registry=https://registry.yarnpkg.com\n" \
                "@dependabot:always-auth=true\n" \
                "@dependabot:registry=https://registry.dependabot.com\n" \
                "\n" \
                "//registry.dependabot.com/npm-private/:_authToken=my_token"
              )
          end
        end
      end

      context "with a private source used for some deps and creds cleared" do
        let(:dependency_files) { project_dependency_files("npm6/private_source") }

        it { is_expected.to eq("") }

        context "when dealing with some credentials" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org"
            })]
          end

          it { is_expected.to eq("") }

          context "when it matches a scoped package" do
            let(:credentials) do
              [Dependabot::Credential.new({
                "type" => "git_source",
                "host" => "github.com"
              }), Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot"
              })]
            end

            it "adds auth details, and scopes them correctly" do
              expect(npmrc_content)
                .to eq("@dependabot:registry=https://npm.fury.io/dependabot")
            end
          end

          context "when it matches a scoped package with lowercase escaped slash" do
            let(:dependency_files) { project_dependency_files("npm6/private_source_lower") }
            let(:credentials) do
              [Dependabot::Credential.new({
                "type" => "git_source",
                "host" => "github.com"
              }), Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot"
              })]
            end

            it "adds auth details, and scopes them correctly" do
              expect(npmrc_content)
                .to eq("@dependabot:registry=https://npm.fury.io/dependabot")
            end
          end
        end
      end

      context "with a private source used for all dependencies" do
        let(:dependency_files) { project_dependency_files("npm6/all_private") }

        it { is_expected.to eq("") }

        context "when dealing with credentials for the private source" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot",
              "token" => "my_token"
            })]
          end

          it "adds a global registry line, and token auth details" do
            expect(npmrc_content)
              .to eq("registry = https://npm.fury.io/dependabot\n" \
                     "//npm.fury.io/dependabot/:_authToken=my_token\n" \
                     "always-auth = true")
          end

          context "with basic auth credentials" do
            let(:credentials) do
              [Dependabot::Credential.new({
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }), Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot",
                "token" => "secret:token"
              })]
            end

            it "adds a global registry line, and Basic auth details" do
              expect(npmrc_content)
                .to eq("registry = https://npm.fury.io/dependabot\n" \
                       "//npm.fury.io/dependabot/:_auth=c2VjcmV0OnRva2Vu\n" \
                       "always-auth = true")
            end
          end

          context "when dealing with an npmrc file" do
            let(:dependency_files) { project_dependency_files("npm6/all_private_env_global_auth") }

            it "populates the already existing npmrc" do
              expect(npmrc_content)
                .to eq("always-auth = true\n" \
                       "strict-ssl = true\n" \
                       "//npm.fury.io/dependabot/:_authToken=secret_token\n" \
                       "registry = https://npm.fury.io/dependabot\n" \
                       "//npm.fury.io/dependabot/:_authToken=my_token\n" \
                       "always-auth = true\n")
            end

            context "with basic auth credentials" do
              let(:credentials) do
                [Dependabot::Credential.new({
                  "type" => "git_source",
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                }), Dependabot::Credential.new({
                  "type" => "npm_registry",
                  "registry" => "npm.fury.io/dependabot",
                  "token" => "secret:token"
                })]
              end

              it "populates the already existing npmrc" do
                expect(npmrc_content)
                  .to eq("always-auth = true\n" \
                         "strict-ssl = true\n" \
                         "//npm.fury.io/dependabot/:_authToken=secret_token\n" \
                         "registry = https://npm.fury.io/dependabot\n" \
                         "//npm.fury.io/dependabot/:_auth=c2VjcmV0OnRva2Vu\n" \
                         "always-auth = true\n")
              end
            end
          end

          context "when dealing with an npmrc file with timeout" do
            let(:dependency_files) { project_dependency_files("npm6/npmrc_env_timeout") }

            it "populates the already existing npmrc" do
              expect(npmrc_content)
                .to eq("legacy-peer-deps=true\n" \
                       "loglevel=verbose\n\n" \
                       "fetch-retries=3\n" \
                       "fetch-retry-maxtimeout=4\n" \
                       "fetch-retry-mintimeout=3\n" \
                       "fetch-timeout=400000\n\n" \
                       "always-auth = true\n" \
                       "strict-ssl = true\n" \
                       "//npm.fury.io/dependabot/:_authToken=secret_token\n" \
                       "registry = https://npm.fury.io/dependabot\n" \
                       "//npm.fury.io/dependabot/:_authToken=my_token\n" \
                       "always-auth = true\n")
            end

            context "with basic auth credentials" do
              let(:credentials) do
                [Dependabot::Credential.new({
                  "type" => "git_source",
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                }), Dependabot::Credential.new({
                  "type" => "npm_registry",
                  "registry" => "npm.fury.io/dependabot",
                  "token" => "secret:token"
                })]
              end

              it "populates the already existing npmrc" do
                expect(npmrc_content)
                  .to eq("legacy-peer-deps=true\n" \
                         "loglevel=verbose\n\n" \
                         "fetch-retries=3\n" \
                         "fetch-retry-maxtimeout=4\n" \
                         "fetch-retry-mintimeout=3\n" \
                         "fetch-timeout=400000\n\n" \
                         "always-auth = true\n" \
                         "strict-ssl = true\n" \
                         "//npm.fury.io/dependabot/:_authToken=secret_token\n" \
                         "registry = https://npm.fury.io/dependabot\n" \
                         "//npm.fury.io/dependabot/:_auth=c2VjcmV0OnRva2Vu\n" \
                         "always-auth = true\n")
              end
            end
          end
        end
      end

      context "with a private source used for all deps and creds cleared" do
        let(:dependency_files) { project_dependency_files("npm6/all_private") }

        it { is_expected.to eq("") }

        context "when dealing with credentials for the private source" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "git_source",
              "host" => "github.com"
            }), Dependabot::Credential.new({
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot"
            })]
          end

          it "adds a global registry line, and token auth details" do
            expect(npmrc_content)
              .to eq("registry = https://npm.fury.io/dependabot\n" \
                     "always-auth = true")
          end

          context "with basic auth credentials cleared" do
            let(:credentials) do
              [Dependabot::Credential.new({
                "type" => "git_source",
                "host" => "github.com"
              }), Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot"
              })]
            end

            it "adds a global registry line, and Basic auth details" do
              expect(npmrc_content)
                .to eq("registry = https://npm.fury.io/dependabot\n" \
                       "always-auth = true")
            end
          end

          context "when dealing with an npmrc file" do
            let(:dependency_files) { project_dependency_files("npm6/all_private_env_global_auth") }

            it "populates the already existing npmrc" do
              expect(npmrc_content)
                .to eq("always-auth = true\n" \
                       "strict-ssl = true\n" \
                       "//npm.fury.io/dependabot/:_authToken=secret_token\n" \
                       "registry = https://npm.fury.io/dependabot\n" \
                       "always-auth = true\n")
            end

            context "with basic auth credentials" do
              let(:credentials) do
                [Dependabot::Credential.new({
                  "type" => "git_source",
                  "host" => "github.com"
                }), Dependabot::Credential.new({
                  "type" => "npm_registry",
                  "registry" => "npm.fury.io/dependabot"
                })]
              end

              it "populates the already existing npmrc" do
                expect(npmrc_content)
                  .to eq("always-auth = true\n" \
                         "strict-ssl = true\n" \
                         "//npm.fury.io/dependabot/:_authToken=secret_token\n" \
                         "registry = https://npm.fury.io/dependabot\n" \
                         "always-auth = true\n")
              end
            end
          end
        end
      end
    end

    context "with a pnpm-lock.yaml" do
      let(:dependency_files) { project_dependency_files("pnpm/private_source") }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(name: "@dependabot/etag", version: "1.8.1", package_manager: "npm_and_yarn",
                                     requirements: []),
          Dependabot::Dependency.new(name: "semver", version: "7.5.4", package_manager: "npm_and_yarn",
                                     requirements: [])
        ]
      end

      context "when a private registry configured that lists a specific dependency" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "npm_registry",
            "registry" => "pkgs.dev.azure.com/dependabot/my-project/_packaging/my-feed/npm/registry/",
            "token" => "my_token"
          })]
        end

        before do
          stub_request(:get, "https://pkgs.dev.azure.com/dependabot/my-project/_packaging/my-feed/npm/registry/@dependabot%2Fetag")
            .with(headers: { "Authorization" => "Bearer my_token" })
            .to_return(status: 200, body: "{}")
          stub_request(:get, "https://pkgs.dev.azure.com/dependabot/my-project/_packaging/my-feed/npm/registry/semver")
            .with(headers: { "Authorization" => "Bearer my_token" })
            .to_return(status: 404)
        end

        it "adds a scoped registry for the dependency" do
          expect(npmrc_content).to include("@dependabot:registry=https://pkgs.dev.azure.com/dependabot/my-project/_packaging/my-feed/npm/registry/")
        end
      end
    end

    context "when dealing with registry scope generation" do
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "npm_registry",
          "registry" => "registry.npmjs.org"
        }),
         Dependabot::Credential.new({
           "type" => "npm_registry",
           "registry" => "npm.pkg.github.com",
           "token" => "my_token"
         })]
      end

      context "when no packages resolve to the private registry" do
        let(:dependency_files) do
          project_dependency_files("npm8/simple")
        end

        it "adds only the token auth details" do
          expect(npmrc_content).to eql("//npm.pkg.github.com/:_authToken=my_token")
        end
      end

      context "when no packages resolve to the private registry with v3" do
        let(:dependency_files) do
          project_dependency_files("npm9/simple")
        end

        it "adds only the token auth details" do
          expect(npmrc_content).to eql("//npm.pkg.github.com/:_authToken=my_token")
        end
      end

      context "when a public package of a different scope appears with an npmrc with v3" do
        let(:dependency_files) do
          project_dependency_files("npm9/private-public")
        end

        it "adds only the token auth details" do
          expect(npmrc_content).to eql(<<~NPMRC.chomp)
            @dependabot:registry=https://npm.pkg.github.com

            //npm.pkg.github.com/:_authToken=my_token
          NPMRC
        end
      end

      context "when there are only packages that resolve to the private registry" do
        let(:dependency_files) do
          project_dependency_files("npm8/private_registry_ghpr_only")
        end

        it "adds a global registry line, the scoped registry and token auth details" do
          expect(npmrc_content)
            .to eq(<<~NPMRC.chomp)
              registry = https://npm.pkg.github.com
              //npm.pkg.github.com/:_authToken=my_token
              always-auth = true
              @dsp-testing:registry=https://npm.pkg.github.com
            NPMRC
        end
      end

      context "when there are some packages that resolve to the private registry" do
        let(:dependency_files) do
          project_dependency_files("npm8/private_registry_ghpr_and_npm")
        end

        it "adds the scoped registry and token auth details" do
          expect(npmrc_content)
            .to eq(<<~NPMRC.chomp)
              @dsp-testing:registry=https://npm.pkg.github.com
              //npm.pkg.github.com/:_authToken=my_token
            NPMRC
        end
      end

      context "when there are some packages that resolve to the private registry, but include a port number" do
        let(:dependency_files) do
          project_dependency_files("npm8/private_registry_ghpr_with_ports")
        end

        it "adds the scoped registry and token auth details" do
          expect(npmrc_content)
            .to eq(<<~NPMRC.chomp)
              @dsp-testing:registry=https://npm.pkg.github.com
              //npm.pkg.github.com/:_authToken=my_token
            NPMRC
        end
      end
    end
  end
end
