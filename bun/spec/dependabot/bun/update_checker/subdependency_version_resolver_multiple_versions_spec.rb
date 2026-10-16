# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/update_checker/subdependency_version_resolver"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe Dependabot::Bun::UpdateChecker::SubdependencyVersionResolver do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) { project_dependency_files("bun/multiple_brace_expansion_versions") }

  sig { returns(Dependabot::DependencyFile) }
  let(:lockfile) { T.must(dependency_files.find { |file| file.name == "bun.lock" }) }

  sig { returns(Dependabot::Bun::UpdateChecker::SubdependencyVersionResolver) }
  let(:resolver) do
    described_class.new(
      dependency: Dependabot::Dependency.new(
        name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "bun"
      ),
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: [],
      latest_allowable_version: "5.0.12",
      repo_contents_path: nil
    )
  end

  sig { returns(String) }
  let(:updated_content) { T.must(lockfile.content).gsub("brace-expansion@2.1.2", "brace-expansion@2.1.4") }

  before do
    allow(Dependabot::Bun::Helpers).to receive(:run_bun_command) do
      File.write("bun.lock", updated_content)
      ""
    end
  end

  it "reports the updated target instead of an unrelated lower version" do
    expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.4"))
  end

  context "when the targeted version is unchanged" do
    sig { returns(String) }
    let(:updated_content) { T.must(lockfile.content) }

    it "reports the unchanged targeted version" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.2"))
    end
  end

  context "when the targeted entry disappears" do
    sig { returns(String) }
    let(:updated_content) do
      content = JSON.parse(super())
      content.fetch("packages").delete("current-parent/brace-expansion")
      JSON.generate(content)
    end

    it "does not report an unrelated entry as the result" do
      allow(Dependabot.logger).to receive(:info)

      expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.2"))
      expect(Dependabot.logger).to have_received(:info).with(
        "Cannot verify updated Bun resolution for current-parent/brace-expansion; keeping current version"
      )
    end
  end
end
