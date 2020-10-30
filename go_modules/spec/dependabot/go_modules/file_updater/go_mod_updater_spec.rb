# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/file_updater/go_mod_updater"

RSpec.describe Dependabot::GoModules::FileUpdater::GoModUpdater do
  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }],
      repo_contents_path: repo_contents_path,
      directory: "/",
      options: { tidy: tidy, vendor: false }
    )
  end

  let(:project_name) { "simple" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:go_mod_content) { fixture("projects", project_name, "go.mod") }
  let(:tidy) { true }

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

        context "for a go 1.11 go.mod" do
          let(:project_name) { "go_1.11" }

          it { is_expected.to_not include("go 1.") }
        end

        context "for a go 1.12 go.mod" do
          let(:project_name) { "simple" }

          it { is_expected.to include("go 1.12") }
        end

        context "for a go 1.13 go.mod" do
          let(:project_name) { "go_1.13" }

          it { is_expected.to include("go 1.13") }
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
              error_class = Dependabot::DependencyFileNotResolvable
              expect { updater.updated_go_sum_content }.
                to raise_error(error_class) do |error|
                  expect(error.message).to include("hmarr/404")
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
  end
end
