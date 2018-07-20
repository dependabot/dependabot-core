# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/ruby/bundler"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Ruby::Bundler do
  include_context "stub rubygems compact index"

  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end
  let(:dependencies) { [dependency] }
  let(:dependency_files) { [gemfile, lockfile] }
  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: gemfile_body,
      directory: directory
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: lockfile_body,
      directory: directory
    )
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", gemfile_fixture_name) }
  let(:lockfile_body) { fixture("ruby", "lockfiles", lockfile_fixture_name) }
  let(:gemfile_fixture_name) { "Gemfile" }
  let(:lockfile_fixture_name) { "Gemfile.lock" }
  let(:directory) { "/" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: dependency_previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.5.0" }
  let(:dependency_previous_version) { "1.4.0" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(2) }

    describe "the updated gemfile" do
      subject(:updated_gemfile) do
        updated_files.find { |f| f.name == "Gemfile" }
      end

      context "when no change is required" do
        let(:gemfile_fixture_name) { "version_not_specified" }
        let(:requirements) do
          [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
        end
        let(:previous_requirements) do
          [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
        end
        it { is_expected.to be_nil }
      end

      context "when the full version is specified" do
        let(:gemfile_fixture_name) { "version_specified" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.5.0",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }]
        end
        its(:content) { is_expected.to include("\"business\", \"~> 1.5.0\"") }
        its(:content) { is_expected.to include("\"statesman\", \"~> 1.2.0\"") }
      end

      context "when updating a sub-dependency" do
        let(:gemfile_fixture_name) { "subdependency" }
        let(:lockfile_fixture_name) { "subdependency.lock" }
        let(:dependency_name) { "i18n" }
        let(:dependency_version) { "1.6.0.beta" }
        let(:dependency_previous_version) { "0.7.0.beta1" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        it { is_expected.to be_nil }
      end

      context "when a pre-release is specified" do
        let(:gemfile_fixture_name) { "prerelease_specified" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.5.0",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.4.0.rc1",
            groups: [],
            source: nil
          }]
        end
        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
      end

      context "when the minor version is specified" do
        let(:gemfile_fixture_name) { "minor_version_specified" }
        let(:requirements) do
          [{ file: "Gemfile", requirement: "~> 1.5", groups: [], source: nil }]
        end
        let(:previous_requirements) do
          [{ file: "Gemfile", requirement: "~> 1.4", groups: [], source: nil }]
        end
        its(:content) { is_expected.to include "\"business\", \"~> 1.5\"" }
        its(:content) { is_expected.to include "\"statesman\", \"~> 1.2\"" }
      end

      context "with a gem whose name includes a number" do
        let(:gemfile_fixture_name) { "gem_with_number" }
        let(:lockfile_fixture_name) { "gem_with_number.lock" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "i18n",
            version: "0.5.0",
            requirements: [{
              file: "Gemfile",
              requirement: "~> 0.5.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: "~> 0.4.0",
              groups: [],
              source: nil
            }],
            package_manager: "bundler"
          )
        end
        its(:content) { is_expected.to include "\"i18n\", \"~> 0.5.0\"" }
      end

      context "when there is a comment" do
        let(:gemfile_fixture_name) { "comments" }
        its(:content) do
          is_expected.to include "\"business\", \"~> 1.5.0\"   # Business time"
        end
      end

      context "when the previous version used string interpolation" do
        let(:gemfile_fixture_name) { "interpolated_version" }
        its(:content) { is_expected.to include "\"business\", \"~> #" }
      end

      context "when the previous version used a function" do
        let(:gemfile_fixture_name) { "function_version" }
        its(:content) { is_expected.to include "\"business\", version" }
      end

      context "with multiple dependencies" do
        let(:gemfile_fixture_name) { "version_conflict" }
        let(:lockfile_fixture_name) { "version_conflict.lock" }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "rspec-mocks",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: requirements,
              previous_requirements: previous_requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "rspec-support",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: requirements,
              previous_requirements: previous_requirements,
              package_manager: "bundler"
            )
          ]
        end
        let(:requirements) do
          [{ file: "Gemfile", requirement: "3.6.0", groups: [], source: nil }]
        end
        let(:previous_requirements) do
          [{ file: "Gemfile", requirement: "3.5.0", groups: [], source: nil }]
        end

        it "updates both dependencies" do
          expect(updated_gemfile.content).
            to include("\"rspec-mocks\", \"3.6.0\"")
          expect(updated_gemfile.content).
            to include("\"rspec-support\", \"3.6.0\"")
        end
      end

      context "with a gem that has a git source" do
        let(:gemfile_fixture_name) { "git_source_with_version" }
        let(:lockfile_fixture_name) { "git_source_with_version.lock" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "c170ea081c121c00ed6fe8764e3557e731454b9d",
            previous_version: "c5bf1bd47935504072ac0eba1006cf4d67af6a7a",
            requirements: requirements,
            previous_requirements: previous_requirements,
            package_manager: "bundler"
          )
        end
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.14.0",
            groups: [],
            source: {
              type: "git",
              url: "http://github.com/gocardless/business"
            }
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.0.0",
            groups: [],
            source: {
              type: "git",
              url: "http://github.com/gocardless/business"
            }
          }]
        end
        its(:content) do
          is_expected.to include "\"business\", \"~> 1.14.0\", git"
        end

        context "that should have its tag updated" do
          let(:gemfile_body) do
            %(gem "business", "~> 1.0.0", ) +
              %(git: "https://github.com/gocardless/business", tag: "v1.0.0")
          end
          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: "~> 1.8.0",
              groups: [],
              source: {
                type: "git",
                url: "http://github.com/gocardless/business",
                ref: "v1.8.0"
              }
            }]
          end

          let(:expected_string) do
            %(gem "business", "~> 1.8.0", ) +
              %(git: "https://github.com/gocardless/business", tag: "v1.8.0")
          end

          its(:content) { is_expected.to eq(expected_string) }
        end

        context "that should be removed" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.8.0",
              previous_version: "c5bf1bd47935504072ac0eba1006cf4d67af6a7a",
              requirements: requirements,
              previous_requirements: previous_requirements,
              package_manager: "bundler"
            )
          end
          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: "~> 1.8.0",
              groups: [],
              source: nil
            }]
          end

          its(:content) do
            is_expected.to include "\"business\", \"~> 1.8.0\"\n"
          end

          context "with a tag (i.e., multiple git-related arguments)" do
            let(:gemfile_body) do
              %(gem "business", git: "git_url", tag: "old_tag")
            end
            its(:content) { is_expected.to eq(%(gem "business")) }
          end

          context "with non-git args at the start" do
            let(:gemfile_body) do
              %(gem "business", "1.0.0", require: false, git: "git_url")
            end
            its(:content) do
              is_expected.to eq(%(gem "business", "~> 1.8.0", require: false))
            end
          end

          context "with non-git args at the end" do
            let(:gemfile_body) do
              %(gem "business", "1.0.0", git: "git_url", require: false)
            end
            its(:content) do
              is_expected.to eq(%(gem "business", "~> 1.8.0", require: false))
            end
          end

          context "with non-git args on a subsequent line" do
            let(:gemfile_body) do
              %(gem("business", "1.0.0", git: "git_url",\nrequire: false))
            end
            its(:content) do
              is_expected.to eq(%(gem("business", "~> 1.8.0", require: false)))
            end
          end

          context "with git args on a subsequent line" do
            let(:gemfile_body) do
              %(gem "business", '1.0.0', require: false,\ngit: "git_url")
            end
            its(:content) do
              is_expected.to eq(%(gem "business", '~> 1.8.0', require: false))
            end
          end

          context "with a custom arg" do
            let(:gemfile_body) { %(gem "business", "1.0.0", github: "git_url") }
            its(:content) { is_expected.to eq(%(gem "business", "~> 1.8.0")) }
          end

          context "with a comment" do
            let(:gemfile_body) { %(gem "business", git: "git_url" # My gem) }
            its(:content) { is_expected.to eq(%(gem "business" # My gem)) }
          end
        end
      end

      context "when the new (and old) requirement is a range" do
        let(:gemfile_fixture_name) { "version_between_bounds" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "> 1.0.0, < 1.6.0",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gemfile",
            requirement: "> 1.0.0, < 1.5.0",
            groups: [],
            source: nil
          }]
        end
        its(:content) do
          is_expected.to include "\"business\", \"> 1.0.0\", \"< 1.6.0\""
        end
      end
    end

    describe "a child gemfile" do
      let(:dependency_files) { [gemfile, lockfile, child_gemfile] }
      let(:child_gemfile) do
        Dependabot::DependencyFile.new(
          content: child_gemfile_body,
          name: "backend/Gemfile"
        )
      end
      let(:child_gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
      subject(:updated_gemfile) do
        updated_files.find { |f| f.name == "backend/Gemfile" }
      end

      context "when no change is required" do
        let(:gemfile_fixture_name) { "version_not_specified" }
        let(:child_gemfile_body) do
          fixture("ruby", "gemfiles", "version_not_specified")
        end
        let(:requirements) do
          [
            {
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: nil
            },
            {
              file: "backend/Gemfile",
              requirement: ">= 0",
              groups: [],
              source: nil
            }
          ]
        end
        let(:previous_requirements) do
          [
            {
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: nil
            },
            {
              file: "backend/Gemfile",
              requirement: ">= 0",
              groups: [],
              source: nil
            }
          ]
        end
        it { is_expected.to be_nil }
      end

      context "when a change is required" do
        let(:child_gemfile_body) do
          fixture("ruby", "gemfiles", "version_specified")
        end
        let(:requirements) do
          [
            {
              file: "Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            },
            {
              file: "backend/Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            }
          ]
        end
        let(:previous_requirements) do
          [
            {
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            },
            {
              file: "backend/Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ]
        end
        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
        its(:content) { is_expected.to include "\"statesman\", \"~> 1.2.0\"" }
      end
    end

    describe "the updated lockfile" do
      subject(:file) { updated_files.find { |f| f.name == "Gemfile.lock" } }

      context "when no change is required" do
        let(:gemfile_fixture_name) { "Gemfile" }
        let(:dependency_version) { "1.4.0" }
        let(:requirements) do
          [{ file: "Gemfile", requirement: "~>1.4.0", groups: [], source: nil }]
        end
        let(:previous_requirements) do
          [{ file: "Gemfile", requirement: "~>1.4.0", groups: [], source: nil }]
        end

        it "raises" do
          expect { updated_files }.to raise_error(/Expected content to change/)
        end
      end

      context "when updating a sub-dependency" do
        let(:gemfile_fixture_name) { "subdependency" }
        let(:lockfile_fixture_name) { "subdependency.lock" }
        let(:dependency_name) { "i18n" }
        let(:dependency_version) { "0.7.0" }
        let(:dependency_previous_version) { "0.7.0.beta1" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        its(:content) { is_expected.to include("i18n (0.7.0)") }
      end

      context "when a gem has been yanked" do
        let(:gemfile_fixture_name) { "minor_version_specified" }
        let(:lockfile_fixture_name) { "yanked_gem.lock" }

        context "and it's that gem that we're attempting to bump" do
          it "locks the updated gem to the latest version" do
            expect(file.content).to include("business (1.5.0)")
            expect(file.content).to include("statesman (1.2.1)")
          end
        end

        context "and it's another gem" do
          let(:dependency_name) { "statesman" }
          let(:dependency_version) { "1.3.1" }
          let(:dependency_previous_version) { "1.2.1" }
          let(:requirements) do
            [{
              file: "Gemfile",
              requirement: "~> 1.3",
              groups: [],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "Gemfile",
              requirement: "~> 1.2",
              groups: [],
              source: nil
            }]
          end

          it "locks the updated gem to the latest version" do
            expect(file.content).to include("business (1.8.0)")
            expect(file.content).to include("statesman (1.3.1)")
          end
        end
      end

      context "when the old Gemfile specified the version" do
        let(:gemfile_fixture_name) { "version_specified" }

        it "locks the updated gem to the latest version" do
          expect(file.content).to include("business (1.5.0)")
        end

        it "doesn't change the version of the other (also outdated) gem" do
          expect(file.content).to include("statesman (1.2.1)")
        end

        it "preserves the BUNDLED WITH line in the lockfile" do
          expect(file.content).to include("BUNDLED WITH\n   1.10.6")
        end

        it "doesn't add in a RUBY VERSION" do
          expect(file.content).to_not include("RUBY VERSION")
        end
      end

      context "with a Gemfile that includes a file with require_relative" do
        let(:dependency_files) { [gemfile, lockfile, required_file] }
        let(:gemfile_fixture_name) { "includes_require_relative" }
        let(:lockfile_fixture_name) { "Gemfile.lock" }
        let(:required_file) do
          Dependabot::DependencyFile.new(
            name: "../some_other_file.rb",
            content: "SOME_CONTANT = 5",
            directory: directory
          )
        end
        let(:directory) { "app/" }

        it "locks the updated gem to the latest version" do
          expect(file.content).to include("business (1.5.0)")
        end
      end

      context "when the Gemfile specifies a Ruby version" do
        let(:gemfile_fixture_name) { "explicit_ruby" }
        let(:lockfile_fixture_name) { "explicit_ruby.lock" }

        it "locks the updated gem to the latest version" do
          expect(file.content).to include("business (1.5.0)")
        end

        it "preserves the Ruby version in the lockfile" do
          expect(file.content).to include("RUBY VERSION\n   ruby 2.2.0p0")
        end

        context "but the lockfile didn't include that version" do
          let(:lockfile_fixture_name) { "Gemfile.lock" }

          it "doesn't add in a RUBY VERSION" do
            expect(file.content).to_not include("RUBY VERSION")
          end
        end

        context "that is legacy" do
          let(:gemfile_fixture_name) { "legacy_ruby" }
          let(:lockfile_fixture_name) { "legacy_ruby.lock" }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "public_suffix",
              version: "1.4.6",
              previous_version: "1.4.0",
              requirements: [{
                file: "Gemfile",
                requirement: "~> 1.5.0",
                groups: [],
                source: nil
              }],
              previous_requirements: [{
                file: "Gemfile",
                requirement: "~> 1.4.0",
                groups: [],
                source: nil
              }],
              package_manager: "bundler"
            )
          end

          it "locks the updated gem to the latest version" do
            expect(file.content).to include "public_suffix (1.4.6)"
          end

          it "preserves the Ruby version in the lockfile" do
            expect(file.content).to include "RUBY VERSION\n   ruby 1.9.3p551"
          end
        end
      end

      context "given a Gemfile that loads a .ruby-version file" do
        let(:gemfile_fixture_name) { "ruby_version_file" }
        let(:ruby_version_file) do
          Dependabot::DependencyFile.new(content: "2.2", name: ".ruby-version")
        end
        let(:updater) do
          described_class.new(
            dependency_files: [gemfile, lockfile, ruby_version_file],
            dependencies: [dependency],
            credentials: [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }]
          )
        end

        it "locks the updated gem to the latest version" do
          expect(file.content).to include "business (1.5.0)"
        end
      end

      context "when the Gemfile.lock didn't have a BUNDLED WITH line" do
        let(:lockfile_fixture_name) { "no_bundled_with.lock" }

        it "doesn't add in a BUNDLED WITH" do
          expect(file.content).to_not include "BUNDLED WITH"
        end
      end

      context "when the old Gemfile didn't specify the version" do
        let(:gemfile_fixture_name) { "version_not_specified" }
        let(:lockfile_fixture_name) { "version_not_specified.lock" }

        it "locks the updated gem to the desired version" do
          expect(file.content).to include "business (1.5.0)"
          expect(file.content).to include "business\n"
        end

        it "doesn't change the version of the other (also outdated) gem" do
          expect(file.content).to include "statesman (1.2.1)"
        end
      end

      context "with multiple dependencies" do
        let(:gemfile_fixture_name) { "version_conflict" }
        let(:lockfile_fixture_name) { "version_conflict.lock" }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "rspec-mocks",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: requirements,
              previous_requirements: previous_requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "rspec-support",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: requirements,
              previous_requirements: previous_requirements,
              package_manager: "bundler"
            )
          ]
        end
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "3.6.0",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gemfile",
            requirement: "3.5.0",
            groups: [],
            source: nil
          }]
        end

        it "updates both dependencies" do
          expect(file.content).to include("rspec-mocks (3.6.0)")
          expect(file.content).to include("rspec-support (3.6.0)")
        end
      end

      context "when another gem in the Gemfile has a git source" do
        let(:gemfile_fixture_name) { "git_source" }
        let(:lockfile_fixture_name) { "git_source.lock" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "2.0.1",
            previous_version: "1.2.5",
            requirements: requirements,
            previous_requirements: previous_requirements,
            package_manager: "bundler"
          )
        end
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 2.0.1",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.2.0",
            groups: [],
            source: nil
          }]
        end

        it "updates the gem just fine" do
          expect(file.content).to include "statesman (2.0.1)"
        end

        it "doesn't update the git dependencies" do
          old_lock = lockfile_body.split(/^/)
          new_lock = file.content.split(/^/)

          %w(business prius que uk_phone_numbers).each do |dep|
            original_remote_line =
              old_lock.find { |l| l.include?("gocardless/#{dep}") }
            original_revision_line =
              old_lock[old_lock.find_index(original_remote_line) + 1]

            new_remote_line =
              new_lock.find { |l| l.include?("gocardless/#{dep}") }
            new_revision_line =
              new_lock[new_lock.find_index(original_remote_line) + 1]

            expect(new_remote_line).to eq(original_remote_line)
            expect(new_revision_line).to eq(original_revision_line)
            expect(new_lock.index(new_remote_line)).
              to eq(old_lock.index(original_remote_line))
          end
        end
      end

      context "for a git dependency" do
        let(:gemfile_fixture_name) { "git_source" }
        let(:lockfile_fixture_name) { "git_source.lock" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "prius",
            version: "06824855470b25ffd541720059700fd2e574d958",
            previous_version: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2",
            requirements: requirements,
            previous_requirements: previous_requirements,
            package_manager: "bundler"
          )
        end
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/prius",
              branch: "master",
              ref: "master"
            }
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/prius",
              branch: "master",
              ref: "master"
            }
          }]
        end

        it "updates the dependency's revision" do
          old_lock = lockfile_body.split(/^/)
          new_lock = file.content.split(/^/)

          original_remote_line =
            old_lock.find { |l| l.include?("gocardless/prius") }
          original_revision_line =
            old_lock[old_lock.find_index(original_remote_line) + 1]

          new_remote_line =
            new_lock.find { |l| l.include?("gocardless/prius") }
          new_revision_line =
            new_lock[new_lock.find_index(original_remote_line) + 1]

          expect(new_remote_line).to eq(original_remote_line)
          expect(new_revision_line).to_not eq(original_revision_line)
          expect(new_lock.index(new_remote_line)).
            to eq(old_lock.index(original_remote_line))
        end

        context "that specifies a version that needs updating" do
          context "with a gem that has a git source" do
            let(:gemfile_fixture_name) { "git_source_with_version" }
            let(:lockfile_fixture_name) { "git_source_with_version.lock" }
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "business",
                version: "c170ea081c121c00ed6fe8764e3557e731454b9d",
                previous_version: "c5bf1bd47935504072ac0eba1006cf4d67af6a7a",
                requirements: requirements,
                previous_requirements: previous_requirements,
                package_manager: "bundler"
              )
            end
            let(:requirements) do
              [{
                file: "Gemfile",
                requirement: "~> 1.14.0",
                groups: [],
                source: {
                  type: "git",
                  url: "http://github.com/gocardless/business"
                }
              }]
            end
            let(:previous_requirements) do
              [{
                file: "Gemfile",
                requirement: "~> 1.0.0",
                groups: [],
                source: {
                  type: "git",
                  url: "http://github.com/gocardless/business"
                }
              }]
            end
            its(:content) { is_expected.to include "business (~> 1.14.0)!" }
          end
        end
      end

      context "when another gem in the Gemfile has a path source" do
        let(:gemfile_fixture_name) { "path_source" }
        let(:lockfile_fixture_name) { "path_source.lock" }

        context "that we've downloaded" do
          let(:gemspec_body) { fixture("ruby", "gemspecs", "no_overlap") }
          let(:gemspec) do
            Dependabot::DependencyFile.new(
              content: gemspec_body,
              name: "plugins/example/example.gemspec"
            )
          end

          let(:dependency_files) { [gemfile, lockfile, gemspec] }

          it "updates the gem just fine" do
            expect(file.content).to include "business (1.5.0)"
          end

          it "does not change the original path" do
            expect(file.content).to include "remote: plugins/example"
            expect(file.content).
              not_to include Dependabot::SharedHelpers::BUMP_TMP_FILE_PREFIX
            expect(file.content).
              not_to include Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH
          end

          context "that requires other files" do
            let(:gemspec_body) do
              fixture("ruby", "gemspecs", "no_overlap_with_require")
            end

            it "updates the gem just fine" do
              expect(file.content).to include "business (1.5.0)"
            end

            it "doesn't change the version of the path dependency" do
              expect(file.content).to include "example (0.9.3)"
            end
          end
        end
      end

      context "when the Gemfile evals a child gemfile" do
        let(:dependency_files) { [gemfile, lockfile, child_gemfile] }
        let(:gemfile_fixture_name) { "eval_gemfile" }
        let(:child_gemfile) do
          Dependabot::DependencyFile.new(
            content: child_gemfile_body,
            name: "backend/Gemfile"
          )
        end
        let(:child_gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
        let(:lockfile_fixture_name) { "path_source.lock" }
        let(:requirements) do
          [
            {
              file: "Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            },
            {
              file: "backend/Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            }
          ]
        end
        let(:previous_requirements) do
          [
            {
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            },
            {
              file: "backend/Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ]
        end

        it "updates the gem just fine" do
          expect(file.content).to include "business (1.5.0)"
        end

        context "when the dependency only appears in the child Gemfile" do
          let(:dependency_name) { "statesman" }
          let(:dependency_version) { "1.3.1" }
          let(:dependency_previous_version) { "1.2.1" }
          let(:requirements) do
            [{
              file: "backend/Gemfile",
              requirement: "~> 1.3.1",
              groups: [],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "backend/Gemfile",
              requirement: "~> 1.2.0",
              groups: [],
              source: nil
            }]
          end

          it "updates the gem just fine" do
            expect(file.content).to include "statesman (1.3.1)"
          end
        end
      end

      context "with a Gemfile that imports a gemspec" do
        let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }
        let(:gemfile_fixture_name) { "imports_gemspec" }
        let(:lockfile_fixture_name) { "imports_gemspec.lock" }
        let(:gemspec) do
          Dependabot::DependencyFile.new(
            content: gemspec_body,
            name: "example.gemspec"
          )
        end

        let(:dependency_files) { [gemfile, lockfile, gemspec] }

        context "when the gem in the gemspec isn't being updated" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "statesman",
              version: "2.0.0",
              previous_version: "1.4.0",
              requirements: [{
                file: "Gemfile",
                requirement: "~> 2.0",
                groups: [],
                source: nil
              }],
              previous_requirements: [{
                file: "Gemfile",
                requirement: "~> 1.2.0",
                groups: [],
                source: nil
              }],
              package_manager: "bundler"
            )
          end

          it "returns an updated Gemfile and Gemfile.lock" do
            expect(updated_files.map(&:name)).
              to match_array(["Gemfile", "Gemfile.lock"])
          end
        end

        context "when the gem in the gemspec is being updated" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.8.0",
              previous_version: "1.4.0",
              requirements: [
                {
                  file: "example.gemspec",
                  requirement: requirement,
                  groups: [],
                  source: nil
                },
                {
                  file: "Gemfile",
                  requirement: requirement,
                  groups: [],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  file: "example.gemspec",
                  requirement: "~> 1.0",
                  groups: [],
                  source: nil
                },
                {
                  file: "Gemfile",
                  requirement: "~> 1.4.0",
                  groups: [],
                  source: nil
                }
              ],
              package_manager: "bundler"
            )
          end
          let(:requirement) { ">= 1.0, < 3.0" }

          it "returns an updated gemspec, Gemfile and Gemfile.lock" do
            expect(updated_files.map(&:name)).
              to match_array(["Gemfile", "Gemfile.lock", "example.gemspec"])
          end

          context "but the gemspec constraint is already satisfied" do
            let(:requirement) { "~> 1.0" }

            it "returns an updated Gemfile and Gemfile.lock" do
              expect(updated_files.map(&:name)).
                to match_array(["Gemfile", "Gemfile.lock"])
            end
          end

          context "and only appears in the gemspec" do
            let(:gemspec_body) { fixture("ruby", "gemspecs", "no_overlap") }
            let(:lockfile_fixture_name) { "imports_gemspec_no_overlap.lock" }
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "json",
                version: "2.0.3",
                previous_version: "1.8.6",
                requirements: [{
                  file: "example.gemspec",
                  requirement: ">= 1.0, < 3.0",
                  groups: [],
                  source: nil
                }],
                previous_requirements: [{
                  file: "example.gemspec",
                  requirement: "~> 1.0",
                  groups: [],
                  source: nil
                }],
                package_manager: "bundler"
              )
            end

            it "returns an updated gemspec and Gemfile.lock" do
              expect(updated_files.map(&:name)).
                to match_array(["example.gemspec", "Gemfile.lock"])
            end
          end
        end
      end
    end

    context "when provided with only a gemspec" do
      let(:dependency_files) { [gemspec] }

      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemspec_body) { fixture("ruby", "gemspecs", "example") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "5.1.0",
          requirements: [{
            file: "example.gemspec",
            requirement: ">= 4.6, < 6.0",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "example.gemspec",
            requirement: "~> 4.6",
            groups: [],
            source: nil
          }],
          package_manager: "bundler"
        )
      end
      let(:dependency_name) { "octokit" }

      it "returns DependencyFile objects" do
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated gemspec" do
        subject(:updated_gemspec) { updated_files.first }

        context "when no change is required" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: dependency_name,
              version: "5.1.0",
              requirements: [{
                file: "example.gemspec",
                requirement: "~> 4.6",
                groups: [],
                source: nil
              }],
              previous_requirements: [{
                file: "example.gemspec",
                requirement: "~> 4.6",
                groups: [],
                source: nil
              }],
              package_manager: "bundler"
            )
          end
          it { is_expected.to be_nil }
        end

        its(:content) do
          is_expected.to include(%("octokit", ">= 4.6", "< 6.0"\n))
        end

        context "with a runtime dependency" do
          let(:dependency_name) { "bundler" }

          its(:content) do
            is_expected.to include(%("bundler", ">= 4.6", "< 6.0"\n))
          end
        end

        context "with a development dependency" do
          let(:dependency_name) { "webmock" }

          its(:content) do
            is_expected.to include(%("webmock", ">= 4.6", "< 6.0"\n))
          end
        end

        context "with an array of requirements" do
          let(:dependency_name) { "excon" }

          its(:content) do
            is_expected.to include(%("excon", ">= 4.6", "< 6.0"\n))
          end
        end

        context "with brackets around the requirements" do
          let(:dependency_name) { "gemnasium-parser" }

          its(:content) do
            is_expected.to include(%("gemnasium-parser", ">= 4.6", "< 6.0"\)\n))
          end
        end

        context "with single quotes" do
          let(:dependency_name) { "gems" }

          its(:content) do
            is_expected.to include(%('gems', '>= 4.6', '< 6.0'\n))
          end
        end
      end
    end

    context "when provided with a Gemfile and a gemspec" do
      let(:dependency_files) { [gemfile, gemspec] }

      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemspec_body) { fixture("ruby", "gemspecs", "example") }
      let(:gemfile_fixture_name) { "imports_gemspec" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "5.1.0",
          requirements: requirements,
          previous_requirements: previous_requirements,
          package_manager: "bundler"
        )
      end
      let(:requirements) do
        [{
          file: "example.gemspec",
          requirement: ">= 4.6, < 6.0",
          groups: [],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "example.gemspec",
          requirement: "~> 4.6",
          groups: [],
          source: nil
        }]
      end
      let(:dependency_name) { "octokit" }

      it "returns an updated gemspec DependencyFile objects" do
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.name).to eq("example.gemspec")
      end

      context "when the gem appears in both" do
        let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }
        let(:dependency_name) { "business" }
        let(:requirements) do
          [
            {
              file: "example.gemspec",
              requirement: ">= 1.0, < 6.0",
              groups: [],
              source: nil
            },
            {
              file: "Gemfile",
              requirement: "~> 5.1.0",
              groups: [],
              source: nil
            }
          ]
        end
        let(:previous_requirements) do
          [
            {
              file: "example.gemspec",
              requirement: "~> 1.0",
              groups: [],
              source: nil
            },
            {
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ]
        end

        its(:length) { is_expected.to eq(2) }

        describe "the updated gemspec" do
          subject(:updated_gemspec) do
            updated_files.find { |f| f.name == "example.gemspec" }
          end

          its(:content) do
            is_expected.to include(%('business', '>= 1.0', '< 6.0'\n))
          end
        end

        describe "the updated gemfile" do
          subject(:updated_gemfile) do
            updated_files.find { |f| f.name == "Gemfile" }
          end

          its(:content) { is_expected.to include(%("business", "~> 5.1.0"\n)) }
        end
      end
    end

    context "when provided with only a Gemfile" do
      let(:dependency_files) { [gemfile] }

      describe "the updated gemfile" do
        subject(:updated_gemfile) do
          updated_files.find { |f| f.name == "Gemfile" }
        end

        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
      end
    end

    context "with a Gemfile, Gemfile.lock and gemspec (not imported)" do
      let(:dependency_files) { [gemfile, lockfile, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: fixture("ruby", "gemspecs", "with_require"),
          name: "some.gemspec"
        )
      end

      context "with a dependency that appears in the Gemfile" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "1.4.0",
            requirements: [{
              file: "Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }],
            package_manager: "bundler"
          )
        end

        describe "the updated gemfile" do
          subject(:updated_gemfile) do
            updated_files.find { |f| f.name == "Gemfile" }
          end

          its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
        end
      end

      context "with a dependency that appears in the gemspec" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "octokit",
            requirements: [{
              file: "some.gemspec",
              requirement: ">= 4.6, < 6.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "some.gemspec",
              requirement: "~> 4.6",
              groups: [],
              source: nil
            }],
            package_manager: "bundler"
          )
        end

        describe "the updated gemspec" do
          subject(:updated_gemspec) do
            updated_files.find { |f| f.name == "some.gemspec" }
          end

          its(:content) do
            is_expected.to include "\"octokit\", \">= 4.6\", \"< 6.0\""
          end
        end
      end
    end

    context "when provided with only a Gemfile.lock" do
      let(:dependency_files) { [lockfile] }

      it "raises on initialization" do
        expect { updater }.to raise_error(/Gemfile must be provided/)
      end
    end

    context "when provided with only a gemspec and Gemfile.lock" do
      let(:dependency_files) { [lockfile, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: fixture("ruby", "gemspecs", "example"),
          name: "example.gemspec"
        )
      end

      it "raises on initialization" do
        expect { updater }.to raise_error(/Gemfile must be provided/)
      end
    end
  end
end
