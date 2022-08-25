# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/bundler/file_updater/requirement_replacer"

RSpec.describe Dependabot::Bundler::FileUpdater::RequirementReplacer do
  let(:replacer) do
    described_class.new(
      dependency: dependency,
      file_type: file_type,
      updated_requirement: updated_requirement,
      previous_requirement: previous_requirement
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.5.0",
      previous_version: "1.2.0",
      requirements: requirement,
      package_manager: "bundler"
    )
  end
  let(:requirement) do
    [{
      source: nil,
      file: "Gemfile",
      requirement: updated_requirement,
      groups: []
    }]
  end
  let(:updated_requirement) { "~> 1.5.0" }
  let(:previous_requirement) { "~> 1.2.0" }

  let(:dependency_name) { "business" }
  let(:file_type) { :gemfile }

  describe "#rewrite" do
    subject(:rewrite) { replacer.rewrite(content) }

    context "with a Gemfile" do
      let(:file_type) { :gemfile }

      context "when the declaration spans multiple lines" do
        let(:content) do
          bundler_project_dependency_file("git_source", filename: "Gemfile").content
        end
        it { is_expected.to include(%(gem "business", "~> 1.5.0",\n    git: )) }
        it { is_expected.to include(%(gem "statesman", "~> 1.2.0")) }
      end

      context "when the declaration uses a symbol" do
        let(:content) { %(gem "business", :"~> 1.0", require: true) }
        it { is_expected.to include(%(gem "business", :"~> 1.5.0", require:)) }
      end

      context "when the declaration changes from one to many requirements" do
        let(:dependency_name) { "devise" }
        let(:updated_requirement) { ">=3.2, <5.0" }
        let(:content) { %(gem "devise", "~>3.2") }

        it "should include spaces between enumerated requirements" do
          is_expected.to include(%(gem "devise", ">=3.2", "<5.0"))
        end
      end

      context "within a source block" do
        let(:content) do
          "source 'https://example.com' do\n" \
          "  gem \"business\", \"~> 1.0\", require: true\n" \
          "end"
        end
        it { is_expected.to include(%(gem "business", "~> 1.5.0", require:)) }
      end

      context "with multiple requirements" do
        let(:content) { %(gem "business", "~> 1.0", ">= 1.0.1") }
        it { is_expected.to eq(%(gem "business", "~> 1.5.0")) }

        context "given as an array" do
          let(:content) { %(gem "business", [">= 1", "<3"], require: true) }
          it { is_expected.to eq(%(gem "business", "~> 1.5.0", require: true)) }
        end

        context "for the new requirement" do
          let(:updated_requirement) { ">= 1.0, < 3.0" }
          it { is_expected.to eq(%(gem "business", ">= 1.0", "< 3.0")) }
        end
      end

      context "with a length change and a comment" do
        let(:previous_requirement) { "~> 1.9" }
        let(:content) { "gem \"business\", \"~> 1.9\"    # description\n" }

        context "when length has increased" do
          let(:updated_requirement) { "~> 1.10" }

          it "handles the change in required spaces" do
            expect(rewrite).
              to eq("gem \"business\", \"~> 1.10\"   # description\n")
          end
        end

        context "when length has decreased" do
          let(:updated_requirement) { "~> 2" }

          it "handles the change in required spaces" do
            expect(rewrite).
              to eq("gem \"business\", \"~> 2\"      # description\n")
          end

          context "but there was only one space to start with" do
            let(:content) { "gem \"business\", \"~> 1.9\" # description\n" }

            it "doesn't update the spaces" do
              expect(rewrite).
                to eq("gem \"business\", \"~> 2\" # description\n")
            end
          end
        end

        context "with an equality matcher" do
          let(:updated_requirement) { "2.0" }
          let(:previous_requirement) { "= 1.9" }
          let(:content) { "gem \"business\", \"1.9\"    # description\n" }

          context "when no change is required" do
            it "handles the change in required spaces" do
              expect(rewrite).
                to eq("gem \"business\", \"2.0\"    # description\n")
            end
          end

          context "when a change is required" do
            let(:updated_requirement) { "2.0.0" }
            it "handles the change in required spaces" do
              expect(rewrite).
                to eq("gem \"business\", \"2.0.0\"  # description\n")
            end
          end
        end
      end

      context "with a function requirement" do
        let(:content) { %(version = "1.0.0"\ngem "business", version) }
        it { is_expected.to eq(content) }

        context "in an || condition" do
          let(:content) do
            %(version = "1.0.0"\ngem "business", ENV["a"] || version)
          end
          it { is_expected.to eq(content) }
        end
      end

      context "with no requirement" do
        let(:content) { %(gem "business") }
        it { is_expected.to eq(content) }

        context "when asked to insert if required" do
          let(:replacer) do
            described_class.new(
              dependency: dependency,
              file_type: file_type,
              updated_requirement: updated_requirement,
              previous_requirement: previous_requirement,
              insert_if_bare: true
            )
          end

          it { is_expected.to eq(%(gem "business", "~> 1.5.0")) }
        end
      end

      context "with a ternary requirement" do
        let(:content) { %(gem "business", (true ? "1.0.0" : "1.2.0")) }
        it { is_expected.to eq(content) }

        context "that uses an expression" do
          let(:content) do
            %(gem "business", RUBY_VERSION >= "2.2" ? "1.0.0" : "1.2.0")
          end
          it { is_expected.to eq(content) }
        end
      end

      context "with a case statement" do
        let(:content) { %(gem "business",  case true\n when true\n "1.0.0"\n else\n "1.2.0"\n end) }
        it { is_expected.to eq(content) }
      end

      context "with a conditional" do
        let(:content) { %(gem "business", ENV["ROUGE"] if ENV["ROUGE"]) }
        it { is_expected.to eq(content) }
      end

      context "with a constant" do
        let(:content) { %(gem "business", MyModule::VERSION) }
        it { is_expected.to eq(content) }
      end

      context "with a dependency that uses single quotes" do
        let(:content) { %(gem "business", '~> 1.0') }
        it { is_expected.to eq(%(gem "business", '~> 1.5.0')) }
      end

      context "with a dependency that uses quote brackets" do
        let(:content) { %(gem "business", %(1.0)) }
        it { is_expected.to eq(%(gem "business", %(~> 1.5.0))) }
      end

      context "with a dependency that uses doesn't have a space" do
        let(:content) { %(gem "business", "~>1.0") }
        it { is_expected.to eq(%(gem "business", "~>1.5.0")) }
      end
    end

    context "with a gemspec" do
      let(:file_type) { :gemspec }
      let(:content) do
        bundler_project_dependency_file("gemfile_example", filename: "example.gemspec").content
      end

      context "when declared with `add_runtime_dependency`" do
        let(:dependency_name) { "bundler" }
        it { is_expected.to include(%(time_dependency "bundler", "~> 1.5.0")) }
      end

      context "when declared with `add_dependency`" do
        let(:dependency_name) { "excon" }
        it { is_expected.to include(%(add_dependency "excon", "~> 1.5.0")) }
      end

      context "when declared without a version" do
        let(:dependency_name) { "rake" }
        it { is_expected.to include(%(ent_dependency "rake"\n)) }
      end

      context "when declared with an array expansion" do
        let(:content) do
          %(s.add_runtime_dependency("business", *rouge_versions))
        end
        it { is_expected.to eq(content) }
      end

      context "with an exact requirement" do
        let(:content) do
          bundler_project_dependency_file("gemfile_exact", filename: "example.gemspec").content
        end

        context "when declared with `=` operator" do
          let(:dependency_name) { "statesman" }
          let(:updated_requirement) { "= 1.5.0" }
          let(:previous_requirement) { "= 1.0.0" }
          it { is_expected.to include(%(d_dependency 'statesman', '= 1.5.0')) }
        end

        context "when declared with no operator" do
          let(:dependency_name) { "business" }
          let(:updated_requirement) { "= 1.5.0" }
          let(:previous_requirement) { "= 1.0.0" }
          it { is_expected.to include(%(d_dependency 'business', '1.5.0')) }
        end
      end

      context "with inequality matchers" do
        let(:previous_requirement) { ">= 2.0.0, != 2.0.3, != 2.0.4" }
        let(:updated_requirement) { "~> 2.0.1, != 2.0.3, != 2.0.4" }
        let(:content) do
          %(s.add_runtime_dependency("business", "~> 2.0.1", "!= 2.0.3", "!= 2.0.4"))
        end

        it { is_expected.to eq(content) }
      end

      context "when declared with `add_development_dependency`" do
        let(:dependency_name) { "rspec" }
        it { is_expected.to include(%(ent_dependency "rspec", "~> 1.5.0"\n)) }
      end
    end
  end
end
