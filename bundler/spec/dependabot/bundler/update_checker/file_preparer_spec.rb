# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/bundler/update_checker/file_preparer"

RSpec.describe Dependabot::Bundler::UpdateChecker::FilePreparer do
  let(:preparer) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency,
      remove_git_source: remove_git_source,
      unlock_requirement: unlock_requirement,
      replacement_git_pin: replacement_git_pin,
      latest_allowable_version: latest_allowable_version
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end

  let(:version) { "df9f605d7111b6814fe493cf8f41de3f9f0978b2" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
  end
  let(:dependency_name) { "business" }
  let(:remove_git_source) { false }
  let(:unlock_requirement) { true }
  let(:replacement_git_pin) { nil }
  let(:latest_allowable_version) { nil }

  let(:dependency_files) { bundler_project_dependency_files("gemfile") }

  describe "#prepared_dependency_files" do
    subject(:prepared_dependency_files) { preparer.prepared_dependency_files }

    describe "the updated Gemfile" do
      subject { prepared_dependency_files.find { |f| f.name == "Gemfile" } }

      context "with a ~> matcher" do
        let(:version) { "1.4.3" }

        its(:content) { is_expected.to include(%("business", ">= 1.4.3"\n)) }
        its(:content) { is_expected.to include(%("statesman", "~> 1.2.0"\n)) }

        context "with a latest allowable version" do
          let(:latest_allowable_version) { "5.0.0" }

          its(:content) do
            is_expected.to include(%("business", ">= 1.4.3", "<= 5.0.0"\n))
          end

          context "that is a git SHA" do
            let(:latest_allowable_version) { "d12ca5e" }
            its(:content) do
              is_expected.to include(%("business", ">= 1.4.3"\n))
            end
          end
        end

        context "with a gems.rb and gems.locked setup" do
          let(:dependency_files) { bundler_project_dependency_files("gems_rb") }
          subject { prepared_dependency_files.find { |f| f.name == "gems.rb" } }

          it "returns the right files" do
            expect(prepared_dependency_files.map(&:name)).
              to match_array(%w(gems.rb gems.locked))
          end

          its(:content) { is_expected.to include(%("business", ">= 1.4.3"\n)) }
          its(:content) { is_expected.to include(%("statesman", "~> 1.2.0"\n)) }
        end

        context "when asked not to unlock the requirement" do
          let(:unlock_requirement) { false }
          its(:content) { is_expected.to include(%("business", "~> 1.4.0"\n)) }

          context "with a latest allowable version" do
            let(:latest_allowable_version) { "5.0.0" }

            its(:content) do
              is_expected.to include(%("business", "~> 1.4.0", "<= 5.0.0"\n))
            end
          end
        end
      end

      context "within a source block" do
        let(:dependency_files) { bundler_project_dependency_files("source_block_gemfile") }
        let(:version) { "1.4.3" }

        its(:content) { is_expected.to include(%("business", ">= 1.4.3")) }
      end

      context "with multiple requirements" do
        let(:dependency_files) { bundler_project_dependency_files("gemfile_multiple_requirements") }
        let(:version) { "1.4.3" }
        its(:content) do
          is_expected.to eq(%(gem "business", ">= 1.4.3", require: true\n))
        end

        context "given as an array" do
          let(:dependency_files) { bundler_project_dependency_files("gemfile_multiple_requirements_array") }
          its(:content) do
            is_expected.to eq(%(gem "business", ">= 1.4.3", require: true\n))
          end
        end
      end

      context "with a git source" do
        let(:dependency_files) { bundler_project_dependency_files("git_source_gemfile") }
        let(:version) { "df9f605d7111b6814fe493cf8f41de3f9f0978b2" }
        let(:dependency_name) { "prius" }

        its(:content) { is_expected.to include(%("prius", ">= 0", git:)) }

        context "and a version specified" do
          let(:dependency_files) { bundler_project_dependency_files("git_source_with_version_gemfile") }
          let(:dependency_name) { "dependabot-test-ruby-package" }

          its(:content) do
            is_expected.to include(
              %("dependabot-test-ruby-package", ">= 0", git:)
            )
          end
        end

        context "that should be removed" do
          let(:remove_git_source) { true }
          its(:content) { is_expected.to include(%("prius", ">= 0"\n)) }
          its(:content) { is_expected.to include(%("que", git:)) }

          context "with a tag (i.e., multiple git-related arguments)" do
            let(:dependency_files) { bundler_project_dependency_files("git_source_gemfile") }
            let(:dependency_name) { "que" }
            its(:content) { is_expected.to include(%("que", ">= 0"\n)) }
          end

          context "with non-git tags at the start" do
            let(:dependency_files) { bundler_project_dependency_files("non_git_tags_at_start_gemfile") }
            its(:content) do
              is_expected.to eq(%(gem "prius", ">= 0", require: false\n))
            end
          end

          context "with non-git tags at the end" do
            let(:dependency_files) { bundler_project_dependency_files("non_git_tags_at_end_gemfile") }
            its(:content) do
              is_expected.to eq(%(gem "prius", ">= 0", require: false\n))
            end
          end

          context "with non-git tags on a subsequent line" do
            let(:dependency_files) { bundler_project_dependency_files("non_git_tags_on_newline_gemfile") }
            its(:content) do
              is_expected.to eq(%(gem "prius", ">= 0", require: false\n))
            end
          end

          context "with git tags on a subsequent line" do
            let(:dependency_files) { bundler_project_dependency_files("git_tags_on_newline_gemfile") }
            its(:content) do
              is_expected.to eq(%(gem "prius", ">= 0", require: false\n))
            end
          end

          context "with a custom tag" do
            let(:dependency_files) { bundler_project_dependency_files("custom_tag_gemfile") }
            its(:content) { is_expected.to eq(%(gem "prius", ">= 0"\n)) }
          end

          context "with a comment" do
            let(:dependency_files) { bundler_project_dependency_files("comment_gemfile") }
            its(:content) { is_expected.to eq(%(gem "prius", ">= 0" # My gem\n)) }
          end
        end

        context "that should have its tag replaced" do
          let(:dependency_name) { "business" }
          let(:replacement_git_pin) { "v5.1.0" }
          its(:content) { is_expected.to include(%(ref: "v5.1.0"\n)) }
        end
      end

      context "with a function call" do
        let(:dependency_files) { bundler_project_dependency_files("function_version_gemfile") }
        let(:version) { "1.4.3" }

        its(:content) { is_expected.to include(%("business", version)) }
      end

      context "with a required ruby version in the gemspec" do
        let(:dependency_files) { bundler_project_dependency_files("gemfile_old_required_ruby") }
        let(:version) { "1.4.3" }

        its(:content) { is_expected.to include("ruby '1.9.3'") }

        context "when asked not to lock the Ruby version" do
          let(:preparer) do
            described_class.new(
              dependency_files: dependency_files,
              dependency: dependency,
              remove_git_source: remove_git_source,
              unlock_requirement: unlock_requirement,
              replacement_git_pin: replacement_git_pin,
              latest_allowable_version: latest_allowable_version,
              lock_ruby_version: false
            )
          end

          its(:content) { is_expected.to_not include("ruby '1.9.3'") }
        end
      end
    end

    describe "the updated gemspec" do
      let(:dependency_files) { bundler_project_dependency_files("gemfile_small_example") }
      let(:version) { "1.4.3" }

      subject do
        prepared_dependency_files.find { |f| f.name == "example.gemspec" }
      end

      its(:content) { is_expected.to include("'business', '>= 1.4.3'\n") }

      context "when the file requires sanitizing" do
        let(:dependency_files) { bundler_project_dependency_files("gemfile_with_require") }
        let(:dependency_name) { "gitlab" }

        its(:content) { is_expected.to include(%("gitlab", ">= 1.4.3"\n)) }
        its(:content) { is_expected.to include("begin\nrequire ") }
        its(:content) { is_expected.to include(%(version      = "0.0.1")) }

        context "without a version" do
          let(:version) { nil }

          context "with no requirements, either" do
            let(:requirements) { [] }
            its(:content) { is_expected.to include(%("gitlab", ">= 0"\n)) }
          end

          context "with a requirement" do
            let(:requirements) do
              [{
                requirement: "~> 1.4",
                file: "Gemfile",
                source: nil,
                groups: [:default]
              }]
            end
            its(:content) { is_expected.to include(%("gitlab", ">= 1.4"\n)) }
          end
        end
      end

      context "with multiple requirements" do
        let(:version) { "1.4.3" }
        let(:gemspec_fixture_name) { "multiple_requirements" }
        let(:dependency_files) { bundler_project_dependency_files("gemspec_multiple_requirements") }
        its(:content) do
          is_expected.to eq(%(spec.add_dependency "business", ">= 1.4.3"\n))
        end

        context "given as an array" do
          let(:dependency_files) { bundler_project_dependency_files("gemspec_multiple_requirements_array") }
          let(:gemspec_fixture_name) { "multiple_requirements_array" }
          its(:content) do
            is_expected.to eq(%(spec.add_dependency "business", ">= 1.4.3"\n))
          end
        end
      end

      context "with parentheses" do
        let(:version) { "1.4.3" }
        let(:dependency_files) { bundler_project_dependency_files("gemfile_multiple_requirements_parenthesis") }
        its(:content) do
          is_expected.to eq(%(spec.add_dependency("business", ">= 1.4.3")\n))
        end
      end
    end

    describe "the updated path gemspec" do
      let(:dependency_files) do
        bundler_project_dependency_files("nested_gemspec")
      end
      subject { prepared_dependency_files.find { |f| f.name == "some/example.gemspec" } }
      let(:version) { "1.4.3" }

      its(:content) { is_expected.to include(%("business", ">= 1.4.3")) }

      context "when the file requires sanitizing" do
        subject { prepared_dependency_files.find { |f| f.name == "example.gemspec" } }
        let(:dependency_files) { bundler_project_dependency_files("gemfile_with_require") }

        its(:content) { is_expected.to include("begin\nrequire ") }
        its(:content) { is_expected.to include(%(version      = "0.0.1")) }
      end
    end

    describe "the updated child gemfile" do
      let(:dependency_files) { bundler_project_dependency_files("nested_gemfile") }
      let(:version) { "1.4.3" }

      subject do
        prepared_dependency_files.find { |f| f.name == "backend/Gemfile" }
      end

      its(:content) { is_expected.to include(%("business", ">= 1.4.3")) }
      its(:content) { is_expected.to include(%("statesman", "~> 1.2.0")) }
    end
  end
end
