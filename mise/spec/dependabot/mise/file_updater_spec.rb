# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/mise/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Mise::FileUpdater do
  let(:mise_toml) do
    Dependabot::DependencyFile.new(
      name: "mise.toml",
      content: <<~TOML
        [tools]
        erlang = "27.3.2"
      TOML
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "erlang",
      version: "28.0.0",
      previous_version: "27.3.2",
      package_manager: "mise",
      requirements: [{
        requirement: "28.0.0",
        file: "mise.toml",
        groups: [],
        source: nil
      }],
      previous_requirements: [{
        requirement: "27.3.2",
        file: "mise.toml",
        groups: [],
        source: nil
      }]
    )
  end

  let(:updater) do
    described_class.new(
      dependency_files: [mise_toml],
      dependencies: [dependency],
      credentials: []
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns one updated file" do
      expect(updated_files.length).to eq(1)
    end

    it "updates the version in mise.toml" do
      expect(updated_files.first.content).to include('erlang = "28.0.0"')
    end

    it "does not include the old version" do
      expect(updated_files.first.content).not_to include('erlang = "27.3.2"')
    end

    context "with quoted key (npm scoped package)" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: <<~TOML
            [tools]
            "npm:@redocly/cli" = "2.19.1"
          TOML
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "npm:@redocly/cli",
          version: "2.20.0",
          previous_version: "2.19.1",
          package_manager: "mise",
          requirements: [{ requirement: "2.20.0", file: "mise.toml", groups: [], source: nil }],
          previous_requirements: [{ requirement: "2.19.1", file: "mise.toml", groups: [], source: nil }]
        )
      end

      it "updates the version in a quoted key entry" do
        expect(updated_files.first.content).to include('"npm:@redocly/cli" = "2.20.0"')
      end
    end

    context "with inline table format" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: <<~TOML
            [tools]
            ruby = { version = "3.3.0", virtualenv = ".venv" }
          TOML
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ruby",
          version: "3.4.0",
          previous_version: "3.3.0",
          package_manager: "mise",
          requirements: [{ requirement: "3.4.0", file: "mise.toml", groups: [], source: nil }],
          previous_requirements: [{ requirement: "3.3.0", file: "mise.toml", groups: [], source: nil }]
        )
      end

      it "updates the version inside the inline table" do
        expect(updated_files.first.content)
          .to include('ruby = { version = "3.4.0", virtualenv = ".venv" }')
      end
    end

    context "with table header format" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: <<~TOML
            [tools.golang]
            version = "1.18"
          TOML
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "golang",
          version: "1.22.0",
          previous_version: "1.18",
          package_manager: "mise",
          requirements: [{ requirement: "1.22.0", file: "mise.toml", groups: [], source: nil }],
          previous_requirements: [{ requirement: "1.18", file: "mise.toml", groups: [], source: nil }]
        )
      end

      it "updates the version in a table header entry" do
        expect(updated_files.first.content).to include("[tools.golang]\nversion = \"1.22.0\"")
      end
    end

    context "with a fuzzy version pin" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: <<~TOML
            [tools]
            node = "20"
          TOML
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "node",
          version: "22",
          previous_version: "20",
          package_manager: "mise",
          requirements: [{ requirement: "22", file: "mise.toml", groups: [], source: nil }],
          previous_requirements: [{ requirement: "20", file: "mise.toml", groups: [], source: nil }]
        )
      end

      it "updates the fuzzy version pin" do
        expect(updated_files.first.content).to include('node = "22"')
      end
    end

    context "with inline table format where version is not first" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: <<~TOML
            [tools]
            python = { virtualenv = ".venv", version = "3.11.0" }
          TOML
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "python",
          version: "3.12.0",
          previous_version: "3.11.0",
          package_manager: "mise",
          requirements: [{ requirement: "3.12.0", file: "mise.toml", groups: [], source: nil }],
          previous_requirements: [{ requirement: "3.11.0", file: "mise.toml", groups: [], source: nil }]
        )
      end

      it "updates the version inside the inline table" do
        expect(updated_files.first.content)
          .to include('python = { virtualenv = ".venv", version = "3.12.0" }')
      end
    end

    context "with table header format where version is not first" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: <<~TOML
            [tools.golang]
            env = "production"
            version = "1.18"
          TOML
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "golang",
          version: "1.22.0",
          previous_version: "1.18",
          package_manager: "mise",
          requirements: [{ requirement: "1.22.0", file: "mise.toml", groups: [], source: nil }],
          previous_requirements: [{ requirement: "1.18", file: "mise.toml", groups: [], source: nil }]
        )
      end

      it "updates the version in the table header entry" do
        expect(updated_files.first.content).to include("[tools.golang]\nenv = \"production\"\nversion = \"1.22.0\"")
      end
    end
  end
end
