# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/file_parser/helper_dependencies"
require "dependabot/bundler/native_helpers"

RSpec.describe Dependabot::Bundler::NativeHelpers do
  subject(:native_helper) { described_class }

  describe ".run_bundler_subprocess" do
    let(:options) { {} }

    let(:native_helpers_path) { "/opt" }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)

      with_env("DEPENDABOT_NATIVE_HELPERS_PATH", native_helpers_path) do
        native_helper.run_bundler_subprocess(
          function: "noop",
          args: {},
          bundler_version: "2",
          options: options
        )
      end
    end

    context "with a timeout provided" do
      let(:options) { { timeout_per_operation_seconds: 120 } }

      it "terminates the spawned process when the timeout is exceeded" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "timeout -s HUP 120 ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: {},
            env: anything
          )
      end
    end

    context "with a timeout that is too high" do
      let(:thirty_minutes_plus_one_second) { 1801 }
      let(:options) do
        {
          timeout_per_operation_seconds: thirty_minutes_plus_one_second
        }
      end

      it "applies the maximum timeout" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "timeout -s HUP 1800 ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: {},
            env: anything
          )
      end
    end

    context "with a timeout that is too low" do
      let(:fifty_nine_seconds) { 59 }
      let(:options) do
        {
          timeout_per_operation_seconds: fifty_nine_seconds
        }
      end

      it "applies the minimum timeout" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "timeout -s HUP 60 ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: {},
            env: anything
          )
      end
    end

    context "without a timeout" do
      let(:options) { {} }

      it "does not apply a timeout" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: {},
            env: anything
          )
      end
    end

    context "with DEPENDABOT_NATIVE_HELPERS_PATH not set" do
      let(:native_helpers_path) { nil }

      it "uses the full path to the uninstalled run.rb command" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "ruby #{File.expand_path('../../../helpers/v2/run.rb', __dir__)}",
            function: "noop",
            args: {},
            env: anything
          )
      end
    end

    context "with a regular (non-security) update" do
      let(:options) { {} }

      it "keeps Bundler's native source cooldown enabled" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: anything,
            function: "noop",
            args: {},
            env: hash_excluding("BUNDLE_COOLDOWN")
          )
      end
    end

    context "with a security update" do
      let(:options) { { security_updates_only: true } }

      it "disables Bundler's native source cooldown so remediation is not blocked" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: anything,
            function: "noop",
            args: {},
            env: hash_including("BUNDLE_COOLDOWN" => "0")
          )
      end
    end

    private

    def with_env(key, value)
      previous_value = ENV.fetch(key, nil)
      ENV[key] = value
      yield
    ensure
      ENV[key] = previous_value
    end
  end

  describe ".run_bundler_subprocess parser protocol" do
    %w(2 4).each do |bundler_version|
      context "with Bundler #{bundler_version}" do
        it "activates the selected helper's Bundler major version" do
          version = native_helper.run_bundler_subprocess(
            function: "bundler_raw_version",
            args: {},
            bundler_version: bundler_version
          )

          expect(version).to start_with("#{bundler_version}.")
        end

        context "when parsing a Gemfile" do
          subject(:parsed_gemfile) do
            Dependabot::SharedHelpers.in_a_temporary_repo_directory do |directory|
              File.write(gemfile.name, gemfile.content)
              native_helper.run_bundler_subprocess(
                function: "parsed_gemfile",
                args: { dir: directory.to_s, gemfile_name: gemfile.name, lockfile_name: "Gemfile.lock" },
                bundler_version: bundler_version
              )
            end
          end

          let(:gemfile) do
            Dependabot::DependencyFile.new(
              name: "Gemfile",
              content: <<~GEMFILE
                source "https://rubygems.org"

                gem "default_gem", "~> 1.0"
                group :development, :test do
                  gem "git_gem", git: "https://git.example.test/git_gem.git"
                end
                source "https://gems.example.test" do
                  gem "private_gem", ">= 2.0"
                end
              GEMFILE
            )
          end

          let(:expected_dependencies) do
            [
              {
                "name" => "default_gem",
                "requirement" => "~> 1.0",
                "groups" => ["default"],
                "source" => nil,
                "type" => "runtime"
              },
              {
                "name" => "git_gem",
                "requirement" => ">= 0",
                "groups" => %w(development test),
                "source" => {
                  "type" => "git",
                  "url" => "https://git.example.test/git_gem.git",
                  "branch" => nil,
                  "ref" => nil
                },
                "type" => "runtime"
              },
              {
                "name" => "private_gem",
                "requirement" => ">= 2.0",
                "groups" => ["default"],
                "source" => {
                  "type" => "rubygems",
                  "url" => "https://gems.example.test/"
                },
                "type" => "runtime"
              }
            ]
          end

          it "preserves JSON value types, explicit nil Git keys, and omitted registry keys" do
            expect(parsed_gemfile).to eq(expected_dependencies)
          end

          it "decodes the real response into typed Gemfile dependencies" do
            dependencies = Dependabot::Bundler::FileParser::HelperDependencies.from_gemfile_result(
              parsed_gemfile,
              file: gemfile
            )

            expected = expected_dependencies.map do |dependency|
              be_a(Dependabot::Bundler::FileParser::HelperDependencies::GemfileDependency).and(
                have_attributes(
                  name: dependency.fetch("name"),
                  requirement: dependency.fetch("requirement"),
                  groups: dependency.fetch("groups"),
                  source: dependency.fetch("source")&.transform_keys(&:to_sym)
                )
              )
            end
            expect(dependencies).to match(expected)
          end
        end

        context "when parsing a gemspec" do
          subject(:parsed_gemspec) do
            Dependabot::SharedHelpers.in_a_temporary_repo_directory do |directory|
              File.write(gemspec.name, gemspec.content)
              native_helper.run_bundler_subprocess(
                function: "parsed_gemspec",
                args: { dir: directory.to_s, gemspec_name: gemspec.name, lockfile_name: "Gemfile.lock" },
                bundler_version: bundler_version
              )
            end
          end

          let(:gemspec) do
            Dependabot::DependencyFile.new(
              name: "example.gemspec",
              content: <<~GEMSPEC
                Gem::Specification.new do |spec|
                  spec.name = "example"
                  spec.version = "1.0.0"
                  spec.summary = "Parser protocol fixture"
                  spec.authors = ["Dependabot"]
                  spec.add_dependency "runtime_gem", "~> 1.0"
                  spec.add_development_dependency "development_gem", ">= 2.0"
                end
              GEMSPEC
            )
          end

          let(:expected_dependencies) do
            [
              {
                "name" => "runtime_gem",
                "requirement" => "~> 1.0",
                "groups" => nil,
                "source" => nil,
                "type" => "runtime"
              },
              {
                "name" => "development_gem",
                "requirement" => ">= 2.0",
                "groups" => nil,
                "source" => nil,
                "type" => "development"
              }
            ]
          end

          it "serializes requirement and dependency type strings with nil groups and sources" do
            expect(parsed_gemspec).to eq(expected_dependencies)
          end

          it "decodes the real response into typed gemspec dependencies" do
            dependencies = Dependabot::Bundler::FileParser::HelperDependencies.from_gemspec_result(
              parsed_gemspec,
              file: gemspec
            )

            expected = expected_dependencies.map do |dependency|
              be_a(Dependabot::Bundler::FileParser::HelperDependencies::GemspecDependency).and(
                have_attributes(
                  name: dependency.fetch("name"),
                  requirement: dependency.fetch("requirement"),
                  type: dependency.fetch("type"),
                  source: dependency.fetch("source")&.transform_keys(&:to_sym)
                )
              )
            end
            expect(dependencies).to match(expected)
          end
        end
      end
    end
  end
end
