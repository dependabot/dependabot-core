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
      dependencies: dependencies,
      credentials: []
    )
  end

  let(:dependencies) { [dependency] }

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

    [
      [
        "an indented assignment with tabs and a comment",
        "[tools]\n  erlang\t=\t\"27.3.2\" # current version\n",
        "[tools]\n  erlang\t=\t\"28.0.0\" # current version\n"
      ],
      [
        "a single-quoted version",
        "[tools]\nerlang = '27.3.2'\n",
        "[tools]\nerlang = '28.0.0'\n"
      ],
      [
        "a single-quoted tool key",
        "[tools]\n\t'erlang'  = '27.3.2'\n",
        "[tools]\n\t'erlang'  = '28.0.0'\n"
      ],
      [
        "a double-quoted tool key without spaces around the equals sign",
        "[tools]\n\"erlang\"=\"27.3.2\"\n",
        "[tools]\n\"erlang\"=\"28.0.0\"\n"
      ],
      [
        "an indented inline table with the version after another option",
        "[tools]\n\terlang={ install_env = { TEST = 'value' }, version\t=\t\"27.3.2\" } # current version\n",
        "[tools]\n\terlang={ install_env = { TEST = 'value' }, version\t=\t\"28.0.0\" } # current version\n"
      ],
      [
        "an inline table with single-quoted strings",
        "[tools]\n  'erlang' = { version='27.3.2', install_env = { TEST = 'value' } }\n",
        "[tools]\n  'erlang' = { version='28.0.0', install_env = { TEST = 'value' } }\n"
      ],
      [
        "a table with an indented single-quoted version after another option",
        "[tools.erlang]\ninstall_env = { TEST = 'value' }\n\tversion\t=\t'27.3.2' # current version\n",
        "[tools.erlang]\ninstall_env = { TEST = 'value' }\n\tversion\t=\t'28.0.0' # current version\n"
      ],
      [
        "a table with an indented double-quoted version",
        "[tools.erlang]\n  version=\"27.3.2\"\n",
        "[tools.erlang]\n  version=\"28.0.0\"\n"
      ],
      [
        "a table with an array before the version",
        "[tools.erlang]\nos = [\"linux\"]\nversion = '27.3.2'\n",
        "[tools.erlang]\nos = [\"linux\"]\nversion = '28.0.0'\n"
      ],
      [
        "a table with a multiline array before the version",
        "[tools.erlang]\nos = [\n  'linux',\n  'macos',\n]\nversion = \"27.3.2\"\n",
        "[tools.erlang]\nos = [\n  'linux',\n  'macos',\n]\nversion = \"28.0.0\"\n"
      ]
    ].each do |description, original_content, expected_content|
      context "with #{description}" do
        let(:mise_toml) do
          Dependabot::DependencyFile.new(name: "mise.toml", content: original_content)
        end

        it "updates the version and preserves formatting" do
          expect(updated_files.map(&:content)).to eq([expected_content])
        end
      end
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

    context "with a backend tool in a quoted table header" do
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

      [["double", '"'], ["single", "'"]].each do |style, quote|
        context "with #{style} quotes" do
          let(:mise_toml) do
            Dependabot::DependencyFile.new(
              name: "mise.toml",
              content: "[tools.#{quote}npm:@redocly/cli#{quote}]\n  version = #{quote}2.19.1#{quote}\n"
            )
          end

          it "updates the version and preserves the quotes" do
            expect(updated_files.map(&:content))
              .to eq(["[tools.#{quote}npm:@redocly/cli#{quote}]\n  version = #{quote}2.20.0#{quote}\n"])
          end
        end
      end
    end

    context "when a changed requirement cannot be rewritten" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: "[tools]\nerlang = ['27.3.2', '26.0']\n"
        )
      end

      it "raises an error identifying the dependency and file" do
        expect { updated_files }
          .to raise_error(RuntimeError, "Expected content to change for erlang in mise.toml!") do |error|
            expect(Dependabot::ErrorReportContext.build(error: error)).to include(
              "dependency-name" => "erlang",
              "dependency-file" => "mise.toml"
            )
          end
      end

      context "when another dependency updates successfully" do
        let(:dependencies) { [node_dependency, dependency] }
        let(:mise_toml) do
          Dependabot::DependencyFile.new(
            name: "mise.toml",
            content: "[tools]\nnode = '20.0.0'\nerlang = ['27.3.2', '26.0']\n"
          )
        end
        let(:node_dependency) do
          Dependabot::Dependency.new(
            name: "node",
            version: "22.0.0",
            previous_version: "20.0.0",
            package_manager: "mise",
            requirements: [{ requirement: "22.0.0", file: "mise.toml", groups: [], source: nil }],
            previous_requirements: [{ requirement: "20.0.0", file: "mise.toml", groups: [], source: nil }]
          )
        end

        it "raises instead of returning a partially updated manifest" do
          expect { updated_files }
            .to raise_error(RuntimeError, "Expected content to change for erlang in mise.toml!")
        end
      end
    end

    context "when the requested version is unchanged" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "erlang",
          version: "27.3.2",
          previous_version: "27.3.2",
          package_manager: "mise",
          requirements: [{ requirement: "27.3.2", file: "mise.toml", groups: [], source: nil }],
          previous_requirements: [{ requirement: "27.3.2", file: "mise.toml", groups: [], source: nil }]
        )
      end

      it "returns no changed files" do
        expect(updated_files).to be_empty
      end

      context "with a version declaration the updater does not support" do
        let(:mise_toml) do
          Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools]\nerlang = ['27.3.2', '26.0']\n")
        end

        it "does not require a rewrite" do
          expect(updated_files).to be_empty
        end
      end
    end

    context "with another table after the tool's table" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: "[tools.erlang]\nos = ['linux']\n  [tools.node]\nversion = '27.3.2'\n"
        )
      end

      it "does not replace the version in the next table" do
        expect { updated_files }
          .to raise_error(RuntimeError, "Expected content to change for erlang in mise.toml!")
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

    context "with dependency in multiple files" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: <<~TOML
            [tools]
            erlang = "27.3.2"
            node = "20.0.0"
          TOML
        )
      end

      let(:mise_production_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.production.toml",
          content: <<~TOML
            [tools]
            erlang = "28.0.0"
            python = "3.11.0"
          TOML
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "erlang",
          version: "28.5.0",
          previous_version: "28.0.0",
          package_manager: "mise",
          requirements: [
            { requirement: "28.5.0", file: "mise.toml", groups: [], source: nil },
            { requirement: "28.5.0", file: "mise.production.toml", groups: [], source: nil }
          ],
          previous_requirements: [
            { requirement: "27.3.2", file: "mise.toml", groups: [], source: nil },
            { requirement: "28.0.0", file: "mise.production.toml", groups: [], source: nil }
          ]
        )
      end

      let(:updater) do
        described_class.new(
          dependency_files: [mise_toml, mise_production_toml],
          dependencies: [dependency],
          credentials: []
        )
      end

      it "updates both files" do
        expect(updated_files.length).to eq(2)
      end

      it "updates erlang in mise.toml from 27.3.2 to 28.5.0" do
        mise_file = updated_files.find { |f| f.name == "mise.toml" }
        expect(mise_file.content).to include('erlang = "28.5.0"')
        expect(mise_file.content).not_to include('erlang = "27.3.2"')
      end

      it "updates erlang in mise.production.toml from 28.0.0 to 28.5.0" do
        production_file = updated_files.find { |f| f.name == "mise.production.toml" }
        expect(production_file.content).to include('erlang = "28.5.0"')
        expect(production_file.content).not_to include('erlang = "28.0.0"')
      end

      it "does not modify other tools in mise.toml" do
        mise_file = updated_files.find { |f| f.name == "mise.toml" }
        expect(mise_file.content).to include('node = "20.0.0"')
      end

      it "does not modify other tools in mise.production.toml" do
        production_file = updated_files.find { |f| f.name == "mise.production.toml" }
        expect(production_file.content).to include('python = "3.11.0"')
      end

      context "when a later file cannot be rewritten" do
        let(:mise_production_toml) do
          Dependabot::DependencyFile.new(
            name: "mise.production.toml",
            content: "[tools]\nerlang = ['28.0.0', '27.3.2']\n"
          )
        end

        it "raises instead of returning only the first updated file" do
          expect { updated_files }
            .to raise_error(RuntimeError, "Expected content to change for erlang in mise.production.toml!")
        end
      end

      context "when one file already has the target version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "erlang",
            version: "28.0.0",
            previous_version: "27.3.2",
            package_manager: "mise",
            requirements: [
              { requirement: "28.0.0", file: "mise.toml", groups: [], source: nil },
              { requirement: "28.0.0", file: "mise.production.toml", groups: [], source: nil }
            ],
            previous_requirements: [
              { requirement: "27.3.2", file: "mise.toml", groups: [], source: nil },
              { requirement: "28.0.0", file: "mise.production.toml", groups: [], source: nil }
            ]
          )
        end

        it "only returns the file with a changed requirement" do
          expect(updated_files.map(&:name)).to eq(["mise.toml"])
        end

        context "when the first file cannot be rewritten" do
          let(:mise_toml) do
            Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools]\nerlang = ['27.3.2', '26.0']\n")
          end

          it "does not mistake the unchanged requirement in the second file for a successful update" do
            expect { updated_files }
              .to raise_error(RuntimeError, "Expected content to change for erlang in mise.toml!")
          end
        end
      end
    end

    context "with dependency only in one of multiple files" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: <<~TOML
            [tools]
            erlang = "27.3.2"
            node = "20.0.0"
          TOML
        )
      end

      let(:mise_production_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.production.toml",
          content: <<~TOML
            [tools]
            python = "3.11.0"
          TOML
        )
      end

      let(:node_dependency) do
        Dependabot::Dependency.new(
          name: "node",
          version: "22.0.0",
          previous_version: "20.0.0",
          package_manager: "mise",
          requirements: [
            { requirement: "22.0.0", file: "mise.toml", groups: [], source: nil }
          ],
          previous_requirements: [
            { requirement: "20.0.0", file: "mise.toml", groups: [], source: nil }
          ]
        )
      end

      let(:updater) do
        described_class.new(
          dependency_files: [mise_toml, mise_production_toml],
          dependencies: [node_dependency],
          credentials: []
        )
      end

      it "only updates the file containing the dependency" do
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.name).to eq("mise.toml")
      end

      it "updates node in mise.toml" do
        expect(updated_files.first.content).to include('node = "22.0.0"')
      end

      it "does not update mise.production.toml" do
        expect(updated_files.map(&:name)).not_to include("mise.production.toml")
      end
    end
  end
end
