# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/mise"

RSpec.describe Dependabot::Mise::FileUpdater do
  describe "updating aliases parsed by the mise CLI" do
    [
      ["golang", "1.18", "1.22.0"],
      ["nodejs", "20.0.0", "22.0.0"],
      ["core:node", "20.0.0", "22.0.0"],
      ["core:golang", "1.18", "1.22.0"],
      ["core:python", "3.12.0", "3.13.0"],
      ["op", "2.30.0", "2.31.0"],
      ["aqua:hashicorp/terraform", "1.11.0", "1.12.0"]
    ].each do |original_name, old_version, new_version|
      context "with #{original_name}" do
        let(:manifest) do
          Dependabot::DependencyFile.new(
            name: "mise.toml",
            content: "[env]\n'#{original_name}' = '#{old_version}'\n" \
                     "[tools.'#{original_name}']\nversion = '#{old_version}'\n"
          )
        end
        let(:dependency) do
          Dependabot::Mise::FileParser.new(dependency_files: [manifest], source: nil).parse.fetch(0)
        end
        let(:checker) do
          Dependabot::Mise::UpdateChecker.new(dependency: dependency, dependency_files: [manifest], credentials: [])
        end

        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .with(
              ["mise", "ls-remote", "--json", "--", original_name],
              stderr_to_stdout: false,
              env: { "MISE_YES" => "1" }
            )
            .and_return(JSON.dump([{ "version" => new_version }]))
        end

        it "uses the original manifest key as the dependency name" do
          expect(dependency.name).to eq(original_name)
        end

        it "rewrites only the aliased tool's version" do
          updater = described_class.new(
            dependency_files: [manifest],
            dependencies: checker.updated_dependencies(requirements_to_unlock: :own),
            credentials: []
          )

          expect(updater.updated_dependency_files.map(&:content))
            .to eq(
              ["[env]\n'#{original_name}' = '#{old_version}'\n" \
               "[tools.'#{original_name}']\nversion = '#{new_version}'\n"]
            )
        end
      end
    end

    context "when different files use different names for the same tool" do
      let(:manifests) do
        [
          Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools.golang]\nversion = '1.18'\n"),
          Dependabot::DependencyFile.new(name: ".mise.dev.toml", content: "[tools]\ngo = '1.19'\n")
        ]
      end
      let(:dependencies) do
        Dependabot::Mise::FileParser.new(dependency_files: manifests, source: nil).parse
      end
      let(:checkers) do
        dependencies.map do |dependency|
          Dependabot::Mise::UpdateChecker.new(dependency: dependency, dependency_files: manifests, credentials: [])
        end
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        %w(golang go).each do |name|
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .with(
              ["mise", "ls-remote", "--json", "--", name],
              stderr_to_stdout: false,
              env: { "MISE_YES" => "1" }
            )
            .and_return(JSON.dump([{ "version" => "1.22.0" }]))
        end
      end

      it "keeps differently named aliases as separate dependencies" do
        expect(
          dependencies.map do |dep|
            [dep.name, dep.version, dep.requirements.map(&:file)]
          end
        ).to eq([["golang", "1.18", ["mise.toml"]], ["go", "1.19", [".mise.dev.toml"]]])
      end

      it "uses the correct name when updating each manifest" do
        updater = described_class.new(
          dependency_files: manifests,
          dependencies: checkers.flat_map { |checker| checker.updated_dependencies(requirements_to_unlock: :own) },
          credentials: []
        )

        expect(updater.updated_dependency_files.to_h { |file| [file.name, file.content] }).to eq(
          "mise.toml" => "[tools.golang]\nversion = '1.22.0'\n",
          ".mise.dev.toml" => "[tools]\ngo = '1.22.0'\n"
        )
      end

      it "updates one alias independently of the other" do
        updater = described_class.new(
          dependency_files: manifests,
          dependencies: checkers.first.updated_dependencies(requirements_to_unlock: :own),
          credentials: []
        )

        expect(updater.updated_dependency_files.to_h { |file| [file.name, file.content] }).to eq(
          "mise.toml" => "[tools.golang]\nversion = '1.22.0'\n"
        )
      end
    end
  end
end
