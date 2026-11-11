# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clojure/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Clojure::FileParser do
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "example/repo", directory: "/") }
  let(:files) { project_dependency_files(project_name) }
  let(:project_name) { "lein" }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    def requirements_of(name)
      dependencies.find { |dep| dep.name == name }.requirements.map(&:to_h)
    end

    context "with a project.clj" do
      it "reads every literal version, skipping ignored forms, unquoted values and meta-versions" do
        expect(dependencies.map { |dep| [dep.name, dep.version] }).to contain_exactly(
          ["org.clojure:clojure", "1.11.1"],
          ["ring:ring-core", "1.9.6"],
          ["cheshire:cheshire", "5.11.0"],
          ["org.lwjgl:lwjgl", "3.3.1"],
          ["lein-ancient:lein-ancient", "1.0.0-RC3"],
          ["ring:ring-mock", "0.4.0"],
          ["org.clojure:test.check", "1.1.1"]
        )
      end

      it "records where each declaration comes from" do
        expect(requirements_of("ring:ring-core")).to contain_exactly(
          { requirement: "1.9.6", file: "project.clj", groups: ["dependencies"], source: nil, metadata: nil },
          { requirement: "1.9.6", file: "project.clj", groups: ["profile:dev"], source: nil, metadata: nil }
        )
        expect(requirements_of("lein-ancient:lein-ancient").first[:groups]).to eq(["plugins"])
        expect(requirements_of("org.clojure:test.check").first[:groups]).to eq(["profile:test"])
      end

      it "keeps the classifier" do
        expect(requirements_of("org.lwjgl:lwjgl").first[:metadata]).to eq(classifier: "natives-linux")
      end

      it "marks only top-level dependencies as production" do
        production = dependencies.select(&:production?).map(&:name)
        expect(production).to contain_exactly(
          "org.clojure:clojure", "ring:ring-core", "cheshire:cheshire", "org.lwjgl:lwjgl"
        )
      end
    end

    context "with a deps.edn" do
      let(:project_name) { "deps" }

      it "reads :deps and alias dependencies, skipping git and local ones" do
        expect(dependencies.map { |dep| [dep.name, dep.version] }).to contain_exactly(
          ["org.clojure:clojure", "1.11.1"],
          ["cheshire:cheshire", "5.11.0"],
          ["lambdaisland:kaocha", "1.87.1366"],
          ["nrepl:nrepl", "1.0.0"]
        )
        expect(requirements_of("nrepl:nrepl").first[:groups]).to eq(["alias:dev/repl"])
      end
    end

    context "with a project.clj and a deps.edn" do
      let(:project_name) { "lein_and_deps" }

      it "combines the declarations of both files" do
        expect(requirements_of("cheshire:cheshire").map { |req| req[:file] }).to contain_exactly(
          "project.clj", "deps.edn"
        )
      end
    end

    context "with a profile that pins another version" do
      let(:files) do
        [Dependabot::DependencyFile.new(name: "project.clj", content: <<~CLJ)]
          (defproject example/app "0.1.0"
            :dependencies [[org.clojure/clojure "1.11.1"]]
            :profiles {:1.9 {:dependencies [[org.clojure/clojure "1.9.0"]]}
                       :dev {:dependencies [[org.clojure/clojure "1.11.1"]]}})
        CLJ
      end

      it "tracks the top-level version and leaves the pin alone" do
        expect(dependencies.map(&:version)).to eq(["1.11.1"])
        expect(requirements_of("org.clojure:clojure").map { |req| req[:groups] }).to eq(
          [["dependencies"], ["profile:dev"]]
        )
      end
    end

    context "with two top-level declarations of different versions" do
      let(:files) do
        [Dependabot::DependencyFile.new(name: "project.clj", content: <<~CLJ)]
          (defproject example/app "0.1.0"
            :dependencies [[cheshire "5.11.0"]]
            :managed-dependencies [[cheshire "5.12.0"]])
        CLJ
      end

      it "keeps both" do
        expect(requirements_of("cheshire:cheshire").map { |req| req[:requirement] }).to contain_exactly(
          "5.11.0", "5.12.0"
        )
      end
    end

    context "with a malformed file" do
      let(:project_name) { "broken" }

      it "raises a parse error" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end

  describe "#ecosystem" do
    subject(:ecosystem) { parser.ecosystem }

    it "reports Leiningen and the Clojure version" do
      expect(ecosystem.name).to eq("clojure")
      expect(ecosystem.package_manager.name).to eq("lein")
      expect(ecosystem.language.version.to_s).to eq("1.11.1")
    end

    context "with a deps.edn" do
      let(:project_name) { "deps" }

      it "reports the Clojure CLI" do
        expect(ecosystem.package_manager.name).to eq("deps")
      end
    end
  end
end
