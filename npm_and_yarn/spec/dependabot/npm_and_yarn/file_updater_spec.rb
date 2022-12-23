# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/version"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end
  let(:dependencies) { [dependency] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com"
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      previous_version: previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "npm_and_yarn"
    )
  end
  let(:dependency_name) { "fetch-factory" }
  let(:version) { "0.0.2" }
  let(:previous_version) { "0.0.1" }
  let(:requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.2",
      groups: ["dependencies"],
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.1",
      groups: ["dependencies"],
      source: source
    }]
  end
  let(:source) { nil }

  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
  let(:repo_contents_path) { nil }

  before do
    FileUtils.mkdir_p(tmp_path)
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }
    let(:updated_package_json) do
      updated_files.find { |f| f.name == "package.json" }
    end
    let(:updated_npm_lock) do
      updated_files.find { |f| f.name == "package-lock.json" }
    end
    let(:updated_yarn_lock) do
      updated_files.find { |f| f.name == "yarn.lock" }
    end

    context "with both npm and yarn lockfiles" do
      let(:files) { project_dependency_files("npm6_and_yarn/simple") }

      it "updates the files" do
        expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.count).to eq(3)
      end

      it "native helpers don't output to stdout" do
        expect { updated_files }.to_not output.to_stdout
      end
    end

    context "without a lockfile" do
      let(:files) { project_dependency_files("npm6/simple_manifest") }
      its(:length) { is_expected.to eq(1) }

      context "when nothing has changed" do
        let(:requirements) { previous_requirements }
        specify { expect { updated_files }.to raise_error(/No files/) }
      end
    end

    context "with a name that needs sanitizing" do
      let(:files) { project_dependency_files("npm6/invalid_name") }

      it "updates the files" do
        expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.count).to eq(2)
      end
    end

    context "with multiple dependencies" do
      let(:files) { project_dependency_files("npm6_and_yarn/multiple_updates") }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.8.1",
            previous_version: "1.0.1",
            requirements: [{
              file: "package.json",
              requirement: "^1.8.1",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^1.0.1",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          ),
          Dependabot::Dependency.new(
            name: "is-number",
            version: "4.0.0",
            previous_version: "2.0.0",
            requirements: [{
              file: "package.json",
              requirement: "^4.0.0",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^2.0.0",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        ]
      end

      it "updates both dependencies" do
        parsed_package = JSON.parse(updated_package_json.content)
        expect(parsed_package["dependencies"]["is-number"]).
          to eq("^4.0.0")
        expect(parsed_package["dependencies"]["etag"]).
          to eq("^1.8.1")

        parsed_package_lock = JSON.parse(updated_npm_lock.content)
        expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
          to eq("4.0.0")
        expect(parsed_package_lock["dependencies"]["etag"]["version"]).
          to eq("1.8.1")

        expect(updated_yarn_lock.content).to include(
          "is-number@^4.0.0:"
        )
        expect(updated_yarn_lock.content).to include(
          "etag@^1.8.1:"
        )
      end

      context "lockfile only update" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "etag",
              version: "1.2.0",
              previous_version: "1.0.1",
              requirements: [{
                file: "package.json",
                requirement: "^1.0.1",
                groups: ["dependencies"],
                source: nil
              }],
              previous_requirements: [{
                file: "package.json",
                requirement: "^1.0.1",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "npm_and_yarn"
            ),
            Dependabot::Dependency.new(
              name: "is-number",
              version: "2.1.0",
              previous_version: "2.0.0",
              requirements: [{
                file: "package.json",
                requirement: "^2.0.0",
                groups: ["dependencies"],
                source: nil
              }],
              previous_requirements: [{
                file: "package.json",
                requirement: "^2.0.0",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "npm_and_yarn"
            )
          ]
        end

        it "updates both dependencies" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package-lock.json yarn.lock))

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("2.1.0")
          expect(parsed_package_lock["dependencies"]["etag"]["version"]).
            to eq("1.2.0")

          expect(updated_yarn_lock.content).to include(
            "is-number-2.1.0.tgz"
          )
          expect(updated_yarn_lock.content).to include(
            "etag-1.2.0.tgz"
          )
        end
      end
    end

    context "with diverged lockfiles" do
      context "when updating a sub-dependency" do
        let(:dependency_name) { "stringstream" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }
        let(:version) { "0.0.6" }
        let(:previous_version) { "0.0.5" }

        context "that is missing from npm" do
          let(:files) { project_dependency_files("npm6_and_yarn/diverged_sub_dependency_missing_npm") }

          it "only updates the yarn lockfile (which includes the sub-dep)" do
            expect(updated_files.map(&:name)).
              to match_array(%w(yarn.lock))
          end
        end

        context "that is missing from yarn" do
          let(:files) { project_dependency_files("npm6_and_yarn/diverged_sub_dependency_missing_yarn") }

          it "only updates the npm lockfile (which includes the sub-dep)" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package-lock.json))
          end
        end
      end
    end

    context "with a shrinkwrap" do
      let(:files) { project_dependency_files("npm4/shrinkwrap") }

      let(:updated_shrinkwrap) do
        updated_files.find { |f| f.name == "npm-shrinkwrap.json" }
      end

      it "updates the shrinkwrap" do
        parsed_shrinkwrap = JSON.parse(updated_shrinkwrap.content)
        expect(parsed_shrinkwrap["dependencies"]["fetch-factory"]["version"]).
          to eq("0.0.2")
      end

      context "and a package-json.lock" do
        let(:files) { project_dependency_files("npm6/shrinkwrap") }

        it "updates the shrinkwrap and the package-lock.json" do
          parsed_shrinkwrap = JSON.parse(updated_shrinkwrap.content)
          expect(parsed_shrinkwrap["dependencies"]["fetch-factory"]["version"]).
            to eq("0.0.2")

          parsed_npm_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_npm_lock["dependencies"]["fetch-factory"]["version"]).
            to eq("0.0.2")
        end
      end
    end

    context "with a git dependency" do
      let(:dependency_name) { "is-number" }
      let(:requirements) do
        [{
          requirement: req,
          file: "package.json",
          groups: ["devDependencies"],
          source: {
            type: "git",
            url: "https://github.com/jonschlinkert/is-number",
            branch: nil,
            ref: ref
          }
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: old_req,
          file: "package.json",
          groups: ["devDependencies"],
          source: {
            type: "git",
            url: "https://github.com/jonschlinkert/is-number",
            branch: nil,
            ref: old_ref
          }
        }]
      end
      let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      let(:version) { "0c6b15a88bc10cd47f67a09506399dfc9ddc075d" }

      context "without a requirement or reference" do
        let(:req) { nil }
        let(:ref) { "master" }
        let(:old_req) { nil }
        let(:old_ref) { "master" }

        let(:files) { project_dependency_files("npm6_and_yarn/github_dependency_no_ref") }

        it "only updates the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package-lock.json yarn.lock))
        end

        it "correctly update the lockfiles" do
          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#" \
                  "98e8ff1da1a89f93d1397a24d7413ed15421c139")

          expect(updated_yarn_lock.content).to include(
            "is-number@jonschlinkert/is-number:"
          )

          expect(updated_yarn_lock.content).to_not include("d5ac0584ee")
          expect(updated_yarn_lock.content).to include(
            "https://codeload.github.com/jonschlinkert/is-number/tar.gz/0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
          )
        end

        context "specified as a full URL" do
          let(:files) { project_dependency_files("npm6_and_yarn/git_dependency") }

          it "only updates the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package-lock.json yarn.lock))

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("git+https://github.com/jonschlinkert/is-number.git#" \
                    "98e8ff1da1a89f93d1397a24d7413ed15421c139")

            expect(updated_yarn_lock.content).to include("is-number")
            expect(updated_yarn_lock.content).to include("0c6b15a88b")
            expect(updated_yarn_lock.content).to_not include("af885e2e890")
          end

          context "when the lockfile has an outdated source" do
            let(:files) { project_dependency_files("npm6_and_yarn/git_dependency_outdated_source") }

            it "updates the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package-lock.json yarn.lock))

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(
                parsed_package_lock["dependencies"]["is-number"]["version"]
              ).to eq("git+https://github.com/jonschlinkert/is-number.git#" \
                      "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

              # NOTE: Yarn installs the latest version of is-number because the
              # lockfile has an invalid resolved url and the package json has no
              # version specified. The invalid source url gets set when
              # replacing the resolved url from the old lockfile in
              # replace-lockfile-declaration.
              expect(updated_yarn_lock.content).to include(
                "is-number@https://github.com/jonschlinkert/is-number.git"
              )
              expect(updated_yarn_lock.content).to_not include("af885e2e890")
            end
          end

          context "when the package lock is empty" do
            let(:files) { project_dependency_files("npm6_and_yarn/git_dependency_empty_npm_lockfile") }

            it "updates the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package-lock.json yarn.lock))

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(
                parsed_package_lock["dependencies"]["is-number"]["version"]
              ).to eq("git+https://github.com/jonschlinkert/is-number.git#" \
                      "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
            end
          end

          context "that previously caused problems" do
            let(:files) { project_dependency_files("npm6_and_yarn/git_dependency_git_url") }

            let(:dependency_name) { "slick-carousel" }
            let(:requirements) { previous_requirements }
            let(:previous_requirements) do
              [{
                requirement: old_req,
                file: "package.json",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/brianfryer/slick",
                  branch: nil,
                  ref: old_ref
                }
              }]
            end
            let(:previous_version) do
              "280b560161b751ba226d50c7db1e0a14a78c2de0"
            end
            let(:version) { "a2aa3fec335c50aceb58f6ef6d22df8e5f3238e1" }

            it "only updates the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package-lock.json yarn.lock))

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              npm_lockfile_version =
                parsed_package_lock["dependencies"]["slick-carousel"]["version"]
              expect(npm_lockfile_version).
                to eq("git://github.com/brianfryer/slick.git#" \
                      "fc6f7d860844ad562df5b94b5918b58bab067751")

              expect(updated_yarn_lock.content).
                to include('slick-carousel@git://github.com/brianfryer/slick":')
              expect(updated_yarn_lock.content).to include("a2aa3fec")
              expect(updated_yarn_lock.content).to_not include("280b56016")
            end
          end

          context "that uses ssh" do
            let(:files) { project_dependency_files("npm6_and_yarn/git_dependency_ssh") }

            it "only updates the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package-lock.json yarn.lock))

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              npm_lockfile_version =
                parsed_package_lock["dependencies"]["is-number"]["version"]
              expect(npm_lockfile_version).
                to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                      "98e8ff1da1a89f93d1397a24d7413ed15421c139")

              expect(updated_yarn_lock.content).to include("is-number")
              expect(updated_yarn_lock.content).to include("0c6b15a88bc")
              expect(updated_yarn_lock.content).to_not include("af885e2e890")
              expect(updated_yarn_lock.content).
                to include("is-number@git+ssh://git@github.com:jonschlinkert")
            end
          end

          context "when updating another dependency" do
            let(:dependency_name) { "chalk" }
            let(:version) { "2.3.2" }
            let(:previous_version) { "0.4.0" }
            let(:requirements) do
              [{
                requirement: "2.3.2",
                file: "package.json",
                groups: ["dependencies"],
                source: nil
              }]
            end
            let(:previous_requirements) do
              [{
                requirement: "0.4.0",
                file: "package.json",
                groups: ["dependencies"],
                source: nil
              }]
            end

            it "doesn't remove the git dependency" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package.json package-lock.json yarn.lock))

              parsed_npm_lock = JSON.parse(updated_npm_lock.content)
              expect(parsed_npm_lock["dependencies"]["is-number"]["version"]).
                to eq("git+https://github.com/jonschlinkert/is-number.git#" \
                      "af885e2e890b9ef0875edd2b117305119ee5bdc5")

              expect(updated_yarn_lock.content).
                to include("is-number.git#af885e2e890b9ef0875edd2b117305119ee")
            end

            context "with an npm6 lockfile" do
              let(:files) { project_dependency_files("npm6/git_dependency") }

              it "doesn't update the 'from' entry" do
                expect(updated_files.map(&:name)).
                  to match_array(%w(package.json package-lock.json))

                parsed_npm_lock = JSON.parse(updated_npm_lock.content)
                expect(parsed_npm_lock["dependencies"]["is-number"]["version"]).
                  to eq("git+https://github.com/jonschlinkert/is-number.git#" \
                        "af885e2e890b9ef0875edd2b117305119ee5bdc5")

                expect(parsed_npm_lock["dependencies"]["is-number"]["from"]).
                  to eq("git+https://github.com/jonschlinkert/is-number.git")
              end
            end
          end

          context "when using a URL token" do
            let(:files) { project_dependency_files("npm6_and_yarn/git_dependency_token") }

            it "only updates the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package-lock.json yarn.lock))

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(
                parsed_package_lock["dependencies"]["is-number"]["version"]
              ).to eq("git+https://dummy-token@github.com/jonschlinkert/" \
                      "is-number.git#0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

              expect(updated_yarn_lock.content).
                to include("is-number@https://dummy-token@github.com/" \
                           "jonschlinkert/is-number.git#master")
              expect(updated_yarn_lock.content).to include("0c6b15a88b")
              expect(updated_yarn_lock.content).to_not include("af885e2e890")
            end
          end
        end

        context "when using git host URL: gitlab" do
          let(:dependency_name) { "babel-preset-php" }
          let(:version) { "5fbc24ccc37bd72052ce71ceae5b4934feb3ac19" }
          let(:previous_version) { "c5a7ba5e0ad98b8db1cb8ce105403dd4b768cced" }
          let(:requirements) do
            [{
              requirement: nil,
              file: "package.json",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://gitlab.com/kornelski/babel-preset-php",
                branch: nil,
                ref: "master"
              }
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: nil,
              file: "package.json",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://gitlab.com/kornelski/babel-preset-php",
                branch: nil,
                ref: "master"
              }
            }]
          end

          let(:files) { project_dependency_files("npm6_and_yarn/githost_dependency") }

          it "correctly update the lockfiles" do
            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(
              parsed_package_lock["dependencies"]["babel-preset-php"]["version"]
            ).to eq("gitlab:kornelski/babel-preset-php#" \
                    "5fbc24ccc37bd72052ce71ceae5b4934feb3ac19")

            expect(updated_yarn_lock.content).
              to include('gitlab:kornelski/babel-preset-php#master":')
            expect(updated_yarn_lock.content).to include(
              "https://gitlab.com/kornelski/babel-preset-php/repository/archive.tar.gz?ref=5fbc24ccc37bd72052ce71ceae5b4934feb3ac19"
            )
          end
        end

        context "when using git host URL: github" do
          let(:files) { project_dependency_files("npm6_and_yarn/githost_dependency") }

          it "correctly update the lockfiles" do
            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("github:jonschlinkert/is-number#" \
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

            expect(updated_yarn_lock.content).
              to include('is-number@github:jonschlinkert/is-number#master":')
            expect(updated_yarn_lock.content).to include(
              "https://codeload.github.com/jonschlinkert/is-number/tar.gz/0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
            )
          end
        end
      end

      context "with a requirement" do
        let(:req) { "^4.0.0" }
        let(:ref) { "master" }
        let(:old_req) { "^2.0.0" }
        let(:old_ref) { "master" }
        let(:previous_version) { "2.0.2" }
        let(:version) { "4.0.0" }

        let(:files) { project_dependency_files("npm6_and_yarn/github_dependency_semver") }

        before do
          git_url = "https://github.com/jonschlinkert/is-number.git"
          git_header = {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
          pack_url = git_url + "/info/refs?service=git-upload-pack"
          stub_request(:get, pack_url).
            to_return(
              status: 200,
              body: fixture("git", "upload_packs", git_pack_fixture_name),
              headers: git_header
            )
        end
        let(:git_pack_fixture_name) { "is-number" }

        it "updates the package.json and the lockfiles" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json yarn.lock))

          parsed_package_json = JSON.parse(updated_package_json.content)
          expect(parsed_package_json["devDependencies"]["is-number"]).
            to eq("jonschlinkert/is-number#semver:^4.0.0")

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#" \
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

          expect(updated_yarn_lock.content).
            to include('"is-number@jonschlinkert/is-number#semver:^4.0.0":')
          expect(updated_yarn_lock.content).
            to include("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end

        context "with a from line in the package-lock" do
          let(:files) { project_dependency_files("npm6/github_dependency_semver_modern") }

          it "updates the package-lock.json from line correctly" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["devDependencies"]["is-number"]).
              to eq("jonschlinkert/is-number#semver:^4.0.0")

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("github:jonschlinkert/is-number#" \
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
            expect(parsed_package_lock["dependencies"]["is-number"]["from"]).
              to eq("github:jonschlinkert/is-number#semver:^4.0.0")
          end
        end

        context "using Yarn semver format" do
          # npm doesn't support Yarn semver format yet
          let(:files) { project_dependency_files("yarn/github_dependency_yarn_semver") }

          it "updates the package.json and the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json yarn.lock))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["devDependencies"]["is-number"]).
              to eq("jonschlinkert/is-number#^4.0.0")

            expect(updated_yarn_lock.content).
              to include("is-number@jonschlinkert/is-number#^4.0.0:")
            expect(updated_yarn_lock.content).
              to include("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end
        end
      end

      context "with a reference" do
        let(:req) { nil }
        let(:ref) { "4.0.0" }
        let(:old_req) { nil }
        let(:old_ref) { "2.0.0" }

        let(:files) { project_dependency_files("npm6_and_yarn/github_dependency") }

        it "updates the package.json and the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json yarn.lock))

          parsed_package_json = JSON.parse(updated_package_json.content)
          expect(parsed_package_json["devDependencies"]["is-number"]).
            to eq("jonschlinkert/is-number#4.0.0")

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#" \
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

          expect(updated_yarn_lock.content).
            to include("is-number@jonschlinkert/is-number#4.0.0:")
          expect(updated_yarn_lock.content).to include(
            "https://codeload.github.com/jonschlinkert/is-number/tar.gz/0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
          )
        end

        context "with a commit reference" do
          let(:dependency_name) { "@reach/router" }
          let(:requirements) do
            [{
              requirement: nil,
              file: "package.json",
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "https://github.com/reach/router",
                branch: nil,
                ref: ref
              }
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: nil,
              file: "package.json",
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "https://github.com/reach/router",
                branch: nil,
                ref: old_ref
              }
            }]
          end
          let(:version) { "1c62524db6e156050552fa4938c2de363d3116df" }
          let(:previous_version) { "2675f56127c921474b275ff91fbdad8ec33cbd74" }
          let(:ref) { "1c62524db6e156050552fa4938c2de363d3116df" }
          let(:old_ref) { "2675f56127c921474b275ff91fbdad8ec33cbd74" }

          let(:files) { project_dependency_files("npm6_and_yarn/github_dependency_commit_ref") }

          it "updates the package.json and the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json yarn.lock))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["dependencies"]["@reach/router"]).
              to eq("reach/router#1c62524db6e156050552fa4938c2de363d3116df")

            parsed_npm_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_npm_lock["dependencies"]["@reach/router"]["version"]).
              to eq("github:reach/router#" \
                    "1c62524db6e156050552fa4938c2de363d3116df")

            expect(updated_yarn_lock.content).to include(
              '"@reach/router@reach/router' \
              '#1c62524db6e156050552fa4938c2de363d3116df":'
            )
            expect(updated_yarn_lock.content).to include(
              "https://codeload.github.com/reach/router/tar.gz/" \
              "1c62524db6e156050552fa4938c2de363d3116df"
            )
          end
        end

        context "when using full git URL" do
          let(:files) { project_dependency_files("npm6_and_yarn/git_dependency_ref") }

          it "updates the package.json and the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json yarn.lock))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["devDependencies"]["is-number"]).
              to eq("https://github.com/jonschlinkert/is-number.git#4.0.0")

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("git+https://github.com/jonschlinkert/is-number.git#" \
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

            expect(updated_yarn_lock.content).
              to include("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end
        end

        context "when using git host URL" do
          let(:files) { project_dependency_files("npm6_and_yarn/githost_dependency_ref") }

          it "updates the package.json and the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json yarn.lock))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["devDependencies"]["is-number"]).
              to eq("github:jonschlinkert/is-number#4.0.0")

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("github:jonschlinkert/is-number#" \
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

            expect(updated_yarn_lock.content).
              to include('is-number@github:jonschlinkert/is-number#4.0.0":')
            expect(updated_yarn_lock.content).to include(
              "https://codeload.github.com/jonschlinkert/is-number/tar.gz/0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
            )
          end
        end

        context "updating to use the registry" do
          let(:dependency_name) { "is-number" }
          let(:version) { "4.0.0" }
          let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
          let(:requirements) do
            [{
              requirement: "^4.0.0",
              file: "package.json",
              groups: ["devDependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: nil,
              file: "package.json",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://github.com/jonschlinkert/is-number",
                branch: nil,
                ref: "d5ac058"
              }
            }]
          end

          let(:files) { project_dependency_files("npm6_and_yarn/git_dependency_commit_ref") }

          it "updates the package.json and the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json yarn.lock))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["devDependencies"]["is-number"]).
              to eq("^4.0.0")

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("4.0.0")

            expect(updated_yarn_lock.content).
              to include("is-number@^4.0.0")
          end
        end

        context "when updating to a dependency with file path sub-deps" do
          let(:dependency_name) do
            "@segment/analytics.js-integration-facebook-pixel"
          end
          let(:ref) { "master" }
          let(:old_ref) { "2.4.1" }
          let(:requirements) do
            [{
              requirement: req,
              file: "package.json",
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "https://github.com/segmentio/analytics.js-integrations",
                branch: nil,
                ref: ref
              }
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: old_req,
              file: "package.json",
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "https://github.com/segmentio/analytics.js-integrations",
                branch: nil,
                ref: old_ref
              }
            }]
          end
          let(:previous_version) { "3b1bb80b302c2e552685dc8a029797ec832ea7c9" }
          let(:version) { "5677730fd3b9de2eb2224b968259893e5fc9adac" }

          context "with a yarn lockfile" do
            let(:files) { project_dependency_files("yarn/git_dependency_local_file") }

            it "raises a helpful error" do
              expect { updated_files }.
                to raise_error(
                  Dependabot::DependencyFileNotResolvable,
                  %r{@segment\/analytics\.js-integration-facebook-pixel}
                )
            end
          end

          context "with a npm lockfile" do
            let(:files) { project_dependency_files("npm6/git_dependency_local_file") }

            it "raises a helpful error" do
              expect { updated_files }.
                to raise_error(
                  Dependabot::DependencyFileNotResolvable,
                  %r{@segment\/analytics\.js-integration-facebook-pixel}
                )
            end
          end
        end
      end
    end

    context "with a path-based dependency" do
      let(:files) { project_dependency_files("npm6_and_yarn/path_dependency") }

      let(:dependency_name) { "lodash" }
      let(:version) { "1.3.1" }
      let(:previous_version) { "1.2.1" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^1.3.1",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^1.2.1",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it "has details of the updated item" do
        parsed_lockfile = JSON.parse(updated_npm_lock.content)

        expect(parsed_lockfile["dependencies"]["lodash"]["version"]).
          to eq("1.3.1")
        expect(updated_yarn_lock.content).to include("lodash@^1.3.1")

        expect(updated_package_json.content).
          to include('"lodash": "^1.3.1"')
        expect(updated_package_json.content).
          to include('"etag": "file:./deps/etag"')
      end
    end

    context "with a lerna.json and both yarn and npm lockfiles" do
      let(:files) { project_dependency_files("npm6_and_yarn/lerna") }

      let(:dependency_name) { "etag" }
      let(:version) { "1.8.1" }
      let(:previous_version) { "1.8.0" }
      let(:requirements) do
        [{
          requirement: "^1.1.0",
          file: "packages/package1/package.json",
          groups: ["devDependencies"],
          source: nil
        }, {
          requirement: "^1.0.0",
          file: "packages/other_package/package.json",
          groups: ["devDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: "^1.1.0",
          file: "packages/package1/package.json",
          groups: ["devDependencies"],
          source: nil
        }, {
          requirement: "^1.0.0",
          file: "packages/other_package/package.json",
          groups: ["devDependencies"],
          source: nil
        }]
      end

      it "updates both lockfiles" do
        expect(updated_files.map(&:name)).
          to match_array(
            [
              "packages/package1/yarn.lock",
              "packages/package1/package-lock.json",
              "packages/other_package/yarn.lock",
              "packages/other_package/package-lock.json"
            ]
          )

        package1_yarn_lock =
          updated_files.find { |f| f.name == "packages/package1/yarn.lock" }
        package1_npm_lock =
          updated_files.
          find { |f| f.name == "packages/package1/package-lock.json" }
        parsed_package1_npm_lock = JSON.parse(package1_npm_lock.content)
        other_package_yarn_lock =
          updated_files.
          find { |f| f.name == "packages/other_package/yarn.lock" }
        other_package_npm_lock =
          updated_files.
          find { |f| f.name == "packages/other_package/package-lock.json" }
        parsed_other_pkg_npm_lock = JSON.parse(other_package_npm_lock.content)

        expect(package1_yarn_lock.content).
          to include("etag@^1.1.0:\n  version \"1.8.1\"")
        expect(other_package_yarn_lock.content).
          to include("etag@^1.0.0:\n  version \"1.8.1\"")

        expect(parsed_package1_npm_lock["dependencies"]["etag"]["version"]).
          to eq("1.8.1")
        expect(parsed_other_pkg_npm_lock["dependencies"]["etag"]["version"]).
          to eq("1.8.1")
      end
    end

    context "when updating a sub dependency with both yarn and npm lockfiles" do
      let(:files) { project_dependency_files("npm6_and_yarn/nested_sub_dependency_update") }

      let(:dependency_name) { "extend" }
      let(:version) { "2.0.2" }
      let(:previous_version) { "2.0.0" }
      let(:requirements) { [] }
      let(:previous_requirements) { nil }

      it "updates only relevant lockfiles" do
        expect(updated_files.map(&:name)).
          to match_array(
            [
              "packages/package1/package-lock.json",
              "packages/package3/yarn.lock"
            ]
          )

        package1_npm_lock =
          updated_files.
          find { |f| f.name == "packages/package1/package-lock.json" }
        package3_yarn_lock =
          updated_files.find { |f| f.name == "packages/package3/yarn.lock" }
        parsed_package1_npm_lock = JSON.parse(package1_npm_lock.content)

        expect(package3_yarn_lock.content).
          to include("extend@~2.0.0:\n  version \"2.0.2\"")

        expect(parsed_package1_npm_lock["dependencies"]["extend"]["version"]).
          to eq("2.0.2")
      end

      context "updates to lowest required version" do
        let(:dependency_name) { "extend" }
        let(:version) { "2.0.1" }
        let(:previous_version) { "2.0.0" }
        let(:requirements) { [] }
        let(:previous_requirements) { nil }

        it "updates only relevant lockfiles" do
          expect(updated_files.map(&:name)).
            to match_array(
              [
                "packages/package1/package-lock.json",
                "packages/package3/yarn.lock"
              ]
            )

          package1_npm_lock =
            updated_files.
            find { |f| f.name == "packages/package1/package-lock.json" }
          package3_yarn_lock =
            updated_files.find { |f| f.name == "packages/package3/yarn.lock" }
          parsed_package1_npm_lock = JSON.parse(package1_npm_lock.content)

          expect(package3_yarn_lock.content).
            to include("extend@~2.0.0:\n  version \"2.0.1\"")

          # TODO: Change this to 2.0.1 once npm supports updating to specific
          # sub dependency versions
          expect(parsed_package1_npm_lock["dependencies"]["extend"]["version"]).
            to eq("2.0.2")
        end
      end

      context "when one lockfile version is out of range" do
        let(:files) { project_dependency_files("npm6_and_yarn/nested_sub_dependency_update_npm_out_of_range") }

        it "updates out of range to latest resolvable version" do
          expect(updated_files.map(&:name)).
            to match_array(
              [
                "packages/package1/package-lock.json",
                "packages/package3/yarn.lock",
                "packages/package4/package-lock.json"
              ]
            )

          package1_npm_lock =
            updated_files.
            find { |f| f.name == "packages/package1/package-lock.json" }
          package3_yarn_lock =
            updated_files.find { |f| f.name == "packages/package3/yarn.lock" }
          parsed_package1_npm_lock = JSON.parse(package1_npm_lock.content)
          package4_npm_lock =
            updated_files.
            find { |f| f.name == "packages/package4/package-lock.json" }
          parsed_package4_npm_lock = JSON.parse(package4_npm_lock.content)

          expect(package3_yarn_lock.content).
            to include("extend@~2.0.0:\n  version \"2.0.2\"")

          expect(parsed_package1_npm_lock["dependencies"]["extend"]["version"]).
            to eq("2.0.2")

          expect(parsed_package4_npm_lock["dependencies"]["extend"]["version"]).
            to eq("1.3.0")
        end
      end
    end

    context "when a wildcard is specified" do
      let(:files) { project_dependency_files("npm6_and_yarn/wildcard") }

      let(:version) { "0.2.0" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "*",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) { requirements }

      it "only updates the lockfiles" do
        expect(updated_files.map(&:name)).
          to match_array(%w(yarn.lock package-lock.json))

        expect(updated_yarn_lock.content).
          to include("fetch-factory@*:\n  version \"0.2.0\"")
        expect(updated_npm_lock.content).
          to include("fetch-factory/-/fetch-factory-0.2.0.tgz")
      end
    end

    ######################
    # npm specific tests #
    ######################
    describe "npm 6 specific" do
      let(:files) { project_dependency_files("npm6/simple") }

      context "when the package lock is empty" do
        let(:files) { project_dependency_files("npm6/no_dependencies") }

        it "updates the files" do
          expect(updated_files.count).to eq(2)
        end
      end

      context "with a requirement that specifies a hash" do
        let(:files) { project_dependency_files("npm6/hash_requirement") }

        it "updates the files" do
          expect(updated_files.count).to eq(2)
        end
      end

      context "with a name that was sanitized" do
        let(:files) { project_dependency_files("npm6/simple") }

        it "updates the files" do
          expect(updated_files.count).to eq(2)
          expect(updated_files.last.content).
            to start_with("{\n\t\"name\": \"{{ name }}\",\n")
        end
      end

      context "when a tarball URL will incorrectly swap to http" do
        let(:files) { project_dependency_files("npm6/tarball_bug") }

        it "keeps the correct protocol" do
          expect(updated_files.count).to eq(2)

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["lodash"]["resolved"]).
            to eq("https://registry.npmjs.org/lodash/-/lodash-3.10.1.tgz")
        end

        context "when updating the problematic dependency" do
          let(:dependency_name) { "chalk" }
          let(:version) { "2.3.2" }
          let(:previous_version) { "0.4.0" }
          let(:requirements) do
            [{
              requirement: "2.3.2",
              file: "package.json",
              groups: ["dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: "0.4.0",
              file: "package.json",
              groups: ["dependencies"],
              source: nil
            }]
          end

          it "keeps the correct protocol" do
            expect(updated_files.count).to eq(2)

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["chalk"]["resolved"]).
              to eq("https://registry.npmjs.org/chalk/-/chalk-2.3.2.tgz")
          end
        end
      end

      context "when the package lock has a numeric version for a git dep" do
        let(:files) { project_dependency_files("npm6/git_dependency_version") }
        let(:dependency_name) { "is-number" }
        let(:requirements) do
          [{
            requirement: nil,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: "master"
            }
          }]
        end
        let(:previous_requirements) { requirements }
        let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
        let(:version) { "0c6b15a88bc10cd47f67a09506399dfc9ddc075d" }

        it "updates the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package-lock.json))

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("git+https://github.com/jonschlinkert/is-number.git#" \
                  "98e8ff1da1a89f93d1397a24d7413ed15421c139")
        end
      end

      context "with a sub-dependency" do
        let(:files) { project_dependency_files("npm6/subdependency_update") }

        let(:dependency_name) { "acorn" }
        let(:version) { "5.7.3" }
        let(:previous_version) { "5.5.3" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        it "updates the version" do
          parsed_npm_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_npm_lock["dependencies"]["acorn"]["version"]).
            to eq("5.7.4")
        end
      end

      context "with a sub-dependency and non-standard indentation" do
        let(:files) { project_dependency_files("npm6/subdependency_update_tab_indentation") }

        let(:dependency_name) { "extend" }
        let(:version) { "1.3.0" }
        let(:previous_version) { "1.2.0" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        it "preserves indentation in the package-lock.json" do
          expect(updated_npm_lock.content).to eq(
            fixture("updated_projects", "npm6", "subdependency_update_tab_indentation", "package-lock.json")
          )
        end
      end

      # NOTE: this will never fail locally on a Mac
      context "with an incompatible os" do
        let(:files) { project_dependency_files("npm6/os_mismatch") }

        let(:dependency_name) { "fsevents" }
        let(:version) { "1.2.4" }
        let(:previous_version) { "1.2.2" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^1.2.4",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^1.2.2",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "updates the version" do
          parsed_npm_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_npm_lock["dependencies"]["fsevents"]["version"]).
            to eq("1.2.4")
        end
      end

      context "when there are git tag dependencies not being updated" do
        let(:files) { project_dependency_files("npm6/git_tag_dependencies") }
        let(:dependency_name) { "etag" }
        let(:requirements) do
          [{
            requirement: "^1.8.1",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: "^1.8.0",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_version) { "1.8.0" }
        let(:version) { "1.8.1" }

        it "doesn't update git dependencies" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))

          parsed_package_json = JSON.parse(updated_package_json.content)
          expect(parsed_package_json["dependencies"]["Select2"]).
            to eq("git+https://github.com/select2/select2.git#3.4.8")

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["Select2"]["from"]).
            to eq("git+https://github.com/select2/select2.git#3.4.8")
          expect(parsed_package_lock["dependencies"]["Select2"]["version"]).
            to eq("git+https://github.com/select2/select2.git#" \
                  "b5f3b2839c48c53f9641d6bb1bccafc5260c7620")
        end
      end

      context "when there are git ref dependencies not being updated" do
        let(:files) { project_dependency_files("npm6/git_ref_dependencies") }
        let(:dependency_name) { "etag" }
        let(:requirements) do
          [{
            requirement: "^1.8.1",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: "^1.8.0",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_version) { "1.8.0" }
        let(:version) { "1.8.1" }

        it "doesn't update git dependencies" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))

          parsed_package_json = JSON.parse(updated_package_json.content)
          expect(parsed_package_json["dependencies"]["Select2"]).
            to eq("git+https://github.com/select2/select2.git#3.x")

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["Select2"]["from"]).
            to eq("git+https://github.com/select2/select2.git#3.x")
          expect(parsed_package_lock["dependencies"]["Select2"]["version"]).
            to eq("git+https://github.com/select2/select2.git#" \
                  "170c88460ac69639b57dfa03cfea0dadbf3c2bad")
        end
      end

      context "with non-standard indentation" do
        it "preserves indentation in the package-lock.json" do
          expect(updated_npm_lock.content).to eq(
            fixture("updated_projects", "npm6", "simple", "package-lock.json")
          )
        end
      end

      context "when 'latest' is specified as version requirement" do
        let(:files) { project_dependency_files("npm6/latest_package_requirement") }
        let(:dependency_name) { "extend" }
        let(:version) { "3.0.2" }
        let(:previous_version) { "2.0.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^3.0.2",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^2.0.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "only updates extend and locks etag" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))
          expect(updated_npm_lock.content).
            to include("extend/-/extend-3.0.2.tgz")
          expect(updated_npm_lock.content).
            to include("etag/-/etag-1.7.0.tgz")
        end
      end

      context "with a .npmrc" do
        context "that has an environment variable auth token" do
          let(:files) { project_dependency_files("npm6/npmrc_env_auth_token") }

          it "updates the files" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json))
          end
        end

        context "that has an _auth line" do
          let(:files) { project_dependency_files("npm6/npmrc_env_global_auth") }

          let(:credentials) do
            [{
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org",
              "token" => "secret_token"
            }]
          end

          it "updates the files" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json))
          end
        end

        context "that precludes updates to the lockfile" do
          let(:files) { project_dependency_files("npm6/npmrc_no_lockfile") }

          specify { expect(updated_files.map(&:name)).to eq(["package.json"]) }
        end
      end
    end

    describe "npm 8 specific" do
      describe "updating top-level dependency with lockfile" do
        let(:files) { project_dependency_files("npm8/package-lock") }

        let(:dependency_name) { "left-pad" }
        let(:version) { "1.3.0" }
        let(:previous_version) { "1.0.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^1.3.0",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^1.0.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "updates the files" do
          expect(updated_files.count).to eq(2)
          parsed_lockfile = JSON.parse(updated_npm_lock.content)
          expect(parsed_lockfile["packages"]["node_modules/left-pad"]["version"]).
            to eq("1.3.0")
          expect(parsed_lockfile["dependencies"]["left-pad"]["version"]).
            to eq("1.3.0")
        end
      end

      describe "updating subdependency with lockfile" do
        let(:files) { project_dependency_files("npm8/subdependency-in-range") }

        let(:dependency_name) { "ms" }
        let(:version) { "2.1.3" }
        let(:previous_version) { "2.1.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^2.1.1",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^2.1.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "updates the files" do
          expect(updated_files.count).to eq(1)
          parsed_lockfile = JSON.parse(updated_npm_lock.content)
          expect(parsed_lockfile["packages"]["node_modules/ms"]["version"]).to eq("2.1.3")
          expect(parsed_lockfile["dependencies"]["ms"]["version"]).to eq("2.1.3")
        end
      end

      context "when the package lock is empty" do
        let(:files) { project_dependency_files("npm8/no_dependencies") }

        it "updates the files" do
          expect(updated_files.count).to eq(2)
        end
      end

      context "with a name that needs sanitizing" do
        let(:files) { project_dependency_files("npm8/invalid_name") }

        it "updates the files" do
          expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
          updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
          expect(updated_files.count).to eq(2)
        end
      end

      context "with multiple dependencies" do
        let(:files) { project_dependency_files("npm8/multiple_updates") }

        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "etag",
              version: "1.8.1",
              previous_version: "1.0.1",
              requirements: [{
                file: "package.json",
                requirement: "^1.8.1",
                groups: ["dependencies"],
                source: nil
              }],
              previous_requirements: [{
                file: "package.json",
                requirement: "^1.0.1",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "npm_and_yarn"
            ),
            Dependabot::Dependency.new(
              name: "is-number",
              version: "4.0.0",
              previous_version: "2.0.0",
              requirements: [{
                file: "package.json",
                requirement: "^4.0.0",
                groups: ["dependencies"],
                source: nil
              }],
              previous_requirements: [{
                file: "package.json",
                requirement: "^2.0.0",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "npm_and_yarn"
            )
          ]
        end

        it "updates both dependencies" do
          parsed_package = JSON.parse(updated_package_json.content)
          expect(parsed_package["dependencies"]["is-number"]).
            to eq("^4.0.0")
          expect(parsed_package["dependencies"]["etag"]).
            to eq("^1.8.1")

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["packages"][""]["dependencies"]["is-number"]).
            to eq("^4.0.0")
          expect(parsed_package_lock["packages"][""]["dependencies"]["etag"]).
            to eq("^1.8.1")
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("4.0.0")
          expect(parsed_package_lock["dependencies"]["etag"]["version"]).
            to eq("1.8.1")
        end

        context "lockfile only update" do
          let(:dependencies) do
            [
              Dependabot::Dependency.new(
                name: "etag",
                version: "1.2.0",
                previous_version: "1.0.1",
                requirements: [{
                  file: "package.json",
                  requirement: "^1.0.1",
                  groups: ["dependencies"],
                  source: nil
                }],
                previous_requirements: [{
                  file: "package.json",
                  requirement: "^1.0.1",
                  groups: ["dependencies"],
                  source: nil
                }],
                package_manager: "npm_and_yarn"
              ),
              Dependabot::Dependency.new(
                name: "is-number",
                version: "2.1.0",
                previous_version: "2.0.0",
                requirements: [{
                  file: "package.json",
                  requirement: "^2.0.0",
                  groups: ["dependencies"],
                  source: nil
                }],
                previous_requirements: [{
                  file: "package.json",
                  requirement: "^2.0.0",
                  groups: ["dependencies"],
                  source: nil
                }],
                package_manager: "npm_and_yarn"
              )
            ]
          end

          it "updates both dependencies" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package-lock.json))

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("2.1.0")
            expect(parsed_package_lock["dependencies"]["etag"]["version"]).
              to eq("1.2.0")
          end
        end
      end

      context "with a requirement that specifies a hash (invalid in npm 8/arborist)" do
        let(:files) { project_dependency_files("npm8/invalid_hash_requirement") }

        it "raises a helpful error" do
          expect { updater.updated_dependency_files }.
            to raise_error(Dependabot::DependencyFileNotParseable)
        end
      end

      context "with a name that was sanitized" do
        let(:files) { project_dependency_files("npm8/simple") }

        it "updates the files" do
          expect(updated_files.count).to eq(2)
          expect(updated_files.last.content).
            to start_with("{\n    \"name\": \"project-name\",\n")
        end
      end

      context "when a tarball URL will incorrectly swap to http" do
        let(:files) { project_dependency_files("npm8/tarball_bug") }

        it "keeps the correct protocol" do
          expect(updated_files.count).to eq(2)

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["lodash"]["resolved"]).
            to eq("https://registry.npmjs.org/lodash/-/lodash-3.10.1.tgz")
        end

        context "when updating the problematic dependency" do
          let(:dependency_name) { "chalk" }
          let(:version) { "2.3.2" }
          let(:previous_version) { "0.4.0" }
          let(:requirements) do
            [{
              requirement: "2.3.2",
              file: "package.json",
              groups: ["dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: "0.4.0",
              file: "package.json",
              groups: ["dependencies"],
              source: nil
            }]
          end

          it "keeps the correct protocol" do
            expect(updated_files.count).to eq(2)

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["chalk"]["resolved"]).
              to eq("https://registry.npmjs.org/chalk/-/chalk-2.3.2.tgz")
          end
        end
      end

      context "when the package lock has a numeric version for a git dep" do
        let(:files) { project_dependency_files("npm8/git_dependency_version") }
        let(:dependency_name) { "is-number" }
        let(:requirements) do
          [{
            requirement: nil,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: "master"
            }
          }]
        end
        let(:previous_requirements) { requirements }
        let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
        let(:version) { "0c6b15a88bc10cd47f67a09506399dfc9ddc075d" }

        it "updates the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package-lock.json))

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end
      end

      context "with a sub-dependency" do
        let(:files) { project_dependency_files("npm8/subdependency_update") }

        let(:dependency_name) { "acorn" }
        let(:version) { "5.7.3" }
        let(:previous_version) { "5.5.3" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        it "updates the version" do
          parsed_npm_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_npm_lock["dependencies"]["acorn"]["version"]).
            to eq("5.7.4")
        end
      end

      context "with a sub-dependency and non-standard indentation" do
        let(:files) { project_dependency_files("npm8/subdependency_update_tab_indentation") }

        let(:dependency_name) { "extend" }
        let(:version) { "1.3.0" }
        let(:previous_version) { "1.2.0" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        it "preserves indentation in the package-lock.json" do
          expect(updated_npm_lock.content).to eq(
            fixture("updated_projects", "npm8", "subdependency_update_tab_indentation", "package-lock.json")
          )
        end
      end

      context "with a path-based dependency" do
        let(:files) { project_dependency_files("npm8/path_dependency") }

        let(:dependency_name) { "lodash" }
        let(:version) { "1.3.1" }
        let(:previous_version) { "1.2.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "has details of the updated item" do
          parsed_lockfile = JSON.parse(updated_npm_lock.content)

          expect(parsed_lockfile["dependencies"]["lodash"]["version"]).
            to eq("1.3.1")

          expect(updated_package_json.content).
            to include('"lodash": "^1.3.1"')
          expect(updated_package_json.content).
            to include('"etag": "file:./deps/etag"')
        end
      end

      # NOTE: this will never fail locally on a Mac
      context "with an incompatible os" do
        let(:files) { project_dependency_files("npm8/os_mismatch") }

        let(:dependency_name) { "fsevents" }
        let(:version) { "1.2.4" }
        let(:previous_version) { "1.2.2" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^1.2.4",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^1.2.2",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "updates the version" do
          parsed_npm_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_npm_lock["dependencies"]["fsevents"]["version"]).
            to eq("1.2.4")
        end
      end

      context "when there are git tag dependencies not being updated" do
        let(:files) { project_dependency_files("npm8/git_tag_dependencies") }
        let(:dependency_name) { "etag" }
        let(:requirements) do
          [{
            requirement: "^1.8.1",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: "^1.8.0",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_version) { "1.8.0" }
        let(:version) { "1.8.1" }

        it "doesn't update git dependencies" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))

          parsed_package_json = JSON.parse(updated_package_json.content)
          expect(parsed_package_json["dependencies"]["Select2"]).
            to eq("git+https://github.com/select2/select2.git#3.4.8")
          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["Select2"]["from"]).
            to eq("Select2@git+https://github.com/select2/select2.git#3.4.8")

          expect(parsed_package_lock["dependencies"]["Select2"]["version"]).
            to eq("git+ssh://git@github.com/select2/select2.git#" \
                  "b5f3b2839c48c53f9641d6bb1bccafc5260c7620")

          # metadata introduced in npm 8, check we restire the package requirement
          expect(parsed_package_lock["packages"][""]["dependencies"]["Select2"]).
            to eq("git+https://github.com/select2/select2.git#3.4.8")
          expect(parsed_package_lock["packages"]["node_modules/Select2"]).
            to eq({
              "version" => "3.4.8",
              "resolved" =>
                      "git+ssh://git@github.com/select2/select2.git#b5f3b2839c48c53f9641d6bb1bccafc5260c7620",
              "integrity" =>
                      "sha512-9sUir8IknGcc2CWbTicYuEFvm0X8AyoMpe6DMtxtNYepRltK4dI7dqUYm5di/zy5Sm8gfC0Vwvn79SWXVNyLdg=="
            })
        end
      end

      context "when there are git ref dependencies not being updated" do
        let(:files) { project_dependency_files("npm8/git_ref_dependencies") }
        let(:dependency_name) { "etag" }
        let(:requirements) do
          [{
            requirement: "^1.8.1",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: "^1.8.0",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_version) { "1.8.0" }
        let(:version) { "1.8.1" }

        it "doesn't update git dependencies" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))

          parsed_package_json = JSON.parse(updated_package_json.content)
          expect(parsed_package_json["dependencies"]["Select2"]).
            to eq("git+https://github.com/select2/select2.git#3.x")

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["packages"][""]["dependencies"]["Select2"]).
            to eq("git+https://github.com/select2/select2.git#3.x")
          expect(parsed_package_lock["dependencies"]["Select2"]["from"]).
            to eq("Select2@git+https://github.com/select2/select2.git#3.x")
          expect(parsed_package_lock["dependencies"]["Select2"]["version"]).
            to eq("git+ssh://git@github.com/select2/select2.git#" \
                  "170c88460ac69639b57dfa03cfea0dadbf3c2bad")
        end
      end

      context "with workspaces" do
        let(:files) { project_dependency_files("npm8/workspaces") }

        let(:dependency_name) { "lodash" }
        let(:version) { "1.3.1" }
        let(:previous_version) { "1.2.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "1.3.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package1/package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "other_package/package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "1.2.0",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package1/package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "other_package/package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "updates the package-lock.json and all three package.jsons" do
          lockfile = updated_files.find { |f| f.name == "package-lock.json" }
          package = updated_files.find { |f| f.name == "package.json" }
          package1 = updated_files.find do |f|
            f.name == "packages/package1/package.json"
          end
          other_package = updated_files.find do |f|
            f.name == "other_package/package.json"
          end

          parsed_lockfile = JSON.parse(lockfile.content)
          expect(parsed_lockfile["dependencies"]["lodash"]["version"]).to eq("1.3.1")
          expect(parsed_lockfile["dependencies"]["other_package"]["requires"]["lodash"]).to eq("1.3.1")
          expect(parsed_lockfile["dependencies"]["package1"]["requires"]["lodash"]).to eq("1.3.1")

          expect(package.content).to include('"lodash": "1.3.1"')
          expect(package1.content).to include('"lodash": "^1.3.1"')
          expect(other_package.content).to include('"lodash": "^1.3.1"')
        end

        context "with a dependency that doesn't appear in all the workspaces" do
          let(:dependency_name) { "chalk" }
          let(:version) { "0.4.0" }
          let(:previous_version) { "0.3.0" }
          let(:requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "0.4.0",
              groups: ["dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "0.3.0",
              groups: ["dependencies"],
              source: nil
            }]
          end

          it "updates the yarn.lock and the correct package_json" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package-lock.json packages/package1/package.json))

            lockfile = updated_files.find { |f| f.name == "package-lock.json" }
            parsed_lockfile = JSON.parse(lockfile.content)
            expect(parsed_lockfile["dependencies"]["chalk"]["version"]).to eq("0.4.0")
          end
        end

        context "with a dependency that's actually up-to-date but has the wrong previous version" do
          let(:files) { project_dependency_files("npm8/workspaces_incorrect_version") }

          let(:dependency_name) { "yargs" }
          let(:version) { "16.2.0" }
          let(:previous_version) { "14.2.3" }
          let(:requirements) do
            [{
              file: "package/package.json",
              requirement: "^16.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "package/package.json",
              requirement: "^16.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          end

          it "doesn't update any files and raises" do
            expect { updated_files }.to raise_error(
              described_class::NoChangeError, "No files were updated!"
            )
          end
        end

        context "with a dependency that appears as a development dependency" do
          let(:dependency_name) { "etag" }
          let(:version) { "1.8.1" }
          let(:previous_version) { "1.8.0" }
          let(:requirements) do
            [{
              file: "other_package/package.json",
              requirement: "^1.8.1",
              groups: ["devDependencies"],
              source: nil
            }, {
              file: "packages/package1/package.json",
              requirement: "^1.8.1",
              groups: ["devDependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "other_package/package.json",
              requirement: "^1.0.0",
              groups: ["devDependencies"],
              source: nil
            }, {
              file: "packages/package1/package.json",
              requirement: "^1.1.0",
              groups: ["devDependencies"],
              source: nil
            }]
          end

          it "updates the right file" do
            updated_npm_lock_content = updated_files.find { |f| f.name == "package-lock.json" }
            expected_updated_npm_lock_content = fixture(
              "updated_projects", "npm8", "workspaces_dev", "package-lock.json"
            )
            parsed_npm_lockfile = JSON.parse(updated_npm_lock_content.content)
            expect(updated_files.map(&:name)).
              to match_array(%w(package-lock.json other_package/package.json packages/package1/package.json))
            expect(parsed_npm_lockfile.dig("dependencies", "etag", "version")).to eq("1.8.1")
            expect(updated_npm_lock.content).to eq(expected_updated_npm_lock_content)
          end

          it "updates the existing development declaration" do
            package1 = updated_files.find do |f|
              f.name == "packages/package1/package.json"
            end
            other_package = updated_files.find do |f|
              f.name == "other_package/package.json"
            end
            parsed_package1 = JSON.parse(package1.content)
            parsed_other_package = JSON.parse(other_package.content)
            expect(parsed_package1.dig("dependencies", "etag")).to be_nil
            expect(parsed_package1.dig("devDependencies", "etag")).to eq("^1.8.1")
            expect(parsed_other_package.dig("dependencies", "etag")).to be_nil
            expect(parsed_other_package.dig("devDependencies", "etag")).to eq("^1.8.1")
          end
        end
      end

      context "when 'latest' is specified as version requirement" do
        let(:files) { project_dependency_files("npm8/latest_package_requirement") }
        let(:dependency_name) { "extend" }
        let(:version) { "3.0.2" }
        let(:previous_version) { "2.0.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^3.0.2",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^2.0.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "only updates extend and locks etag" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))
          expect(updated_npm_lock.content).
            to include("extend/-/extend-3.0.2.tgz")
          expect(updated_npm_lock.content).
            to include("etag/-/etag-1.7.0.tgz")
        end
      end

      context "with a .npmrc" do
        context "that has an environment variable auth token" do
          let(:files) { project_dependency_files("npm8/npmrc_env_auth_token") }

          it "updates the files" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json))
          end
        end

        context "that has an _auth line" do
          let(:files) { project_dependency_files("npm8/npmrc_env_global_auth") }

          let(:credentials) do
            [{
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org",
              "token" => "secret_token"
            }]
          end

          it "updates the files" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json))
          end
        end
      end

      context "with a git dependency" do
        let(:dependency_name) { "is-number" }
        let(:requirements) do
          [{
            requirement: req,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: ref
            }
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: old_req,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: old_ref
            }
          }]
        end
        let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
        let(:version) { "0c6b15a88bc10cd47f67a09506399dfc9ddc075d" }

        context "without a requirement or reference" do
          let(:req) { nil }
          let(:ref) { "master" }
          let(:old_req) { nil }
          let(:old_ref) { "master" }

          let(:files) { project_dependency_files("npm8/github_dependency_no_ref") }

          it "only updates the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package-lock.json))
          end

          it "correctly update the lockfiles" do
            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end

          context "specified as a full URL" do
            let(:files) { project_dependency_files("npm8/git_dependency") }

            it "only updates the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package-lock.json))

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
                to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                      "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
            end

            context "when the lockfile has an outdated source" do
              let(:files) { project_dependency_files("npm8/git_dependency_outdated_source") }

              it "updates the lockfile" do
                expect(updated_files.map(&:name)).
                  to match_array(%w(package-lock.json))

                parsed_package_lock = JSON.parse(updated_npm_lock.content)
                expect(
                  parsed_package_lock["dependencies"]["is-number"]["version"]
                ).to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                        "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
              end
            end

            context "when the package lock is empty" do
              let(:files) { project_dependency_files("npm8/git_dependency_empty_npm_lockfile") }

              it "updates the lockfile" do
                expect(updated_files.map(&:name)).
                  to match_array(%w(package-lock.json))

                parsed_package_lock = JSON.parse(updated_npm_lock.content)
                expect(
                  parsed_package_lock["dependencies"]["is-number"]["version"]
                ).to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                        "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
              end
            end

            context "that previously caused problems" do
              let(:files) { project_dependency_files("npm8/git_dependency_git_url") }

              let(:dependency_name) { "slick-carousel" }
              let(:requirements) { previous_requirements }
              let(:previous_requirements) do
                [{
                  requirement: old_req,
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/brianfryer/slick",
                    branch: nil,
                    ref: old_ref
                  }
                }]
              end
              let(:previous_version) do
                "280b560161b751ba226d50c7db1e0a14a78c2de0"
              end
              let(:version) { "a2aa3fec335c50aceb58f6ef6d22df8e5f3238e1" }

              it "only updates the lockfile" do
                expect(updated_files.map(&:name)).
                  to match_array(%w(package-lock.json))

                parsed_package_lock = JSON.parse(updated_npm_lock.content)
                npm_lockfile_version =
                  parsed_package_lock["dependencies"]["slick-carousel"]["version"]
                expect(npm_lockfile_version).
                  to eq("git+ssh://git@github.com/brianfryer/slick.git#" \
                        "a2aa3fec335c50aceb58f6ef6d22df8e5f3238e1")
              end
            end

            context "that uses ssh" do
              let(:files) { project_dependency_files("npm8/git_dependency_ssh") }

              it "only updates the lockfile" do
                expect(updated_files.map(&:name)).
                  to match_array(%w(package-lock.json))

                parsed_package_lock = JSON.parse(updated_npm_lock.content)
                npm_lockfile_version =
                  parsed_package_lock["dependencies"]["is-number"]["version"]
                expect(npm_lockfile_version).
                  to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                        "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
              end
            end

            context "when updating another dependency" do
              let(:dependency_name) { "chalk" }
              let(:version) { "2.3.2" }
              let(:previous_version) { "0.4.0" }
              let(:requirements) do
                [{
                  requirement: "2.3.2",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              end
              let(:previous_requirements) do
                [{
                  requirement: "0.4.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              end

              it "doesn't remove the git dependency" do
                expect(updated_files.map(&:name)).
                  to match_array(%w(package.json package-lock.json))

                parsed_npm_lock = JSON.parse(updated_npm_lock.content)
                expect(parsed_npm_lock["dependencies"]["is-number"]["version"]).
                  to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                        "af885e2e890b9ef0875edd2b117305119ee5bdc5")
              end
            end

            context "when using a URL token" do
              let(:files) { project_dependency_files("npm8/git_dependency_token") }

              it "only updates the lockfile" do
                expect(updated_files.map(&:name)).
                  to match_array(%w(package-lock.json))

                parsed_package_lock = JSON.parse(updated_npm_lock.content)
                expect(
                  parsed_package_lock["dependencies"]["is-number"]["version"]
                ).to eq("git+https://dummy-token@github.com/jonschlinkert/" \
                        "is-number.git#0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
              end
            end
          end

          context "when using git host URL: gitlab" do
            let(:dependency_name) { "babel-preset-php" }
            let(:version) { "5fbc24ccc37bd72052ce71ceae5b4934feb3ac19" }
            let(:previous_version) { "c5a7ba5e0ad98b8db1cb8ce105403dd4b768cced" }
            let(:requirements) do
              [{
                requirement: nil,
                file: "package.json",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://gitlab.com/kornelski/babel-preset-php",
                  branch: nil,
                  ref: "master"
                }
              }]
            end
            let(:previous_requirements) do
              [{
                requirement: nil,
                file: "package.json",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://gitlab.com/kornelski/babel-preset-php",
                  branch: nil,
                  ref: "master"
                }
              }]
            end

            let(:files) { project_dependency_files("npm8/githost_dependency") }

            it "correctly update the lockfiles" do
              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(
                parsed_package_lock["dependencies"]["babel-preset-php"]["version"]
              ).to eq("git+ssh://git@gitlab.com/kornelski/babel-preset-php.git#" \
                      "5fbc24ccc37bd72052ce71ceae5b4934feb3ac19")
            end
          end

          context "when using git host URL: github" do
            let(:files) { project_dependency_files("npm8/githost_dependency") }

            it "correctly update the lockfiles" do
              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
                to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                      "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
            end
          end
        end

        context "with a requirement" do
          let(:req) { "^4.0.0" }
          let(:ref) { "master" }
          let(:old_req) { "^2.0.0" }
          let(:old_ref) { "master" }
          let(:previous_version) { "2.0.2" }
          let(:version) { "4.0.0" }

          let(:files) { project_dependency_files("npm8/github_dependency_semver") }

          before do
            git_url = "https://github.com/jonschlinkert/is-number.git"
            git_header = {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
            pack_url = git_url + "/info/refs?service=git-upload-pack"
            stub_request(:get, pack_url).
              to_return(
                status: 200,
                body: fixture("git", "upload_packs", git_pack_fixture_name),
                headers: git_header
              )
          end
          let(:git_pack_fixture_name) { "is-number" }

          it "updates the package.json and the lockfiles" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["devDependencies"]["is-number"]).
              to eq("jonschlinkert/is-number#semver:^4.0.0")

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["packages"][""]["devDependencies"]["is-number"]).
              to eq("jonschlinkert/is-number#semver:^4.0.0")
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end

          context "with a from line in the package-lock" do
            let(:files) { project_dependency_files("npm8/github_dependency_semver_modern") }

            it "updates the package-lock.json from line correctly" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package.json package-lock.json))

              parsed_package_json = JSON.parse(updated_package_json.content)
              expect(parsed_package_json["devDependencies"]["is-number"]).
                to eq("jonschlinkert/is-number#semver:^4.0.0")

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(parsed_package_lock["packages"][""]["devDependencies"]["is-number"]).
                to eq("jonschlinkert/is-number#semver:^4.0.0")
              expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
                to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                      "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
              expect(parsed_package_lock["dependencies"]["is-number"]["from"]).
                to eq("is-number@jonschlinkert/is-number#semver:^4.0.0")
            end
          end
        end

        context "with a reference" do
          let(:req) { nil }
          let(:ref) { "4.0.0" }
          let(:old_req) { nil }
          let(:old_ref) { "2.0.0" }

          let(:files) { project_dependency_files("npm8/github_dependency") }

          it "updates the package.json and the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["devDependencies"]["is-number"]).
              to eq("jonschlinkert/is-number#4.0.0")

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["packages"][""]["devDependencies"]["is-number"]).
              to eq("jonschlinkert/is-number#4.0.0")
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end

          context "with a commit reference" do
            let(:dependency_name) { "@reach/router" }
            let(:requirements) do
              [{
                requirement: nil,
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/reach/router",
                  branch: nil,
                  ref: ref
                }
              }]
            end
            let(:previous_requirements) do
              [{
                requirement: nil,
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/reach/router",
                  branch: nil,
                  ref: old_ref
                }
              }]
            end
            let(:version) { "1c62524db6e156050552fa4938c2de363d3116df" }
            let(:previous_version) { "2675f56127c921474b275ff91fbdad8ec33cbd74" }
            let(:ref) { "1c62524db6e156050552fa4938c2de363d3116df" }
            let(:old_ref) { "2675f56127c921474b275ff91fbdad8ec33cbd74" }

            let(:files) { project_dependency_files("npm8/github_dependency_commit_ref") }

            it "updates the package.json and the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package.json package-lock.json))

              parsed_package_json = JSON.parse(updated_package_json.content)
              expect(parsed_package_json["dependencies"]["@reach/router"]).
                to eq("reach/router#1c62524db6e156050552fa4938c2de363d3116df")

              parsed_npm_lock = JSON.parse(updated_npm_lock.content)
              expect(parsed_npm_lock["dependencies"]["@reach/router"]["version"]).
                to eq("git+ssh://git@github.com/reach/router.git#" \
                      "1c62524db6e156050552fa4938c2de363d3116df")
            end
          end

          context "when using full git URL" do
            let(:files) { project_dependency_files("npm8/git_dependency_ref") }

            it "updates the package.json and the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package.json package-lock.json))

              parsed_package_json = JSON.parse(updated_package_json.content)
              expect(parsed_package_json["devDependencies"]["is-number"]).
                to eq("https://github.com/jonschlinkert/is-number.git#4.0.0")

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(parsed_package_lock["packages"][""]["devDependencies"]["is-number"]).
                to eq("https://github.com/jonschlinkert/is-number.git#4.0.0")
              expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
                to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                      "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
            end
          end

          context "when using git host URL" do
            let(:files) { project_dependency_files("npm8/githost_dependency_ref") }

            it "updates the package.json and the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package.json package-lock.json))

              parsed_package_json = JSON.parse(updated_package_json.content)
              expect(parsed_package_json["devDependencies"]["is-number"]).
                to eq("github:jonschlinkert/is-number#4.0.0")

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(parsed_package_lock["packages"][""]["devDependencies"]["is-number"]).
                to eq("github:jonschlinkert/is-number#4.0.0")
              expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
                to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#" \
                      "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
            end
          end

          context "updating to use the registry" do
            let(:dependency_name) { "is-number" }
            let(:version) { "4.0.0" }
            let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
            let(:requirements) do
              [{
                requirement: "^4.0.0",
                file: "package.json",
                groups: ["devDependencies"],
                source: nil
              }]
            end
            let(:previous_requirements) do
              [{
                requirement: nil,
                file: "package.json",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/jonschlinkert/is-number",
                  branch: nil,
                  ref: "d5ac058"
                }
              }]
            end

            let(:files) { project_dependency_files("npm8/git_dependency_commit_ref") }

            it "updates the package.json and the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package.json package-lock.json))

              parsed_package_json = JSON.parse(updated_package_json.content)
              expect(parsed_package_json["devDependencies"]["is-number"]).
                to eq("^4.0.0")

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
                to eq("4.0.0")
            end
          end

          context "when updating to a dependency with file path sub-deps" do
            let(:dependency_name) do
              "@segment/analytics.js-integration-facebook-pixel"
            end
            let(:ref) { "master" }
            let(:old_ref) { "2.4.1" }
            let(:requirements) do
              [{
                requirement: req,
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/segmentio/analytics.js-integrations",
                  branch: nil,
                  ref: ref
                }
              }]
            end
            let(:previous_requirements) do
              [{
                requirement: old_req,
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/segmentio/analytics.js-integrations",
                  branch: nil,
                  ref: old_ref
                }
              }]
            end
            let(:previous_version) { "3b1bb80b302c2e552685dc8a029797ec832ea7c9" }
            let(:version) { "5677730fd3b9de2eb2224b968259893e5fc9adac" }

            # TODO: npm 8 silently ignores this issue and generates a broken lockfile
            context "with a npm lockfile" do
              let(:files) { project_dependency_files("npm8/git_dependency_local_file") }

              pending "raises a helpful error" do
                expect { updated_files }.
                  to raise_error(
                    Dependabot::DependencyFileNotResolvable,
                    %r{@segment\/analytics\.js-integration-facebook-pixel}
                  )
              end
            end
          end
        end
      end

      context "with a lerna.json and npm lockfiles" do
        let(:files) { project_dependency_files("npm8/lerna") }

        let(:dependency_name) { "etag" }
        let(:version) { "1.8.1" }
        let(:previous_version) { "1.8.0" }
        let(:requirements) do
          [{
            requirement: "^1.1.0",
            file: "packages/package1/package.json",
            groups: ["devDependencies"],
            source: nil
          }, {
            requirement: "^1.0.0",
            file: "packages/other_package/package.json",
            groups: ["devDependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: "^1.1.0",
            file: "packages/package1/package.json",
            groups: ["devDependencies"],
            source: nil
          }, {
            requirement: "^1.0.0",
            file: "packages/other_package/package.json",
            groups: ["devDependencies"],
            source: nil
          }]
        end

        it "updates both lockfiles" do
          expect(updated_files.map(&:name)).
            to match_array(
              [
                "packages/package1/package-lock.json",
                "packages/other_package/package-lock.json"
              ]
            )

          package1_npm_lock =
            updated_files.
            find { |f| f.name == "packages/package1/package-lock.json" }
          parsed_package1_npm_lock = JSON.parse(package1_npm_lock.content)
          other_package_npm_lock =
            updated_files.
            find { |f| f.name == "packages/other_package/package-lock.json" }
          parsed_other_pkg_npm_lock = JSON.parse(other_package_npm_lock.content)

          # Sets npm 8 metadata from corresponding package.json requirements
          expect(parsed_package1_npm_lock["packages"][""]["devDependencies"]["etag"]).
            to eq("^1.1.0")
          expect(parsed_other_pkg_npm_lock["packages"][""]["devDependencies"]["etag"]).
            to eq("^1.0.0")

          expect(parsed_package1_npm_lock["dependencies"]["etag"]["version"]).
            to eq("1.8.1")
          expect(parsed_other_pkg_npm_lock["dependencies"]["etag"]["version"]).
            to eq("1.8.1")
        end
      end

      context "when updating a sub dependency with npm lockfiles" do
        let(:files) { project_dependency_files("npm8/nested_sub_dependency_update") }

        let(:dependency_name) { "extend" }
        let(:version) { "2.0.2" }
        let(:previous_version) { "2.0.0" }
        let(:requirements) { [] }
        let(:previous_requirements) { nil }

        it "updates only relevant lockfiles" do
          expect(updated_files.map(&:name)).
            to match_array(
              [
                "packages/package1/package-lock.json"
              ]
            )

          package1_npm_lock =
            updated_files.
            find { |f| f.name == "packages/package1/package-lock.json" }
          parsed_package1_npm_lock = JSON.parse(package1_npm_lock.content)

          expect(parsed_package1_npm_lock["dependencies"]["extend"]["version"]).
            to eq("2.0.2")
        end

        context "updates to lowest required version" do
          let(:dependency_name) { "extend" }
          let(:version) { "2.0.1" }
          let(:previous_version) { "2.0.0" }
          let(:requirements) { [] }
          let(:previous_requirements) { nil }

          it "updates only relevant lockfiles" do
            expect(updated_files.map(&:name)).
              to match_array(
                [
                  "packages/package1/package-lock.json"
                ]
              )

            package1_npm_lock =
              updated_files.
              find { |f| f.name == "packages/package1/package-lock.json" }
            parsed_package1_npm_lock = JSON.parse(package1_npm_lock.content)

            # TODO: Change this to 2.0.1 once npm supports updating to specific
            # sub dependency versions
            expect(parsed_package1_npm_lock["dependencies"]["extend"]["version"]).
              to eq("2.0.2")
          end
        end

        context "when one lockfile version is out of range" do
          let(:files) { project_dependency_files("npm8/nested_sub_dependency_update_npm_out_of_range") }

          it "updates out of range to latest resolvable version" do
            expect(updated_files.map(&:name)).
              to match_array(
                [
                  "packages/package1/package-lock.json",
                  "packages/package4/package-lock.json"
                ]
              )

            package1_npm_lock =
              updated_files.
              find { |f| f.name == "packages/package1/package-lock.json" }
            parsed_package1_npm_lock = JSON.parse(package1_npm_lock.content)
            package4_npm_lock =
              updated_files.
              find { |f| f.name == "packages/package4/package-lock.json" }
            parsed_package4_npm_lock = JSON.parse(package4_npm_lock.content)

            expect(parsed_package1_npm_lock["dependencies"]["extend"]["version"]).
              to eq("2.0.2")

            expect(parsed_package4_npm_lock["dependencies"]["extend"]["version"]).
              to eq("1.3.0")
          end
        end
      end

      context "when a wildcard is specified" do
        let(:files) { project_dependency_files("npm8/wildcard") }

        let(:version) { "0.2.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "*",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) { requirements }

        it "only updates the lockfiles" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package-lock.json))
          parsed_package_lock = JSON.parse(updated_npm_lock.content)

          expect(parsed_package_lock["packages"][""]["dependencies"]["fetch-factory"]).
            to eq("*")
          expect(parsed_package_lock["dependencies"]["fetch-factory"]["version"]).
            to eq("0.2.0")
        end
      end

      context "when 'latest' is specified as version requirement" do
        let(:files) { project_dependency_files("npm6/latest_package_requirement") }
        let(:dependency_name) { "extend" }
        let(:version) { "3.0.2" }
        let(:previous_version) { "2.0.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^3.0.2",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^2.0.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "only updates extend and locks etag" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))
          expect(updated_npm_lock.content).
            to include("extend/-/extend-3.0.2.tgz")
          expect(updated_npm_lock.content).
            to include("etag/-/etag-1.7.0.tgz")
        end
      end

      context "with a .npmrc" do
        context "that has an environment variable auth token" do
          let(:files) { project_dependency_files("npm6/npmrc_env_auth_token") }

          it "updates the files" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json))
          end
        end

        context "that has an _auth line" do
          let(:files) { project_dependency_files("npm6/npmrc_env_global_auth") }

          let(:credentials) do
            [{
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org",
              "token" => "secret_token"
            }]
          end

          it "updates the files" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json))
          end
        end

        context "that precludes updates to the lockfile" do
          let(:files) { project_dependency_files("npm6/npmrc_no_lockfile") }

          specify { expect(updated_files.map(&:name)).to eq(["package.json"]) }
        end
      end
    end

    #############################
    # Yarn Berry specific tests #
    #############################
    describe "Yarn berry specific" do
      describe "the updated yarn_lock" do
        let(:project_name) { "yarn_berry/simple" }
        let(:files) { project_dependency_files(project_name) }
        let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

        it "does not downgrade the lockfile to the yarn 1 format" do
          expect(updated_yarn_lock.content).to include("__metadata")
        end

        it "has details of the updated item" do
          expect(updated_yarn_lock.content).to include("fetch-factory@npm:^0.0.2")
        end

        it "updates the .yarn/cache folder" do
          expect(updated_files.map(&:name)).to match_array(
            [
              ".pnp.cjs",
              ".yarn/cache/fetch-factory-npm-0.0.1-e67abc1f87-ff7fe6fdb8.zip",
              ".yarn/cache/fetch-factory-npm-0.0.2-816f8766e1-200ddd8ae3.zip",
              ".yarn/install-state.gz",
              "package.json",
              "yarn.lock"
            ]
          )
          expect(updated_files.find { |updated_file| updated_file.name == ".pnp.cjs" }.mode).to eq("100755")
        end
      end

      describe "without zero-install the updated yarn_lock" do
        let(:project_name) { "yarn_berry/simple_nopnp" }
        let(:files) { project_dependency_files(project_name) }
        let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

        it "does not downgrade the lockfile to the yarn 1 format" do
          expect(updated_yarn_lock.content).to include("__metadata")
        end

        it "has details of the updated item" do
          expect(updated_yarn_lock.content).to include("fetch-factory@npm:^0.0.2")
        end

        it "does not update zero-install files" do
          expect(updated_files.map(&:name)).to match_array(
            [
              "package.json",
              "yarn.lock",
              ".yarn/install-state.gz"
            ]
          )
        end
      end

      describe "with offline cache the updated yarn_lock" do
        let(:project_name) { "yarn_berry/simple_node_modules" }
        let(:files) { project_dependency_files(project_name) }
        let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

        it "does not downgrade the lockfile to the yarn 1 format" do
          expect(updated_yarn_lock.content).to include("__metadata")
        end

        it "has details of the updated item" do
          expect(updated_yarn_lock.content).to include("fetch-factory@npm:^0.0.2")
        end

        it "updates the cache but not the zero install file" do
          expect(updated_files.map(&:name)).to match_array(
            [
              ".yarn/cache/fetch-factory-npm-0.0.1-e67abc1f87-ff7fe6fdb8.zip",
              ".yarn/cache/fetch-factory-npm-0.0.2-816f8766e1-200ddd8ae3.zip",
              "package.json",
              "yarn.lock"
            ]
          )
        end
      end

      context "when updating only the lockfile" do
        let(:files) { project_dependency_files("yarn_berry/lockfile_only_change") }

        let(:dependency_name) { "babel-jest" }
        let(:version) { "22.4.4" }
        let(:previous_version) { "22.0.4" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^22.0.4",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) { requirements }

        it "has details of the updated item, but doesn't update everything" do
          parsed_lockfile = YAML.safe_load(updated_yarn_lock.content)
          # Updates the desired dependency
          expect(parsed_lockfile["babel-jest@npm:^22.0.4"]["version"]).to eq("22.4.4")

          # Doesn't update unrelated dependencies
          expect(parsed_lockfile["eslint@npm:^4.14.0"]["version"]).to eq("4.14.0")
        end
      end

      context "with workspaces" do
        let(:files) { project_dependency_files("yarn_berry/workspaces") }

        let(:dependency_name) { "lodash" }
        let(:version) { "1.3.1" }
        let(:previous_version) { "1.2.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "1.3.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package1/package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "other_package/package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "1.2.0",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package1/package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "other_package/package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "updates the yarn.lock and all three package.jsons" do
          lockfile = updated_files.find { |f| f.name == "yarn.lock" }
          package = updated_files.find { |f| f.name == "package.json" }
          package1 = updated_files.find do |f|
            f.name == "packages/package1/package.json"
          end
          other_package = updated_files.find do |f|
            f.name == "other_package/package.json"
          end

          expect(lockfile.content).to include(%("lodash@npm:1.3.1, lodash@npm:^1.3.1":))
          expect(lockfile.content).to_not include("lodash@npm:^1.2.1:")
          expect(lockfile.content).to_not include("workspace-aggregator")

          expect(package.content).to include('"lodash": "1.3.1"')
          expect(package.content).to include("\"./packages/*\",\n")
          expect(package1.content).to include('"lodash": "^1.3.1"')
          expect(other_package.content).to include('"lodash": "^1.3.1"')
        end

        context "with a dependency that doesn't appear in all the workspaces" do
          let(:dependency_name) { "chalk" }
          let(:version) { "0.4.0" }
          let(:previous_version) { "0.3.0" }
          let(:requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "0.4.0",
              groups: ["dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "0.3.0",
              groups: ["dependencies"],
              source: nil
            }]
          end

          it "updates the yarn.lock and the correct package_json" do
            expect(updated_files.map(&:name)).
              to match_array(%w(yarn.lock packages/package1/package.json))

            lockfile = updated_files.find { |f| f.name == "yarn.lock" }
            expect(lockfile.content).to include("chalk@npm:0.4.0")
            expect(lockfile.content).to_not include("workspace-aggregator")
          end

          it "does not add the dependency to the top-level workspace" do
            lockfile = updated_files.find { |f| f.name == "yarn.lock" }
            parsed_lockfile = YAML.safe_load(lockfile.content)
            expect(parsed_lockfile.dig("bump-test@workspace:.", "dependencies").keys).not_to include("chalk")
          end
        end
      end

      context "with a sub-dependency" do
        let(:files) { project_dependency_files("yarn_berry/no_lockfile_change") }

        let(:dependency_name) { "acorn" }
        let(:version) { "5.7.3" }
        let(:previous_version) { "5.1.1" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        it "updates the version" do
          expect(updated_yarn_lock.content).
            to include(%("acorn@npm:^5.0.0, acorn@npm:^5.1.2":\n  version: 5.7.3))
        end
      end
    end

    #######################
    # Yarn specific tests #
    #######################
    describe "Yarn specific" do
      describe "the updated yarn_lock" do
        let(:files) { project_dependency_files("yarn/simple") }

        it "has details of the updated item" do
          expect(updated_yarn_lock.content).to include("fetch-factory@^0.0.2")
        end

        context "when a dist-tag is specified" do
          let(:files) { project_dependency_files("yarn/dist_tag") }

          let(:dependency_name) { "npm" }
          let(:version) { "5.9.0-next.0" }
          let(:previous_version) { "5.8.0" }
          let(:requirements) do
            [{
              file: "package.json",
              requirement: "next",
              groups: ["dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) { requirements }

          it "has details of the updated item" do
            expect(updated_yarn_lock.content).to include("npm@next:")

            version =
              updated_yarn_lock.content.
              match(/npm\@next:\n  version "(?<version>.*?)"/).
              named_captures["version"]

            expect(Dependabot::NpmAndYarn::Version.new(version)).
              to be >= Dependabot::NpmAndYarn::Version.new("5.9.0-next.0")
          end
        end

        context "when the version is missing from the lockfile" do
          let(:files) { project_dependency_files("yarn/missing_requirement") }

          it "has details of the updated item (doesn't error)" do
            expect(updated_yarn_lock.content).to include("fetch-factory@^0.0.2")
          end
        end

        context "when updating only the lockfile" do
          let(:files) { project_dependency_files("yarn/lockfile_only_change") }

          let(:dependency_name) { "babel-jest" }
          let(:version) { "22.4.3" }
          let(:previous_version) { "22.0.4" }
          let(:requirements) do
            [{
              file: "package.json",
              requirement: "^22.0.4",
              groups: ["dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) { requirements }

          it "has details of the updated item, but doesn't update everything" do
            # Updates the desired dependency
            expect(updated_yarn_lock.content).
              to include("babel-jest@^22.0.4:\n  version \"22.4.3\"")

            # Doesn't update unrelated dependencies
            expect(updated_yarn_lock.content).
              to include("eslint@^4.14.0:\n  version \"4.14.0\"")
          end
        end
      end

      context "when a yarnrc would prevent updates to the yarn.lock" do
        let(:files) { project_dependency_files("yarn/frozen_lockfile") }

        it "updates the lockfile" do
          expect(updated_files.map(&:name)).to include("yarn.lock")
        end
      end

      context "when the lockfile needs to be cleaned up (Yarn bug)" do
        let(:files) { project_dependency_files("yarn/no_lockfile_change") }

        let(:dependency_name) { "babel-register" }
        let(:version) { "6.26.0" }
        let(:previous_version) { "6.24.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^6.26.0",
            groups: ["devDependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^6.24.1",
            groups: ["devDependencies"],
            source: nil
          }]
        end

        it "removes details of the old version" do
          expect(updated_yarn_lock.content).
            to_not include("babel-register@^6.24.1:")
          expect(updated_yarn_lock.content).
            to_not include("integrity sha512-")
        end
      end

      context "when there were http:// entries in the lockfile" do
        let(:files) { project_dependency_files("yarn/http_lockfile") }

        it "updates the files" do
          expect(updated_yarn_lock.content).
            to include("fetch-factory@^0.0.2:\n  version \"0.0.2\"")
          expect(updated_yarn_lock.content).
            to include("https://registry.yarnpkg.com/etag/-/etag-1.7.0.tgz")
        end
      end

      context "when the npm registry was explicitly specified" do
        let(:files) { project_dependency_files("yarn/npm_global_registry") }
        let(:credentials) do
          [{
            "type" => "npm_registry",
            "registry" => "https://registry.npmjs.org",
            "token" => "secret_token"
          }]
        end
        let(:source) do
          { type: "registry", url: "https://registry.npmjs.org" }
        end

        it "keeps the preference for the npm registry" do
          expect(updated_yarn_lock.content).
            to include("fetch-factory@^0.0.2:\n  version \"0.0.2\"")
          expect(updated_yarn_lock.content).to include(
            "https://registry.npmjs.org/fetch-factory/-/fetch-factory-0.0.2"
          )
        end
      end

      context "when there's a duplicate indirect dependency" do
        let(:files) { project_dependency_files("yarn/duplicate_indirect_dependency") }

        let(:dependency_name) { "graphql-cli" }
        let(:version) { "3.0.4" }
        let(:previous_version) { "3.0.3" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "3.0.4",
            groups: ["devDependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "3.0.3",
            groups: ["devDependencies"],
            source: nil
          }]
        end

        it "removes old version" do
          expect(updated_yarn_lock.content).to include("rimraf@2.6.3")

          # Cleaned up in fix-duplicates.js
          expect(updated_yarn_lock.content).to_not include("rimraf-2.6.2")
        end
      end

      context "with a sub-dependency" do
        let(:files) { project_dependency_files("yarn/no_lockfile_change") }

        let(:dependency_name) { "acorn" }
        let(:version) { "5.7.3" }
        let(:previous_version) { "5.1.1" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        it "updates the version" do
          expect(updated_yarn_lock.content).
            to include(%(acorn@^5.0.0, acorn@^5.1.2:\n  version "5.7.3"))
        end
      end

      context "with resolutions" do
        let(:files) { project_dependency_files("yarn/resolution_specified") }

        let(:dependency_name) { "lodash" }
        let(:version) { "3.10.1" }
        let(:previous_version) { "3.10.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^3.0",
            groups: ["devDependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) { requirements }

        it "updates the resolution, as well as the declaration" do
          expect(updated_package_json.content).
            to include('"lodash": "3.10.1"')

          expect(updated_yarn_lock.content).
            to include("lodash@2.4.1, lodash@3.10.1, lodash@^3.0, " \
                       "lodash@^3.10.1:\n  version \"3.10.1\"")
        end
      end

      context "with workspaces" do
        let(:files) { project_dependency_files("yarn/workspaces") }

        let(:dependency_name) { "lodash" }
        let(:version) { "1.3.1" }
        let(:previous_version) { "1.2.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "1.3.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package1/package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "other_package/package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "1.2.0",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package1/package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "other_package/package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "updates the yarn.lock and all three package.jsons" do
          lockfile = updated_files.find { |f| f.name == "yarn.lock" }
          package = updated_files.find { |f| f.name == "package.json" }
          package1 = updated_files.find do |f|
            f.name == "packages/package1/package.json"
          end
          other_package = updated_files.find do |f|
            f.name == "other_package/package.json"
          end

          expect(lockfile.content).to include("lodash@1.3.1, lodash@^1.3.1:")
          expect(lockfile.content).to_not include("lodash@^1.2.1:")
          expect(lockfile.content).to_not include("workspace-aggregator")

          expect(package.content).to include('"lodash": "1.3.1"')
          expect(package.content).to include("\"./packages/*\",\n")
          expect(package1.content).to include('"lodash": "^1.3.1"')
          expect(other_package.content).to include('"lodash": "^1.3.1"')
        end

        context "with a dependency that doesn't appear in all the workspaces" do
          let(:dependency_name) { "chalk" }
          let(:version) { "0.4.0" }
          let(:previous_version) { "0.3.0" }
          let(:requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "0.4.0",
              groups: ["dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "0.3.0",
              groups: ["dependencies"],
              source: nil
            }]
          end

          it "updates the yarn.lock and the correct package_json" do
            expect(updated_files.map(&:name)).
              to match_array(%w(yarn.lock packages/package1/package.json))

            lockfile = updated_files.find { |f| f.name == "yarn.lock" }
            expect(lockfile.content).to include("chalk@0.4.0:")
            expect(lockfile.content).to_not include("workspace-aggregator")
          end
        end

        context "when the package.json doesn't specify that it's private" do
          let(:files) { project_dependency_files("yarn/workspaces_bad") }

          it "raises a helpful error" do
            expect { updater.updated_dependency_files }.
              to raise_error(Dependabot::DependencyFileNotEvaluatable)
          end
        end

        context "with a dependency that appears as a development dependency" do
          let(:dependency_name) { "etag" }
          let(:version) { "1.8.1" }
          let(:previous_version) { "1.8.0" }
          let(:requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "^1.8.1",
              groups: ["devDependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "^1.1.0",
              groups: ["devDependencies"],
              source: nil
            }]
          end

          it "updates the right file" do
            root_lockfile = updated_files.find { |f| f.name == "yarn.lock" }
            expect(updated_files.map(&:name)).
              to match_array(%w(yarn.lock packages/package1/package.json))
            expect(root_lockfile.content).to include("etag@^1.8.1:")
          end

          it "updates the existing development declaration" do
            file = updated_files.find do |f|
              f.name == "packages/package1/package.json"
            end
            parsed_file = JSON.parse(file.content)
            expect(parsed_file.dig("dependencies", "etag")).to be_nil
            expect(parsed_file.dig("devDependencies", "etag")).to eq("^1.8.1")
          end
        end
      end

      context "when package resolutions create invalid lockfile requirements" do
        let(:files) { project_dependency_files("yarn/resolutions_invalid") }

        let(:dependency_name) { "graphql" }
        let(:requirements) do
          [{
            requirement: nil,
            file: "package.json",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/graphql/graphql-js",
              branch: nil,
              ref: "npm"
            }
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: nil,
            file: "package.json",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/graphql/graphql-js",
              branch: nil,
              ref: "npm"
            }
          }]
        end
        let(:previous_version) { "c67add85a6f47d58aa510897d520278fffd23611" }
        let(:version) { "241058716a075a04fd6a84cd76151cd94c3ffd3a" }

        it "updates the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(yarn.lock))

          # All graphql requirements should be flattened to the git version
          # This "invalid" requirement is created by the "resolutions" glob
          # targetting all graphql dependency names and resolving it to the git
          # version
          expect(updated_yarn_lock.content).to include(
            "graphql@0.11.7, " \
            '"graphql@git://github.com/graphql/graphql-js.git#npm":'
          )
          expect(updated_yarn_lock.content).
            to include("241058716a075a04fd6a84cd76151cd94c3ffd3a")
        end
      end

      context "when package has a invalid platform requirement" do
        let(:files) { project_dependency_files("yarn/invalid_platform") }

        let(:dependency_name) { "node-adodb" }
        let(:requirements) do
          [{
            requirement: "^5.0.2",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: "^5.0.0",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_version) { "5.0.2" }
        let(:version) { "5.0.0" }

        it "updates the manifest and lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json yarn.lock))

          expect(updated_yarn_lock.content).to include(
            "node-adodb@^5.0.2"
          )
        end
      end

      context "when 'latest' is specified as version requirement" do
        let(:files) { project_dependency_files("yarn/latest_package_requirement") }

        let(:dependency_name) { "extend" }
        let(:version) { "3.0.2" }
        let(:previous_version) { "2.0.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^3.0.2",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^2.0.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "only updates extend and locks etag" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json yarn.lock))
          expect(updated_yarn_lock.content).
            to include("extend@^3.0.2:\n  version \"3.0.2\"")
          expect(updated_yarn_lock.content).
            to include("etag@latest:\n  version \"1.7.0\"")
        end
      end

      context "when updating a sub dependency with multiple requirements" do
        let(:files) { project_dependency_files("yarn/multiple_sub_dependencies") }

        let(:dependency_name) { "js-yaml" }
        let(:version) { "3.12.0" }
        let(:previous_version) { "3.9.0" }
        let(:requirements) { [] }
        let(:previous_requirements) { nil }

        it "de-duplicates all entries to the same version" do
          expect(updated_files.map(&:name)).to match_array(["yarn.lock"])
          expect(updated_yarn_lock.content).
            to include("js-yaml@^3.10.0, js-yaml@^3.4.6, js-yaml@^3.9.0:\n" \
                       '  version "3.12.0"')
        end
      end

      context "when the exact version we're updating from is still requested" do
        let(:files) { project_dependency_files("yarn/typedoc-plugin-ui-router") }

        let(:dependency_name) { "typescript" }
        let(:version) { "2.9.1" }
        let(:previous_version) { "2.1.4" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^2.1.1",
            groups: ["devDependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) { requirements }

        it "updates the lockfile" do
          expect(updated_files.map(&:name)).to eq(%w(yarn.lock))

          expect(updated_yarn_lock.content).
            to include("typescript@2.1.4:\n  version \"2.1.4\"")
          expect(updated_yarn_lock.content).
            to include("typescript@^2.1.1:\n  version \"2.9.1\"")
        end
      end
    end
  end
end
