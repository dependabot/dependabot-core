# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Bundler::FileUpdater do
  include_context "stub rubygems compact index"

  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com"
      }],
      repo_contents_path: repo_contents_path
    )
  end
  let(:dependencies) { [dependency] }
  let(:project_name) { "gemfile" }
  let(:dependency_files) { bundler_project_dependency_files(project_name) }
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
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
  let(:repo_contents_path) { nil }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.not_to(change { Dir.entries(tmp_path) })
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
        let(:project_name) { "version_not_specified" }

        let(:requirements) do
          [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
        end
        let(:previous_requirements) do
          [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
        end
        it { is_expected.to be_nil }
      end

      context "when the full version is specified" do
        let(:project_name) { "version_specified_gemfile" }
        let(:gemfile) { bundler_project_dependency_file(project_name, filename: "Gemfile") }

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

        it "delegates to GemfileUpdater" do
          expect(described_class::GemfileUpdater).
            to receive(:new).
            with(dependencies: dependencies, gemfile: gemfile).
            and_call_original.
            twice

          expect(updated_gemfile.content).
            to include("\"business\", \"~> 1.5.0\"")
          expect(updated_gemfile.content).
            to include("\"statesman\", \"~> 1.2.0\"")
        end

        context "for a gems.rb setup" do
          subject(:updated_gemfile) do
            updated_files.find { |f| f.name == "gems.rb" }
          end

          let(:project_name) { "gems_rb" }
          let(:gemfile) { bundler_project_dependency_file(project_name, filename: "gems.rb") }

          let(:requirements) do
            [{
              file: "gems.rb",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "gems.rb",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }]
          end

          it "delegates to GemfileUpdater" do
            expect(described_class::GemfileUpdater).
              to receive(:new).
              with(dependencies: dependencies, gemfile: gemfile).
              and_call_original.
              twice

            expect(updated_gemfile.content).
              to include("\"business\", \"~> 1.5.0\"")
            expect(updated_gemfile.content).
              to include("\"statesman\", \"~> 1.2.0\"")
          end
        end
      end

      context "when updating a sub-dependency" do
        let(:project_name) { "subdependency" }

        let(:dependency_name) { "i18n" }
        let(:dependency_version) { "0.7.0" }
        let(:dependency_previous_version) { "0.7.0.beta1" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        it { is_expected.to be_nil }
      end
    end

    describe "a child gemfile" do
      subject(:updated_gemfile) do
        updated_files.find { |f| f.name == "backend/Gemfile" }
      end

      context "when no change is required" do
        let(:project_name) { "nested_gemfile_version_not_specified" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: nil
          }, {
            file: "backend/Gemfile",
            requirement: ">= 0",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: nil
          }, {
            file: "backend/Gemfile",
            requirement: ">= 0",
            groups: [],
            source: nil
          }]
        end
        it { is_expected.to be_nil }
      end

      context "when a change is required" do
        let(:project_name) { "nested_gemfile" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.5.0",
            groups: [],
            source: nil
          }, {
            file: "backend/Gemfile",
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
          }, {
            file: "backend/Gemfile",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }]
        end
        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
        its(:content) { is_expected.to include "\"statesman\", \"~> 1.2.0\"" }
      end
    end

    describe "the updated lockfile" do
      subject(:file) { updated_files.find { |f| f.name == "Gemfile.lock" } }

      context "when no change is required" do
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
        let(:project_name) { "subdependency" }
        let(:dependency_name) { "i18n" }
        let(:dependency_version) { "0.7.0" }
        let(:dependency_previous_version) { "0.7.0.beta1" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        its(:content) { is_expected.to include("i18n (0.7.0)") }

        context "which is blocked by another sub-dep" do
          let(:project_name) { "subdep_blocked_by_subdep" }
          let(:dependency_name) { "dummy-pkg-a" }
          let(:dependency_version) { "1.1.0" }
          let(:dependency_previous_version) { "1.0.1" }

          it "updates the lockfile correctly" do
            expect(file.content).to include("dummy-pkg-a (1.1.0)")
            expect(file.content).not_to include("\n  dummy-pkg-a (= 1.1.0)")
          end
        end
      end

      context "when updating a dep blocked by a sub-dep" do
        let(:project_name) { "blocked_by_subdep" }
        let(:dependency_name) { "dummy-pkg-a" }
        let(:dependency_version) { "1.1.0" }
        let(:dependency_previous_version) { "1.0.1" }
        let(:requirements) do
          [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
        end
        let(:previous_requirements) { requirements }

        its(:content) { is_expected.to include("dummy-pkg-a (1.1.0)") }
      end

      context "when a gem has been yanked" do
        let(:project_name) { "minor_version_specified_yanked_gem" }

        context "and it's that gem that we're attempting to bump" do
          it "locks the updated gem to the latest version" do
            expect(file.content).to include("business (1.5.0)")
          end

          it "does not update unrelated dependencies" do
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
            expect(file.content).to include("statesman (1.3.1)")
          end

          it "locks the yanked gem to the latest version allowed by the Gemfile", :bundler_v1_only do
            expect(file.content).to include("business (1.18.0)")
          end

          it "does not touch the yanked gem", :bundler_v2_only do
            expect(file.content).to include("business (1.4.1)")
          end
        end
      end

      context "when the old Gemfile specified the version" do
        let(:project_name) { "version_specified_gemfile" }

        it "locks the updated gem to the latest version" do
          expect(file.content).to include("business (1.5.0)")
        end

        it "doesn't change the version of the other (also outdated) gem" do
          expect(file.content).to include("statesman (1.2.1)")
        end

        it "preserves the BUNDLED WITH line in the lockfile", :bundler_v1_only do
          expect(file.content).to include("BUNDLED WITH\n   1.10.6")
        end

        it "preserves the BUNDLED WITH line in the lockfile", :bundler_v2_only do
          expect(file.content).to include("BUNDLED WITH\n   2.2.0")
        end

        it "doesn't add in a RUBY VERSION" do
          expect(file.content).not_to include("RUBY VERSION")
        end

        context "for a gems.rb setup" do
          let(:project_name) { "gems_rb" }

          subject(:file) { updated_files.find { |f| f.name == "gems.locked" } }

          let(:requirements) do
            [{
              file: "gems.rb",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "gems.rb",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }]
          end

          it "locks the updated gem to the latest version" do
            expect(file.content).to include("business (1.5.0)")
          end
        end
      end

      context "when unlocking another top-level dep would cause an error" do
        let(:project_name) { "cant_unlock_subdep" }
        let(:dependency_name) { "ibandit" }
        let(:dependency_version) { "0.11.5" }
        let(:dependency_previous_version) { "0.6.6" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 0.6.0",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 0.11.5",
            groups: [],
            source: nil
          }]
        end

        it "locks the updated gem to the latest version" do
          expect(file.content).to include("ibandit (0.11.5)")
          expect(file.content).
            to include("d049c7115f59689efb123d61430c078c6feb7537")
        end
      end

      context "with a Gemfile that includes a file with require_relative" do
        let(:project_name) { "includes_require_relative_nested" }

        it "locks the updated gem to the latest version" do
          expect(file.content).to include("business (1.5.0)")
        end
      end

      context "with a default gem specified" do
        let(:project_name) { "default_gem_specified" }
        let(:requirements) do
          [{ file: "Gemfile", requirement: "~> 1.5", groups: [], source: nil }]
        end
        let(:previous_requirements) do
          [{ file: "Gemfile", requirement: "~> 1.4", groups: [], source: nil }]
        end

        it "locks the updated gem to the latest version" do
          expect(file.content).to include("business (1.5.0)")
        end
      end

      context "with an imported gemspec that specifies a minimum Ruby version not satisfied by the running Ruby" do
        let(:project_name) { "unsatisfied_required_ruby_version" }

        before do
          require "dependabot/bundler/file_updater/ruby_requirement_setter"

          stub_const(
            "#{described_class}::RubyRequirementSetter::RUBY_VERSIONS",
            described_class::RubyRequirementSetter::RUBY_VERSIONS + ["99.0.0"]
          )
        end

        it "locks the updated gem to the latest version" do
          expect(file.content).to include("business (1.5.0)")
        end

        it "doesn't add in a RUBY VERSION" do
          expect(file.content).not_to include("RUBY VERSION")
        end
      end

      context "when the Gemfile specifies a Ruby version" do
        let(:project_name) { "explicit_ruby_in_lockfile" }

        it "locks the updated gem to the latest version" do
          expect(file.content).to include("business (1.5.0)")
        end

        it "preserves the Ruby version in the lockfile" do
          expect(file.content).to include("RUBY VERSION\n   ruby 2.2.0p0")
        end

        context "but the lockfile didn't include that version" do
          let(:project_name) { "explicit_ruby" }

          it "doesn't add in a RUBY VERSION" do
            expect(file.content).not_to include("RUBY VERSION")
          end
        end

        context "that is legacy" do
          let(:project_name) { "legacy_ruby" }
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
        let(:project_name) { "ruby_version_file" }
        let(:updater) do
          described_class.new(
            dependency_files: dependency_files,
            dependencies: [dependency],
            credentials: [{
              "type" => "git_source",
              "host" => "github.com"
            }]
          )
        end

        it "locks the updated gem to the latest version" do
          expect(file.content).to include "business (1.5.0)"
        end
      end

      context "when the Gemfile.lock didn't have a BUNDLED WITH line" do
        let(:project_name) { "no_bundled_with" }

        it "doesn't add in a BUNDLED WITH" do
          expect(file.content).not_to include "BUNDLED WITH"
        end
      end

      context "when the old Gemfile didn't specify the version" do
        let(:project_name) { "version_not_specified" }

        it "locks the updated gem to the desired version" do
          expect(file.content).to include "business (1.5.0)"
          expect(file.content).to include "business\n"
        end

        it "doesn't change the version of the other (also outdated) gem" do
          expect(file.content).to include "statesman (1.2.1)"
        end
      end

      context "with multiple dependencies" do
        let(:project_name) { "version_conflict" }
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
        let(:project_name) { "git_source" }
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
          old_lock = bundler_project_dependency_file("git_source", filename: "Gemfile.lock").content.split(/^/)
          new_lock = file.content.split(/^/)

          %w(business prius uk_phone_numbers).each do |dep|
            original_remote_line =
              old_lock.find { |l| l.include?("dependabot-fixtures/#{dep}") }
            original_revision_line =
              old_lock[old_lock.find_index(original_remote_line) + 1]

            new_remote_line =
              new_lock.find { |l| l.include?("dependabot-fixtures/#{dep}") }
            new_revision_line =
              new_lock[new_lock.find_index(original_remote_line) + 1]

            expect(new_remote_line).to eq(original_remote_line)
            expect(new_revision_line).to eq(original_revision_line)
            expect(new_lock.index(new_remote_line)).
              to eq(old_lock.index(original_remote_line))
          end
        end

        context "that specifies the dependency using github:" do
          let(:project_name) { "github_source" }

          it "doesn't update the git dependencies" do
            old_lock = bundler_project_dependency_file("github_source", filename: "Gemfile.lock").content.split(/^/)
            new_lock = file.content.split(/^/)

            original_remote_line =
              old_lock.find { |l| l.include?("dependabot-fixtures/business") }
            original_revision_line =
              old_lock[old_lock.find_index(original_remote_line) + 1]

            new_remote_line =
              new_lock.find { |l| l.include?("dependabot-fixtures/business") }

            new_revision_line =
              new_lock[new_lock.find_index(new_remote_line) + 1]

            expect(new_remote_line).to eq(original_remote_line)
            expect(new_revision_line).to eq(original_revision_line)
            expect(new_lock.index(new_remote_line)).
              to eq(old_lock.index(original_remote_line))
          end
        end

        context "and the git dependency is used internally" do
          let(:project_name) { "git_source_internal" }

          it "doesn't update the git dependency's version" do
            expect(file.content).to include("parallel (1.12.0)")
          end
        end

        context "and the git dependencies are in a weird order" do
          let(:project_name) { "git_source_reordered" }

          it "doesn't update the order of the git dependencies" do
            old_lock = bundler_project_dependency_file("git_source_reordered",
                                                       filename: "Gemfile.lock").content.split(/^/)
            new_lock = file.content.split(/^/)

            %w(business prius uk_phone_numbers).each do |dep|
              original_remote_line =
                old_lock.find { |l| l.include?("dependabot-fixtures/#{dep}") }
              original_revision_line =
                old_lock[old_lock.find_index(original_remote_line) + 1]

              new_remote_line =
                new_lock.find { |l| l.include?("dependabot-fixtures/#{dep}") }
              new_revision_line =
                new_lock[new_lock.find_index(original_remote_line) + 1]

              expect(new_remote_line).to eq(original_remote_line)
              expect(new_revision_line).to eq(original_revision_line)
              expect(new_lock.index(new_remote_line)).
                to eq(old_lock.index(original_remote_line))
            end

            # Check that nothing strange has happened to the formatting anywhere
            expected_lockfile =
              bundler_project_dependency_file("git_source_reordered", filename: "Gemfile.lock").content.
              gsub("1.2.5", "2.0.1").gsub("~> 1.2.0", "~> 2.0.1")
            expect(file.content).to eq(expected_lockfile)
          end
        end

        context "and the lockfile was wrong before" do
          let(:project_name) { "git_source_outdated" }

          it "generates the correct lockfile" do
            expect(file.content).to include("statesman (2.0.1)")
            expect(file.content).
              to include "remote: http://github.com/dependabot-fixtures/uk_phone_numbers"
          end
        end
      end

      context "for a git dependency" do
        let(:project_name) { "git_source" }
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
              url: "https://github.com/dependabot-fixtures/prius",
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
              url: "https://github.com/dependabot-fixtures/prius",
              branch: "master",
              ref: "master"
            }
          }]
        end

        it "updates the dependency's revision" do
          old_lock = dependency_files.find { |f| f.name == "Gemfile.lock" }.content.split(/^/)
          new_lock = file.content.split(/^/)

          original_remote_line =
            old_lock.find { |l| l.include?("dependabot-fixtures/prius") }
          original_revision_line =
            old_lock[old_lock.find_index(original_remote_line) + 1]

          new_remote_line =
            new_lock.find { |l| l.include?("dependabot-fixtures/prius") }
          new_revision_line =
            new_lock[new_lock.find_index(original_remote_line) + 1]

          expect(new_remote_line).to eq(original_remote_line)
          expect(new_revision_line).not_to eq(original_revision_line)
          expect(new_lock.index(new_remote_line)).
            to eq(old_lock.index(original_remote_line))
        end

        context "when a git source is specified that multiple deps use" do
          let(:project_name) { "git_source_with_multiple_deps" }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "elasticsearch-dsl",
              version: "86a36ec0db704b2a62dd4d5fe9edf887625b1826",
              previous_version: "43f48b229a975b77c5339644d512c88389fefafa",
              requirements: requirements,
              previous_requirements: previous_requirements,
              package_manager: "bundler"
            )
          end
          let(:requirements) { previous_requirements }
          let(:previous_requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/dependabot-fixtures/elasticsearch-ruby.git",
                branch: "5.x",
                ref: "5.x"
              }
            }]
          end

          it "updates the dependency's revision" do
            old_lock = dependency_files.find { |f| f.name == "Gemfile.lock" }.content.split(/^/)
            new_lock = file.content.split(/^/)

            original_remote_line =
              old_lock.find { |l| l.include?("elasticsearch-ruby") }
            original_revision_line =
              old_lock[old_lock.find_index(original_remote_line) + 1]

            new_remote_line =
              new_lock.find { |l| l.include?("elasticsearch-ruby") }
            new_revision_line =
              new_lock[new_lock.find_index(new_remote_line) + 1]

            expect(new_remote_line).to eq(original_remote_line)
            expect(new_revision_line).not_to eq(original_revision_line)
            expect(new_lock.index(new_remote_line)).
              to eq(old_lock.index(original_remote_line))
          end
        end

        context "that specifies a version that needs updating" do
          context "with a gem that has a git source" do
            let(:project_name) { "git_source_with_version_gemfile" }
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "dependabot-test-ruby-package",
                version: "1c6331732c41e4557a16dacb82534f1d1c831848",
                previous_version: "81073f9462f228c6894e3e384d0718def310d99f",
                requirements: requirements,
                previous_requirements: previous_requirements,
                package_manager: "bundler"
              )
            end
            let(:requirements) do
              [{
                file: "Gemfile",
                requirement: "~> 1.0.1",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/dependabot-fixtures/"\
                  "dependabot-test-ruby-package"
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
                  url: "https://github.com/dependabot-fixtures/"\
                  "dependabot-test-ruby-package"
                }
              }]
            end
            its(:content) do
              is_expected.to include "dependabot-test-ruby-package (~> 1.0.1)!"
            end
          end
        end
      end

      context "when another gem in the Gemfile has a path source" do
        context "that we've downloaded" do
          let(:project_name) { "path_source_no_overlap" }

          it "updates the gem just fine" do
            expect(file.content).to include "business (1.5.0)"
          end

          it "does not change the original path" do
            expect(file.content).to include "remote: plugins/example"
            expect(file.content).
              not_to include Dependabot::Utils::BUMP_TMP_FILE_PREFIX
            expect(file.content).
              not_to include Dependabot::Utils::BUMP_TMP_DIR_PATH
          end

          context "as a .specification" do
            let(:project_name) { "path_source_statesman" }

            it "updates the gem just fine" do
              expect(file.content).to include "business (1.5.0)"
            end
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
        let(:project_name) { "eval_gemfile_gemfile" }
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.5.0",
            groups: [],
            source: nil
          }, {
            file: "backend/Gemfile",
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
          }, {
            file: "backend/Gemfile",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }]
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
        let(:project_name) { "imports_gemspec" }

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

          context "with a tricky ruby requirement" do
            let(:gemspec_body) { fixture("ruby", "gemspecs", "tricky_ruby") }

            it "returns an updated Gemfile and Gemfile.lock" do
              expect(updated_files.map(&:name)).
                to match_array(["Gemfile", "Gemfile.lock"])
            end
          end
        end

        context "when the gem in the gemspec is being updated" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.8.0",
              previous_version: "1.4.0",
              requirements: [{
                file: "example.gemspec",
                requirement: requirement,
                groups: [],
                source: nil
              }, {
                file: "Gemfile",
                requirement: requirement,
                groups: [],
                source: nil
              }],
              previous_requirements: [{
                file: "example.gemspec",
                requirement: "~> 1.0",
                groups: [],
                source: nil
              }, {
                file: "Gemfile",
                requirement: "~> 1.4.0",
                groups: [],
                source: nil
              }],
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

          context "when updating a gemspec with a path" do
            let(:project_name) { "imports_gemspec_from_path" }

            let(:dependency) do
              Dependabot::Dependency.new(
                name: "business",
                version: "1.8.0",
                previous_version: "1.4.0",
                requirements: [{
                  file: "subdir/example.gemspec",
                  requirement: requirement,
                  groups: [],
                  source: nil
                }, {
                  file: "Gemfile",
                  requirement: requirement,
                  groups: [],
                  source: nil
                }],
                previous_requirements: [{
                  file: "subdir/example.gemspec",
                  requirement: "~> 1.0",
                  groups: [],
                  source: nil
                }, {
                  file: "Gemfile",
                  requirement: "~> 1.4.0",
                  groups: [],
                  source: nil
                }],
                package_manager: "bundler"
              )
            end

            it "returns an updated gemspec, Gemfile and Gemfile.lock" do
              expect(updated_files.map(&:name)).
                to match_array(%w(Gemfile Gemfile.lock subdir/example.gemspec))
            end
          end

          context "and only appears in the gemspec" do
            let(:project_name) { "imports_gemspec_no_overlap" }
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
      let(:project_name) { "gemspec_no_lockfile" }
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

          it "raises an error" do
            expect { updated_files }.to raise_error("No files have changed!")
          end
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
      let(:project_name) { "imports_gemspec_no_lockfile" }
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
        let(:project_name) { "imports_gemspec_small_example_no_lockfile" }
        let(:dependency_name) { "business" }
        let(:requirements) do
          [{
            file: "example.gemspec",
            requirement: ">= 1.0, < 6.0",
            groups: [],
            source: nil
          }, {
            file: "Gemfile",
            requirement: "~> 5.1.0",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "example.gemspec",
            requirement: "~> 1.0",
            groups: [],
            source: nil
          }, {
            file: "Gemfile",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }]
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
      let(:project_name) { "no_lockfile" }

      describe "the updated gemfile" do
        subject(:updated_gemfile) do
          updated_files.find { |f| f.name == "Gemfile" }
        end

        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
      end
    end

    context "with a Gemfile, Gemfile.lock and gemspec (not imported)" do
      let(:project_name) { "gemspec_not_imported" }

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

        describe "the updated gemspec" do
          subject(:updated_gemspec) do
            updated_files.find { |f| f.name == "example.gemspec" }
          end

          its(:content) do
            is_expected.to include "\"octokit\", \">= 4.6\", \"< 6.0\""
          end
        end
      end
    end

    context "when provided with only a Gemfile.lock" do
      let(:project_name) { "lockfile_only" }

      it "raises on initialization" do
        expect { updater }.to raise_error(/Gemfile must be provided/)
      end
    end

    context "when provided with only a gemspec and Gemfile.lock" do
      let(:project_name) { "gemspec_no_gemfile" }

      it "raises on initialization" do
        expect { updater }.to raise_error(/Gemfile must be provided/)
      end
    end

    context "for a gem that depends on bundler" do
      subject(:updated_gemfile) do
        updated_files.find { |f| f.name == "Gemfile" }
      end

      let(:project_name) { "guard_bundler" }
      let(:dependency_name) { "guard-bundler" }
      let(:dependency_version) { "3.0.0" }
      let(:dependency_previous_version) { "2.2.1" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 2.2.1",
          groups: [],
          source: nil
        }]
      end

      it "raises an error", :bundler_v1_only do
        expect { updated_gemfile }.to raise_error(/Bundler could not find compatible versions for gem "bundler"/)
      end

      it "returns the latest version", :bundler_v2_only do
        expect(updated_gemfile.content).to include("\"guard-bundler\", \"~> 2.2.1\"")
      end
    end

    context "vendoring" do
      let(:project_name) { "vendored_gems" }
      let(:repo_contents_path) { bundler_build_tmp_repo(project_name) }

      before do
        stub_request(:get, "https://rubygems.org/gems/business-1.5.0.gem").
          to_return(
            status: 200,
            body: fixture("ruby", "gems", "business-1.5.0.gem")
          )
      end

      after do
        FileUtils.remove_entry repo_contents_path
        ::Bundler.settings.temporary(persistent_gems_after_clean: nil)
      end

      it "vendors the new dependency" do
        expect(updater.updated_dependency_files.map(&:name)).to match_array(
          [
            "vendor/cache/business-1.4.0.gem",
            "vendor/cache/business-1.5.0.gem",
            "Gemfile",
            "Gemfile.lock"
          ]
        )
      end

      it "base64 encodes vendored gems" do
        file = updater.updated_dependency_files.find do |f|
          f.name == "vendor/cache/business-1.5.0.gem"
        end

        expect(file.content_encoding).to eq("base64")
      end

      it "deletes the old vendored gem" do
        file = updater.updated_dependency_files.find do |f|
          f.name == "vendor/cache/business-1.4.0.gem"
        end

        expect(file.operation).to eq Dependabot::DependencyFile::Operation::DELETE
      end

      context "persistent gems after clean" do
        let(:project_name) { "vendored_persistent_gems" }

        it "does not delete cached files marked as persistent" do
          file = updater.updated_dependency_files.find do |f|
            f.name == "vendor/cache/business-1.4.0.gem"
          end

          vendor_files =
            Dir.entries(Pathname.new(repo_contents_path).join("vendor/cache"))

          expect(file).to be_nil
          expect(vendor_files).to include("business-1.4.0.gem")
        end
      end

      context "with dependencies that are not unlocked by the update" do
        let(:project_name) { "conditional" }

        before do
          stub_request(:get, "https://rubygems.org/gems/statesman-1.2.1.gem").
            to_return(
              status: 200,
              body: fixture("ruby", "gems", "statesman-1.2.1.gem")
            )
        end

        it "does not delete the cached file" do
          file = updater.updated_dependency_files.find do |f|
            f.name == "vendor/cache/addressable-7.2.0.gem"
          end
          vendor_files =
            Dir.entries(Pathname.new(repo_contents_path).join("vendor/cache"))

          expect(file).to be_nil
          expect(vendor_files).to include("statesman-7.2.0.gem")
        end
      end

      context "with a git dependency" do
        let(:project_name) { "vendored_git" }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "dependabot-test-ruby-package",
            version: "1c6331732c41e4557a16dacb82534f1d1c831848",
            previous_version: "81073f9462f228c6894e3e384d0718def310d99f",
            requirements: requirements,
            previous_requirements: previous_requirements,
            package_manager: "bundler"
          )
        end
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.0.1",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/"\
              "dependabot-test-ruby-package"
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
              url: "https://github.com/dependabot-fixtures/"\
              "dependabot-test-ruby-package"
            }
          }]
        end

        removed = "vendor/cache/dependabot-test-ruby-package-81073f9462f2"
        added = "vendor/cache/dependabot-test-ruby-package-1c6331732c41"

        it "vendors the new dependency" do
          expect(updater.updated_dependency_files.map(&:name)).to match_array(
            [
              "#{removed}/.bundlecache",
              "#{removed}/README.md",
              "#{removed}/test-ruby-package.gemspec",
              "#{added}/.bundlecache",
              "#{added}/.gitignore",
              "#{added}/README.md",
              "#{added}/dependabot-test-ruby-package.gemspec",
              # modified:
              "Gemfile",
              "Gemfile.lock"
            ]
          )
        end

        it "deletes the old vendored repo" do
          file = updater.updated_dependency_files.find do |f|
            f.name == "#{removed}/.bundlecache"
          end

          expect(file&.operation).to eq Dependabot::DependencyFile::Operation::DELETE
        end

        it "does not base64 encode vendored code" do
          updater.updated_dependency_files.
            select { |f| f.name.start_with?(added) }.
            reject { |f| f.name.end_with?(".bundlecache") }.
            each { |f| expect(f.content_encoding).to eq("") }
        end
      end
    end
  end
end
