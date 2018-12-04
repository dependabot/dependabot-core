# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/go/modules/go_mod_parser"

RSpec.describe Dependabot::FileParsers::Go::Modules::GoModParser do
  let(:parser) do
    described_class.new(dependency_files: files, credentials: credentials)
  end

  let(:files) { [go_mod] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:go_mod) do
    Dependabot::DependencyFile.new(
      name: "go.mod",
      content: go_mod_content
    )
  end
  let(:go_mod_content) { fixture("go", "go_mods", go_mod_fixture_name) }
  let(:go_mod_fixture_name) { "go.mod" }

  describe "dependency_set" do
    subject(:dependencies) { parser.dependency_set.dependencies }

    its(:length) { is_expected.to eq(5) }

    describe "top level dependencies" do
      subject(:dependencies) do
        parser.dependency_set.dependencies.select(&:top_level?)
      end

      its(:length) { is_expected.to eq(2) }

      describe "a dependency that uses go modules" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "rsc.io/quote" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("rsc.io/quote")
          expect(dependency.version).to eq("1.4.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "v1.4.0",
              file: "go.mod",
              groups: [],
              source: {
                type: "default",
                source: "rsc.io/quote"
              }
            }]
          )
        end
      end

      describe "a dependency that doesn't use go modules" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "github.com/fatih/Color" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("github.com/fatih/Color")
          expect(dependency.version).to eq("1.7.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "v1.7.0",
              file: "go.mod",
              groups: [],
              source: {
                type: "default",
                source: "github.com/fatih/Color"
              }
            }]
          )
        end
      end

      context "with git dependencies" do
        let(:go_mod_fixture_name) { "git_dependency.mod" }

        describe "a git revision dependency" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "golang.org/x/crypto" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("golang.org/x/crypto")
            expect(dependency.version).
              to eq("0.0.0-20180617042118-027cca12c2d6")
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "go.mod",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/golang/crypto",
                  ref: "027cca12c2d6",
                  branch: nil
                }
              }]
            )
          end
        end
      end
    end

    describe "a garbage go.mod" do
      let(:go_mod_content) { "not really a go.mod file :-/" }

      it "raises the correct error" do
        expect { parser.dependency_set }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_path).to eq("/go.mod")
          end
      end
    end

    describe "a non-existent dependency" do
      let(:go_mod_content) do
        go_mod = fixture("go", "go_mods", go_mod_fixture_name)
        go_mod.sub("rsc.io/quote", "example.com/not-a-repo")
      end

      it "raises the correct error" do
        expect { parser.dependency_set }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    describe "a dependency at a non-existent version" do
      let(:go_mod_content) do
        go_mod = fixture("go", "go_mods", go_mod_fixture_name)
        go_mod.sub("rsc.io/quote v1.4.0", "rsc.io/quote v1.321.0")
      end

      it "raises the correct error" do
        expect { parser.dependency_set }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    describe "a v2+ dependency without the major version in the path" do
      let(:go_mod_content) do
        go_mod = fixture("go", "go_mods", go_mod_fixture_name)
        go_mod.sub("rsc.io/quote v1.4.0", "rsc.io/quote v2.0.0")
      end

      it "raises the correct error" do
        expect { parser.dependency_set }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_path).to eq("/go.mod")
            expect(error.message).to match(/v0 or v1/)
          end
      end
    end
  end
end
