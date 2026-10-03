# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/file_parser"
require "dependabot/maven/file_updater"
require "dependabot/maven/update_checker"
require "dependabot/security_advisory"

RSpec.describe Dependabot::Maven::UpdateChecker do
  let(:dependency_files) do
    [Dependabot::DependencyFile.new(name: "pom.xml", content: fixture("poms", "writable_versions.xml"))]
  end
  let(:dependency) do
    Dependabot::Maven::FileParser.new(dependency_files: dependency_files, source: nil)
                                 .parse.find { |dep| dep.name == "com.example:#{artifact}" }
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      security_advisories: security_advisories
    )
  end
  let(:resolved_version) { transitive_dependencies ? "1.0" : nil }
  let(:security_advisories) do
    if security_update
      [Dependabot::SecurityAdvisory.new(
        dependency_name: "com.example:#{artifact}",
        package_manager: "maven",
        vulnerable_versions: ["< 2.0"]
      )]
    else
      []
    end
  end

  before do
    Dependabot::Experiments.register(:maven_transitive_dependencies, transitive_dependencies)
    tree = fixture("dependency_trees", "writable_versions.json")
    allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin) do |output_file|
      File.write(output_file, tree)
    end
    stub_request(:get, %r{\Ahttps://repo\.maven\.apache\.org/maven2/com/example/[^/]+/maven-metadata\.xml\z})
      .to_return(body: "<metadata><versioning><versions><version>1.0</version><version>2.0</version>" \
                       "<version>3.0</version></versions></versioning></metadata>")
    stub_request(:head, %r{\Ahttps://repo\.maven\.apache\.org/maven2/com/example/})
      .to_return(status: 200)
    stub_request(:get, "https://repo.maven.apache.org/maven2/com/example/parent/1.0/parent-1.0.pom")
      .to_return(body: "<project><modelVersion>4.0.0</modelVersion><groupId>com.example</groupId>" \
                       "<artifactId>parent</artifactId><version>1.0</version></project>")
  end

  shared_examples "an unwritable update" do
    it "retains the resolved version but proposes no update" do
      expect(dependency.version).to eq(resolved_version)
      expect(checker.vulnerable?).to eq(security_update && !resolved_version.nil?)
      expect(checker.latest_version.to_s).to eq("3.0")
      expect(checker.latest_resolvable_version).to be_nil
      expect(checker.preferred_resolvable_version).to be_nil
      expect(checker.updated_requirements).to eq(dependency.requirements)

      %i(none own all).each do |unlock|
        expect(checker.can_update?(requirements_to_unlock: unlock)).to be(false)
        expect(checker.updated_dependencies(requirements_to_unlock: unlock)).to be_empty
      end

      if security_update && resolved_version
        expect(checker.lowest_security_fix_version.to_s).to eq("2.0")
        expect(checker.lowest_resolvable_security_fix_version).to be_nil
        expect(dependency.version).to eq("1.0")
      end
    end
  end

  shared_examples "a writable update" do |xpath, property_reference = nil|
    it "writes the version proposed by the checker" do
      expected_version = security_update ? "2.0" : "3.0"
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      updates = checker.updated_dependencies(requirements_to_unlock: :own)
      expect(updates.map(&:version)).to eq([expected_version])

      files = Dependabot::Maven::FileUpdater.new(
        dependencies: updates,
        dependency_files: dependency_files,
        credentials: []
      ).updated_dependency_files

      expect(files.map(&:name)).to eq(["pom.xml"])
      expect(files.first.content).not_to eq(dependency_files.first.content)
      doc = Nokogiri::XML(files.first.content).tap(&:remove_namespaces!)
      expect(doc.at_xpath(xpath).content).to eq(expected_version)
      expect(files.first.content).to include(property_reference) if property_reference
    end
  end

  [false, true].each do |experiment_enabled|
    context "with the transitive experiment #{experiment_enabled ? 'on' : 'off'}" do
      let(:transitive_dependencies) { experiment_enabled }

      [false, true].each do |security|
        context "with #{security ? 'security' : 'version'} updates" do
          let(:security_update) { security }

          context "with a parent-managed requirement" do
            let(:artifact) { "parent-managed" }

            it_behaves_like "an unwritable update"
          end

          context "with a BOM-managed requirement" do
            let(:artifact) { "bom-managed" }

            it_behaves_like "an unwritable update"
          end

          context "with a range requirement" do
            let(:artifact) { "range" }

            it_behaves_like "an unwritable update"
          end

          context "with a reference to the project parent version" do
            let(:artifact) { "parent-reference" }
            let(:resolved_version) { "1.0" }

            it_behaves_like "an unwritable update"
          end

          context "with the parent dependency itself" do
            let(:artifact) { "parent" }

            it_behaves_like "a writable update", "/project/parent/version"
          end

          context "with an explicit version" do
            let(:artifact) { "explicit" }

            it_behaves_like "a writable update",
                            "//dependency[artifactId='explicit']/version"
          end

          context "with a local property" do
            let(:artifact) { "property" }

            it_behaves_like "a writable update",
                            "/project/properties/library.version",
                            "${library.version}"
          end

          context "with both a managed declaration and a local version" do
            let(:artifact) { "locally-managed" }

            it_behaves_like "a writable update",
                            "//dependencyManagement/dependencies/dependency[artifactId='locally-managed']/version"
          end

          context "with a shared property" do
            let(:artifact) { "shared-one" }

            it "updates all dependencies sharing the property through full unlock" do
              expect(checker.can_update?(requirements_to_unlock: :all)).to be(true)
              updates = checker.updated_dependencies(requirements_to_unlock: :all)
              expect(updates.map(&:name)).to contain_exactly("com.example:shared-one", "com.example:shared-two")
              expect(updates.map(&:version)).to eq(["3.0", "3.0"])

              files = Dependabot::Maven::FileUpdater.new(
                dependencies: updates,
                dependency_files: dependency_files,
                credentials: []
              ).updated_dependency_files

              expect(files.map(&:name)).to eq(["pom.xml"])
              expect(files.first.content).to include("<shared.version>3.0</shared.version>")
              expect(files.first.content.scan("${shared.version}").length).to eq(2)
            end
          end
        end
      end
    end
  end
end
