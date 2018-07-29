# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/go/dep"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Go::Dep do
  it_behaves_like "a dependency file parser"

  let(:parser) { described_class.new(dependency_files: files, source: source) }

  let(:files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Gopkg.toml",
      content: fixture("go", "gopkg_tomls", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Gopkg.lock",
      content: fixture("go", "gopkg_locks", lockfile_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "cockroach.toml" }
  let(:lockfile_fixture_name) { "cockroach.lock" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(149) }

    describe "top level dependencies" do
      subject(:dependencies) { parser.parse.select(&:top_level?) }

      its(:length) { is_expected.to eq(11) }

      describe "a regular version dependency" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "github.com/satori/go.uuid" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("github.com/satori/go.uuid")
          expect(dependency.version).to eq("1.2.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "v1.2.0",
              file: "Gopkg.toml",
              groups: [],
              source: {
                type: "default",
                source: "github.com/satori/go.uuid"
              }
            }]
          )
        end

        context "that doesn't declare a version" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "github.com/dgrijalva/jwt-go" }
          end
          let(:manifest_fixture_name) { "no_version.toml" }
          let(:lockfile_fixture_name) { "no_version.lock" }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("github.com/dgrijalva/jwt-go")
            expect(dependency.version).to eq("1.0.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "Gopkg.toml",
                groups: [],
                source: {
                  type: "default",
                  source: "github.com/dgrijalva/jwt-go"
                }
              }]
            )
          end
        end
      end

      context "with a dependency that isn't in the lockfile" do
        let(:manifest_fixture_name) { "unused_constraint.toml" }
        let(:lockfile_fixture_name) { "unused_constraint.lock" }

        its(:length) { is_expected.to eq(1) }

        it "has the right details" do
          expect(dependencies.map(&:name)).
            to eq(["github.com/dgrijalva/jwt-go"])
        end
      end

      describe "a git version dependency" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "golang.org/x/text" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("golang.org/x/text")
          expect(dependency.version).
            to eq("470f45bf29f4147d6fbd7dfd0a02a848e49f5bf4")
          expect(dependency.requirements).to eq(
            [{
              requirement: nil,
              file: "Gopkg.toml",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/golang/text",
                branch: nil,
                ref: "470f45bf29f4147d6fbd7dfd0a02a848e49f5bf4"
              }
            }]
          )
        end

        context "that specifies a tag as its revision" do
          let(:manifest_fixture_name) { "tag_as_revision.toml" }
          let(:lockfile_fixture_name) { "tag_as_revision.lock" }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("golang.org/x/text")
            expect(dependency.version).to eq("v0.2.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "Gopkg.toml",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/golang/text",
                  branch: nil,
                  ref: "v0.2.0"
                }
              }]
            )
          end
        end

        context "that specifies a tag as its version" do
          let(:manifest_fixture_name) { "tag_as_version.toml" }
          let(:lockfile_fixture_name) { "tag_as_version.lock" }
          subject(:dependency) do
            dependencies.find { |d| d.name == "github.com/globalsign/mgo" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("github.com/globalsign/mgo")
            expect(dependency.version).to eq("r2018.04.23")
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "Gopkg.toml",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/globalsign/mgo",
                  branch: nil,
                  ref: "r2018.04.23"
                }
              }]
            )
          end
        end
      end

      describe "a dependency with an unrecognised name" do
        let(:manifest_fixture_name) { "unknown_source.toml" }
        let(:lockfile_fixture_name) { "unknown_source.lock" }
        subject(:dependency) do
          dependencies.find { |d| d.name == "unknownhost.com/dgrijalva/jwt-go" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("unknownhost.com/dgrijalva/jwt-go")
          expect(dependency.version).to eq("3.2.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "^3.2.0",
              file: "Gopkg.toml",
              groups: [],
              source: {
                type: "default",
                source: "unknownhost.com/dgrijalva/jwt-go"
              }
            }]
          )
        end
      end
    end
  end
end
