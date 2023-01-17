# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/bundler/file_updater/ruby_requirement_setter"

RSpec.describe Dependabot::Bundler::FileUpdater::RubyRequirementSetter do
  let(:setter) { described_class.new(gemspec: gemspec) }
  let(:gemspec) do
    bundler_project_dependency_file("gemfile_small_example", filename: "example.gemspec")
  end

  describe "#rewrite" do
    subject(:rewrite) { setter.rewrite(content) }

    context "when the gemspec does not include a required_ruby_version" do
      let(:gemspec) do
        bundler_project_dependency_file("gemfile_no_required_ruby", filename: "example.gemspec")
      end

      context "without an existing ruby version" do
        let(:content) do
          bundler_project_dependency_file("gemfile", filename: "Gemfile").content
        end
        it { is_expected.to eq(content) }
      end

      context "with an existing ruby version" do
        let(:content) do
          bundler_project_dependency_file("explicit_ruby", filename: "Gemfile").content
        end
        it { is_expected.to eq(content) }
      end
    end

    context "when the gemspec includes a required_ruby_version" do
      let(:gemspec) do
        bundler_project_dependency_file("gemfile_old_required_ruby", filename: "example.gemspec")
      end

      context "with a required ruby version range" do
        let(:gemspec) do
          bundler_project_dependency_file("gemspec_required_ruby_version_range", filename: "example.gemspec")
        end
        let(:content) do
          bundler_project_dependency_file("gemspec_required_ruby_version_range", filename: "Gemfile").content
        end
        it { is_expected.to include("ruby '2.2.10'\n") }
        it { is_expected.to include(%(gem "statesman", "~> 1.2.0")) }
      end

      context "with a required ruby version range array" do
        let(:gemspec) do
          bundler_project_dependency_file("gemspec_required_ruby_version_range_array", filename: "example.gemspec")
        end
        let(:content) do
          bundler_project_dependency_file("gemspec_required_ruby_version_range_array", filename: "Gemfile").content
        end
        it { is_expected.to include("ruby '2.2.10'\n") }
        it { is_expected.to include(%(gem "statesman", "~> 1.2.0")) }
      end

      context "with a required ruby version requirement class" do
        let(:gemspec) do
          bundler_project_dependency_file("gemspec_required_ruby_version_requirement_class",
                                          filename: "example.gemspec")
        end
        let(:content) do
          bundler_project_dependency_file("gemspec_required_ruby_version_requirement_class",
                                          filename: "Gemfile").content
        end
        it { is_expected.to include("ruby '2.1.10'\n") }
        it { is_expected.to include(%(gem "statesman", "~> 1.2.0")) }
      end

      context "without an existing ruby version" do
        let(:content) do
          bundler_project_dependency_file("gemfile", filename: "Gemfile").content
        end
        it { is_expected.to include("ruby '1.9.3'\n") }
        it { is_expected.to include(%(gem "business", "~> 1.4.0")) }
      end

      context "that none of our Ruby versions satisfy" do
        let(:content) do
          bundler_project_dependency_file("gemfile", filename: "Gemfile").content
        end
        let(:gemspec) do
          bundler_project_dependency_file("gemfile_impossible_ruby", filename: "example.gemspec")
        end

        specify { expect { rewrite }.to raise_error(described_class::RubyVersionNotFound) }
      end

      context "when requiring ruby 3" do
        let(:gemspec) do
          bundler_project_dependency_file("gemfile_require_ruby_3", filename: "example.gemspec")
        end
        let(:content) do
          bundler_project_dependency_file("gemfile", filename: "Gemfile").content
        end
        it { is_expected.to include("ruby '3.0.1'\n") }
        it { is_expected.to include(%(gem "business", "~> 1.4.0")) }
      end

      context "when requiring ruby 3.1" do
        let(:gemspec) do
          bundler_project_dependency_file("gemfile_require_ruby_3_1", filename: "example.gemspec")
        end
        let(:content) do
          bundler_project_dependency_file("gemfile", filename: "Gemfile").content
        end
        it { is_expected.to include("ruby '3.1.1'\n") }
        it { is_expected.to include(%(gem "business", "~> 1.4.0")) }
      end

      context "when requiring ruby 3.2" do
        let(:gemspec) do
          bundler_project_dependency_file("gemfile_require_ruby_3_2", filename: "example.gemspec")
        end
        let(:content) do
          bundler_project_dependency_file("gemfile", filename: "Gemfile").content
        end
        it { is_expected.to include("ruby '3.2.0'\n") }
        it { is_expected.to include(%(gem "business", "~> 1.4.0")) }
      end

      context "that can't be evaluated" do
        let(:content) do
          bundler_project_dependency_file("gemfile", filename: "Gemfile").content
        end
        let(:gemspec) do
          bundler_project_dependency_file("gemfile_unevaluatable_ruby", filename: "example.gemspec")
        end

        it { is_expected.to_not include("ruby '") }
      end

      context "with an existing ruby version" do
        context "at top level" do
          let(:content) do
            bundler_project_dependency_file("explicit_ruby", filename: "Gemfile").content
          end

          it { is_expected.to include("ruby '1.9.3'\n") }
          it { is_expected.to_not include(%(ruby "2.2.0")) }
          it { is_expected.to include(%(gem "business", "~> 1.4.0")) }
        end

        context "within a source block" do
          let(:content) do
            "source 'https://example.com' do\n" \
              "  ruby \"2.2.0\"\n" \
              "end"
          end
          it { is_expected.to include("ruby '1.9.3'\n") }
          it { is_expected.to_not include(%(ruby "2.2.0")) }
        end

        context "loaded from a file" do
          let(:content) do
            bundler_project_dependency_file("ruby_version_file", filename: "Gemfile").content
          end

          it { is_expected.to include("ruby '1.9.3'\n") }
          it { is_expected.to_not include("ruby File.open") }
        end
      end
    end
  end
end
