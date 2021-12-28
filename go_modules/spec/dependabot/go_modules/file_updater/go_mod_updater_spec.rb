# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/file_updater/go_mod_updater"

RSpec.describe Dependabot::GoModules::FileUpdater::GoModUpdater do
  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      credentials: credentials,
      repo_contents_path: repo_contents_path,
      directory: directory,
      options: { tidy: tidy, vendor: false, goprivate: goprivate }
    )
  end

  let(:project_name) { "simple" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:go_mod_content) { fixture("projects", project_name, "go.mod") }
  let(:tidy) { true }
  let(:directory) { "/" }
  let(:goprivate) { "*" }

  let(:credentials) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      previous_version: dependency_previous_version,
      previous_requirements: previous_requirements,
      package_manager: "go_modules"
    )
  end

  describe "#updated_go_mod_content" do
    subject(:updated_go_mod_content) { updater.updated_go_mod_content }

    context "for a top level dependency" do
      let(:dependency_name) { "rsc.io/quote" }
      let(:dependency_version) { "v1.4.0" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) { previous_requirements }
      let(:previous_requirements) do
        [{
          file: "go.mod",
          requirement: "v1.4.0",
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/quote"
          }
        }]
      end

      context "if no files have changed" do
        it { is_expected.to eq(go_mod_content) }
      end

      context "when the requirement has changed" do
        let(:dependency_version) { "v1.5.2" }
        let(:requirements) do
          [{
            file: "go.mod",
            requirement: "v1.5.2",
            groups: [],
            source: {
              type: "default",
              source: "rsc.io/quote"
            }
          }]
        end

        it { is_expected.to include(%(rsc.io/quote v1.5.2\n)) }

        context "when a path-based replace directive is present" do
          let(:project_name) { "replace" }

          it { is_expected.to include(%(rsc.io/quote v1.5.2\n)) }
        end

        context "with an unrestricted goprivate" do
          let(:goprivate) { "" }

          it { is_expected.to include(%(rsc.io/quote v1.5.2\n)) }
        end

        context "with an org specific goprivate" do
          let(:goprivate) { "rsc.io/*" }

          it { is_expected.to include(%(rsc.io/quote v1.5.2\n)) }
        end

        context "for a go 1.11 go.mod" do
          let(:project_name) { "go_1.11" }

          it { is_expected.to_not include("go 1.") }
          it { is_expected.to include("module github.com/dependabot/vgotest\n\nrequire") }
        end

        context "for a go 1.12 go.mod" do
          let(:project_name) { "simple" }

          it { is_expected.to include("go 1.12") }
        end

        context "for a go 1.13 go.mod" do
          let(:project_name) { "go_1.13" }

          it { is_expected.to include("go 1.13") }

          it "doesn't add additional go 1.17 requirement sections" do
            is_expected.to include("require").once
          end
        end

        context "for a go 1.17 go.mod" do
          let(:project_name) { "go_1.17" }

          it { is_expected.to include("go 1.17") }

          it "preserves the two requirements sections" do
            is_expected.to include("require").twice
          end
        end

        context "when a retract directive is present" do
          let(:project_name) { "go_retracted" }

          it { is_expected.to include("// reason for retraction") }
          it { is_expected.to include("retract v1.0.5") }
        end

        describe "a dependency who's module path has changed during an update" do
          let(:project_name) { "module_path_and_version_changed_during_update" }
          let(:dependency_name) { "gopkg.in/DATA-DOG/go-sqlmock.v1" }
          let(:dependency_version) { "v1.3.3" }
          let(:dependency_previous_version) { "v1.3.0" }
          let(:requirements) do
            [{
              file: "go.mod",
              requirement: dependency_version,
              groups: [],
              source: {
                type: "default",
                source: dependency_name
              }
            }]
          end
          let(:previous_requirements) do
            [{
              file: "go.mod",
              requirement: dependency_previous_version,
              groups: [],
              source: {
                type: "default",
                source: dependency_name
              }
            }]
          end

          it "raises the correct error" do
            error_class = Dependabot::GoModulePathMismatch
            expect { updater.updated_go_sum_content }.
              to raise_error(error_class) do |error|
              expect(error.message).to include("github.com/DATA-DOG")
            end
          end
        end

        describe "a dependency who's module path has changed (inc version)" do
          let(:project_name) { "module_path_and_version_changed" }

          it "raises the correct error" do
            error_class = Dependabot::GoModulePathMismatch
            expect { updater.updated_go_sum_content }.
              to raise_error(error_class) do |error|
              expect(error.message).to include("github.com/DATA-DOG")
            end
          end
        end

        describe "a dependency who's module path has changed" do
          let(:project_name) { "module_path_changed" }

          it "raises the correct error" do
            error_class = Dependabot::GoModulePathMismatch
            expect { updater.updated_go_sum_content }.
              to raise_error(error_class) do |error|
              expect(error.message).to include("github.com/Sirupsen")
              expect(error.message).to include("github.com/sirupsen")
            end
          end
        end

        context "with a go.sum" do
          let(:project_name) { "go_sum" }
          subject(:updated_go_mod_content) { updater.updated_go_sum_content }

          it "adds new entries to the go.sum" do
            is_expected.
              to include(%(rsc.io/quote v1.5.2 h1:))
            is_expected.
              to include(%(rsc.io/quote v1.5.2/go.mod h1:))
          end

          it "removes old entries from the go.sum" do
            is_expected.
              to_not include(%(rsc.io/quote v1.4.0 h1:))
            is_expected.
              to_not include(%(rsc.io/quote v1.4.0/go.mod h1:))
          end

          describe "a non-existent dependency with a pseudo-version" do
            let(:project_name) { "non_existent_dependency" }

            it "raises the correct error" do
              error_class = Dependabot::GitDependenciesNotReachable
              expect { updater.updated_go_sum_content }.
                to raise_error(error_class) do |error|
                  expect(error.message).to include("hmarr/404")
                  expect(error.dependency_urls).
                    to eq(["github.com/hmarr/404"])
                end
            end
          end

          describe "a dependency with a checksum mismatch" do
            let(:project_name) { "checksum_mismatch" }

            it "raises the correct error" do
              error_class = Dependabot::DependencyFileNotResolvable
              expect { updater.updated_go_sum_content }.
                to raise_error(error_class) do |error|
                  expect(error.message).to include("fatih/Color")
                end
            end
          end

          describe "a dependency that has no top-level package" do
            let(:dependency_name) { "github.com/prometheus/client_golang" }
            let(:dependency_version) { "v0.9.3" }
            let(:project_name) { "no_top_level_package" }

            it "does not raise an error" do
              expect { updater.updated_go_sum_content }.to_not raise_error
            end
          end

          describe "with a main.go that is not in the root directory" do
            let(:project_name) { "not_root" }

            it "updates the go.mod" do
              expect(updater.updated_go_mod_content).to include(
                %(rsc.io/quote v1.5.2\n)
              )
            end

            it "adds new entries to the go.sum" do
              is_expected.
                to include(%(rsc.io/quote v1.5.2 h1:))
              is_expected.
                to include(%(rsc.io/quote v1.5.2/go.mod h1:))
            end

            it "removes old entries from the go.sum" do
              is_expected.
                to_not include(%(rsc.io/quote v1.4.0 h1:))
              is_expected.
                to_not include(%(rsc.io/quote v1.4.0/go.mod h1:))
            end

            it "does not leave a temporary file lingering in the repo" do
              updater.updated_go_mod_content

              go_files = Dir.glob("#{repo_contents_path}/*.go")
              expect(go_files).to be_empty
            end
          end

          describe "with ignored go files in the root" do
            let(:project_name) { "ignored_go_files" }

            it "updates the go.mod" do
              expect(updater.updated_go_mod_content).to include(
                %(rsc.io/quote v1.5.2\n)
              )
            end
          end

          context "renamed package name" do
            let(:project_name) { "renamed_package" }
            let(:dependency_name) { "github.com/googleapis/gnostic" }
            # OpenAPIV2 has been renamed to openapiv2 in this version
            let(:dependency_version) { "v0.5.1" }

            it "raises a DependencyFileNotResolvable error" do
              error_class = Dependabot::DependencyFileNotResolvable
              expect { updater.updated_go_sum_content }.
                to raise_error(error_class) do |error|
                expect(error.message).to include("googleapis/gnostic/OpenAPIv2")
              end
            end
          end
        end

        context "without a go.sum" do
          let(:project_name) { "simple" }

          it "doesn't return a go.sum" do
            expect(updater.updated_go_sum_content).to be_nil
          end
        end
      end

      context "when it has become indirect" do
        let(:project_name) { "indirect_after_update" }
        let(:dependency_name) { "github.com/mattn/go-isatty" }
        let(:dependency_version) { "v0.0.12" }
        let(:requirements) do
          []
        end

        it do
          is_expected.to include(
            %(github.com/mattn/go-isatty v0.0.12 // indirect\n)
          )
        end
      end

      context "when it has become unneeded" do
        context "when it has become indirect" do
          let(:project_name) { "unneeded_after_update" }
          let(:dependency_version) { "v1.5.2" }
          let(:requirements) do
            []
          end

          it { is_expected.to_not include(%(rsc.io/quote)) }
        end
      end
    end

    context "when the remote end hangs up unexpectedly" do
      let(:dependency_name) { "github.com/spf13/viper" }
      let(:dependency_version) { "v1.7.1" }
      let(:dependency_previous_version) { "v1.7.1" }
      let(:requirements) { [] }
      let(:previous_requirements) { [] }
      let(:exit_status) { double(status: 128, success?: false) }
      let(:stderr) do
        <<~ERROR
          go: github.com/spf13/viper@v1.7.1 requires
          	github.com/grpc-ecosystem/grpc-gateway@v1.9.0 requires
          	gopkg.in/yaml.v2@v2.0.0-20170812160011-eb3733d160e7: invalid version: git fetch --unshallow -f origin in /opt/go/gopath/pkg/mod/cache/vcs/sha1: exit status 128:
          	fatal: The remote end hung up unexpectedly
        ERROR
      end

      before do
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, "go get -d").and_return(["", stderr, exit_status])
      end

      it { expect { subject }.to raise_error(Dependabot::DependencyFileNotResolvable, /The remote end hung up/) }
    end

    context "for an explicit indirect dependency" do
      let(:project_name) { "indirect" }
      let(:dependency_name) { "github.com/mattn/go-isatty" }
      let(:dependency_version) { "v0.0.4" }
      let(:dependency_previous_version) { "v0.0.4" }
      let(:requirements) { previous_requirements }
      let(:previous_requirements) { [] }

      context "if no files have changed" do
        it { is_expected.to eq(go_mod_content) }
      end

      context "when the version has changed" do
        let(:dependency_version) { "v0.0.12" }

        it do
          is_expected.
            to include(%(github.com/mattn/go-isatty v0.0.12 // indirect\n))
        end
      end
    end

    context "for an implicit (vgo) indirect dependency" do
      let(:dependency_name) { "rsc.io/sampler" }
      let(:dependency_version) { "v1.2.0" }
      let(:dependency_previous_version) { "v1.2.0" }
      let(:requirements) { previous_requirements }
      let(:previous_requirements) { [] }

      context "when the version has changed" do
        let(:dependency_version) { "v1.3.0" }

        it do
          is_expected.
            to include(%(rsc.io/sampler v1.3.0 // indirect\n))
        end
      end
    end

    context "for an upgraded indirect dependency" do
      let(:go_mod_fixture_name) { "upgraded_indirect_dependency.mod" }
      let(:dependency_name) { "github.com/gorilla/csrf" }
      let(:dependency_version) { "v1.7.0" }
      let(:dependency_previous_version) { "v1.6.2" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: "v1.7.0",
          groups: [],
          source: {
            type: "default",
            source: "github.com/gorilla/csrf"
          }
        }]
      end
      let(:previous_requirements) do
        [requirements.first.merge(requirement: "1.6.2")]
      end

      it do
        is_expected.to_not include("github.com/pkg/errors")
      end
    end

    context "for a revision that does not exist" do
      # The go.mod file contains a reference to a revision of
      # google.golang.org/grpc that does not exist.
      let(:project_name) { "unknown_revision" }
      let(:dependency_name) { "rsc.io/quote" }
      let(:dependency_version) { "v1.5.2" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: "v1.5.2",
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/quote"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("unknown revision v1.33.999")
        end
      end
    end

    context "for a project that references a non-existing proxy" do
      let(:project_name) { "nonexisting_proxy" }
      let(:dependency_name) { "rsc.io/quote" }
      let(:dependency_version) { "v1.5.2" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: "v1.5.2",
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/quote"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("unrecognized import path")
        end
      end
    end

    context "when module major version doesn't match (v1)" do
      let(:project_name) { "module_major_version_mismatch_v1" }
      let(:dependency_name) do
        "github.com/dependabot-fixtures/go-major-mismatch"
      end
      let(:dependency_version) { "v1.0.5" }
      let(:dependency_previous_version) { "v1.0.4" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: "v1.0.5",
          groups: [],
          source: {
            type: "default",
            source: "github.com/dependabot-fixtures/go-major-mismatch"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("go.mod has post-v1 module path")
        end
      end
    end

    context "when module major version doesn't match (v0)" do
      let(:project_name) { "module_major_version_mismatch_v0" }
      let(:dependency_name) do
        "github.com/jenkins-x/jx-api"
      end
      let(:dependency_version) { "v0.0.25" }
      let(:dependency_previous_version) { "v0.0.24" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: "v0.0.25",
          groups: [],
          source: {
            type: "default",
            source: "github.com/jenkins-x/jx-api"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("go.mod has post-v0 module path")
        end
      end
    end

    context "for a invalid pseudo version" do
      let(:project_name) { "invalid_pseudo_version" }
      let(:dependency_name) do
        "rsc.io/quote"
      end
      let(:dependency_version) { "v1.5.2" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/quote"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include(
            "go: github.com/openshift/api@v3.9.1-0.20190424152011-77b8897ec79a+incompatible: " \
            "invalid pseudo-version:"
          )
        end
      end
    end

    context "for an unknown revision version" do
      let(:project_name) { "unknown_revision_version" }
      let(:dependency_name) do
        "github.com/deislabs/oras"
      end
      let(:dependency_version) { "v0.10.0" }
      let(:dependency_previous_version) { "v0.9.0" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "default",
            source: "github.com/deislabs/oras"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include(
            "go: github.com/deislabs/oras@v0.9.0 requires\n"\
            "	github.com/docker/distribution@v0.0.0-00010101000000-000000000000: "\
            "invalid version: unknown revision"
          )
        end
      end
    end

    context "with an unreachable dependency" do
      let(:project_name) { "unreachable_dependency" }
      let(:dependency_name) { "rsc.io/quote" }
      let(:dependency_version) { "v1.5.2" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/quote"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::GitDependenciesNotReachable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("dependabot-fixtures/go-modules-private")
          expect(error.dependency_urls).
            to eq(["github.com/dependabot-fixtures/go-modules-private"])
        end
      end

      context "with an unrestricted goprivate" do
        let(:goprivate) { "" }

        it "raises the correct error" do
          expect { updater.updated_go_sum_content }.
            to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end

      context "with an org specific goprivate" do
        let(:goprivate) { "github.com/dependabot-fixtures/*" }

        it "raises the correct error" do
          expect { updater.updated_go_sum_content }.
            to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end
    end

    context "with an unreachable dependency with a pseudo version" do
      let(:project_name) { "unreachable_dependency_pseudo_version" }
      let(:dependency_name) { "rsc.io/quote" }
      let(:dependency_version) { "v1.5.2" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/quote"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::GitDependenciesNotReachable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("dependabot-fixtures/go-modules-private")
          expect(error.dependency_urls).
            to eq(["github.com/dependabot-fixtures/go-modules-private"])
        end
      end

      context "with bad credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => ""
          }]
        end

        it "raises the correct error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { updater.updated_go_sum_content }.
            to raise_error(error_class) do |error|
            expect(error.message).to include("dependabot-fixtures/go-modules-private")
          end
        end
      end
    end

    context "with an unreachable sub-dependency" do
      let(:project_name) { "unreachable_sub_dependency" }
      let(:dependency_name) { "rsc.io/quote" }
      let(:dependency_version) { "v1.5.2" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/quote"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::GitDependenciesNotReachable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("dependabot-fixtures/go-modules-private")
          expect(error.dependency_urls).
            to eq(["github.com/dependabot-fixtures/go-modules-private"])
        end
      end
    end

    context "with an unreachable sub-dependency with a pseudo version" do
      let(:project_name) { "unreachable_sub_dependency_pseudo_version" }
      let(:dependency_name) { "rsc.io/quote" }
      let(:dependency_version) { "v1.5.2" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/quote"
          }
        }]
      end
      let(:previous_requirements) { [] }

      it "raises the correct error" do
        error_class = Dependabot::GitDependenciesNotReachable
        expect { updater.updated_go_sum_content }.
          to raise_error(error_class) do |error|
          expect(error.message).to include("dependabot-fixtures/go-modules-private")
          expect(error.dependency_urls).
            to eq(["github.com/dependabot-fixtures/go-modules-private"])
        end
      end
    end
  end

  describe "#updated_go_sum_content" do
    let(:project_name) { "go_sum" }
    subject(:updated_go_mod_content) { updater.updated_go_sum_content }

    context "for a top level dependency" do
      let(:dependency_name) { "rsc.io/quote" }
      let(:dependency_version) { "v1.4.0" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) { previous_requirements }
      let(:previous_requirements) do
        [{
          file: "go.mod",
          requirement: "v1.4.0",
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/quote"
          }
        }]
      end

      context "if no files have changed" do
        let(:go_sum_content) { fixture("projects", project_name, "go.sum") }
        it { is_expected.to eq(go_sum_content) }
      end

      context "when the requirement has changed" do
        let(:dependency_version) { "v1.5.2" }
        let(:requirements) do
          [{
            file: "go.mod",
            requirement: "v1.5.2",
            groups: [],
            source: {
              type: "default",
              source: "rsc.io/quote"
            }
          }]
        end

        it { is_expected.to include(%(rsc.io/quote v1.5.2)) }
        it { is_expected.not_to include(%(rsc.io/quote v1.4.0)) }

        context "but tidying is disabled" do
          let(:tidy) { false }
          it { is_expected.to include(%(rsc.io/quote v1.5.2)) }
          it { is_expected.to include(%(rsc.io/quote v1.4.0)) }
        end
      end
    end

    context "for a monorepo directory" do
      let(:project_name) { "monorepo" }
      let(:directory) { "/cmd" }

      let(:dependency_name) { "rsc.io/qr" }
      let(:dependency_version) { "v0.2.0" }
      let(:dependency_previous_version) { "v0.1.0" }
      let(:requirements) { previous_requirements }
      let(:previous_requirements) do
        [{
          file: "go.mod",
          requirement: "v0.1.0",
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/qr"
          }
        }]
      end

      # updated and tidied
      it { is_expected.to include(%(rsc.io/qr v0.2.0)) }
      it { is_expected.not_to include(%(rsc.io/qr v0.1.0)) }
      # module was not stubbed
      it { is_expected.to include(%(rsc.io/quote v1.4.0)) }
    end

    context "for a monorepo root" do
      let(:project_name) { "monorepo" }

      let(:dependency_name) { "rsc.io/qr" }
      let(:dependency_version) { "v0.2.0" }
      let(:dependency_previous_version) { "v0.1.0" }
      let(:requirements) { previous_requirements }
      let(:previous_requirements) do
        [{
          file: "go.mod",
          requirement: "v0.1.0",
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/qr"
          }
        }]
      end

      # updated and tidied
      it { is_expected.to include(%(rsc.io/qr v0.2.0)) }
      it { is_expected.not_to include(%(rsc.io/qr v0.1.0)) }
      # module was not stubbed
      it { is_expected.to include(%(rsc.io/quote v1.4.0)) }
    end

    context "for an external path replacement" do
      let(:project_name) { "substituted" }

      let(:dependency_name) { "rsc.io/qr" }
      let(:dependency_version) { "v0.2.0" }
      let(:dependency_previous_version) { "v0.1.0" }
      let(:requirements) { previous_requirements }
      let(:previous_requirements) do
        [{
          file: "go.mod",
          requirement: "v0.1.0",
          groups: [],
          source: {
            type: "default",
            source: "rsc.io/qr"
          }
        }]
      end

      # Update is applied, stubbed indirect dependencies are not culled
      it { is_expected.to include(%(rsc.io/qr v0.2.0)) }
      it { is_expected.to include(%(rsc.io/quote v1.4.0)) }
    end
  end

  describe "#handle_subprocess_error" do
    context "for a error caused by running out of disk space" do
      let(:dependency_name) { "rsc.io/quote" }
      let(:dependency_version) { "v1.5.2" }
      let(:dependency_previous_version) { "v1.4.0" }
      let(:requirements) { previous_requirements }
      let(:previous_requirements) { [] }

      it "detects 'input/output error'" do
        stderr = <<~ERROR
          rsc.io/sampler imports
          golang.org/x/text/language: write /tmp/go-codehost-014108053: input/output error
        ERROR

        expect { updater.send(:handle_subprocess_error, stderr) }.to raise_error(Dependabot::OutOfDisk) do |error|
          expect(error.message).to include("write /tmp/go-codehost-014108053: input/output error")
        end
      end

      it "detects 'no space left on device'" do
        stderr = <<~ERROR
          rsc.io/sampler imports
          write /opt/go/gopath/pkg/mod/cache/vcs/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/info/attributes: no space left on device
        ERROR

        expect { updater.send(:handle_subprocess_error, stderr) }.to raise_error(Dependabot::OutOfDisk) do |error|
          expect(error.message).to include("info/attributes: no space left on device")
        end
      end
    end
  end
end
