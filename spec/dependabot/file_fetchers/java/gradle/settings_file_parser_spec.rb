# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_fetchers/java/gradle/settings_file_parser"

RSpec.describe Dependabot::FileFetchers::Java::Gradle::SettingsFileParser do
  let(:finder) { described_class.new(settings_file: settings_file) }

  let(:settings_file) do
    Dependabot::DependencyFile.new(
      name: "settings.gradle",
      content: fixture("java", "gradle_settings_files", fixture_name)
    )
  end
  let(:fixture_name) { "simple_settings.gradle" }

  describe "#subproject_paths" do
    subject(:subproject_paths) { finder.subproject_paths }

    context "when there are subproject declarations" do
      let(:buildfile_fixture_name) { "simple_settings.gradle" }

      it "includes the additional declarations" do
        expect(subproject_paths).to match_array(%w(app))
      end
    end
  end
end
