# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_fetcher/child_gemfile_finder"

RSpec.describe Dependabot::Bundler::FileFetcher::ChildGemfileFinder do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Bundler::FileFetcher::ChildGemfileFinder) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:finder) { described_class.new(gemfile: gemfile) }

  sig { returns(Dependabot::DependencyFile) }
  let(:gemfile) { bundler_project_dependency_file("gemfile", filename: "Gemfile") }
  # rubocop:enable RSpec/ScatteredLet

  describe "#child_gemfile_paths" do
    sig { returns(T::Array[String]) }
    subject(:child_gemfile_paths) { finder.child_gemfile_paths }

    context "when the file does not include any child Gemfiles" do
      sig { returns(Dependabot::DependencyFile) }
      let(:gemfile) { bundler_project_dependency_file("gemfile", filename: "Gemfile") }

      it { is_expected.to eq([]) }
    end

    context "when the file does include a child Gemfile" do
      sig { returns(Dependabot::DependencyFile) }
      let(:gemfile) { bundler_project_dependency_file("eval_gemfile_gemfile", filename: "Gemfile") }

      it { is_expected.to eq(["backend/Gemfile"]) }

      context "when path must be eval-ed" do
        sig { returns(Dependabot::DependencyFile) }
        let(:gemfile) { bundler_project_dependency_file("eval_gemfile_absolute", filename: "Gemfile") }

        it "raises a helpful error" do
          expect { finder.child_gemfile_paths }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotParseable)
            expect(error.file_name).to eq("Gemfile")
          end
        end
      end

      context "when that includes a variable" do
        sig { returns(Dependabot::DependencyFile) }
        let(:gemfile) { bundler_project_dependency_file("eval_gemfile_variable", filename: "Gemfile") }

        it "raises a helpful error" do
          expect { finder.child_gemfile_paths }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotParseable)
            expect(error.file_name).to eq("Gemfile")
          end
        end
      end

      context "when within a group block" do
        # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
        sig { returns(String) }
        let(:gemfile_body) do
          "group :development do\neval_gemfile('some_gemfile')\nend"
        end

        sig { returns(Dependabot::DependencyFile) }
        let(:gemfile) do
          Dependabot::DependencyFile.new(content: gemfile_body, name: "Gemfile")
        end

        # rubocop:enable RSpec/ScatteredLet

        it { is_expected.to eq(["some_gemfile"]) }
      end

      context "with invalid Ruby in the Gemfile" do
        sig { returns(Dependabot::DependencyFile) }
        let(:gemfile) { bundler_project_dependency_file("invalid_ruby", filename: "Gemfile") }

        it "raises a helpful error" do
          suppress_output do
            expect { finder.child_gemfile_paths }.to raise_error do |error|
              expect(error).to be_a(Dependabot::DependencyFileNotParseable)
              expect(error.file_name).to eq("Gemfile")
            end
          end
        end
      end

      context "when this Gemfile is already in a nested directory" do
        sig { returns(Dependabot::DependencyFile) }
        let(:gemfile) { bundler_project_dependency_file("eval_gemfile_nested", filename: "nested/Gemfile") }

        it { is_expected.to eq(["nested/backend/Gemfile"]) }
      end
    end
  end
end
