# typed: false
# frozen_string_literal: true

require "spec_helper"
require "json"
require "dependabot/dependency_file"
require "dependabot/dependency_requirement"
require "dependabot/source"
require "dependabot/maven/file_parser/maven_dependency_parser"

RSpec.describe Dependabot::Maven::FileParser::MavenDependencyParser do
  describe "build_dependency_set" do
    let(:dependency_set) { described_class.build_dependency_set(dependency_files) }
    let(:dependency_files) do
      [Dependabot::DependencyFile.new(name: "pom.xml", content: "<project><dependencies></dependencies></project>")]
    end

    it "returns a DependencySet" do
      allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin)
        .and_return(nil)

      expect(dependency_set).to be_a(Dependabot::FileParsers::Base::DependencySet)
    end

    context "with a single empty pom.xml file" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "pom.xml", content: "<project><dependencies></dependencies></project>")]
      end

      it "returns an empty DependencySet" do
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin)
          .and_return(nil)

        expect(dependency_set.dependencies).to be_empty
      end
    end

    context "with a pom.xml file containing a dependency" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "pom.xml", content: <<~XML)]
          <project>
            <modelVersion>4.0.0</modelVersion>

            <groupId>com.dependabot</groupId>
            <artifactId>test-project</artifactId>
            <version>1.0-SNAPSHOT</version>

            <dependencies>
              <dependency>
                <groupId>com.example</groupId>
                <artifactId>example-artifact</artifactId>
                <version>1.0.0</version>
              </dependency>
            </dependencies>
          </project>
        XML
      end

      it "parses the dependencies correctly" do
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin)
          .and_wrap_original do |_original_method, *_args, &_block|
          File.write(
            "dependency-tree-output.json",
            {
              groupId: "com.dependabot",
              artifactId: "test-project",
              version: "1.0-SNAPSHOT",
              type: "jar",
              scope: "",
              classifier: "",
              optional: "false",
              children: [
                {
                  groupId: "com.example",
                  artifactId: "example-artifact",
                  version: "1.0.0",
                  type: "jar",
                  scope: "compile",
                  classifier: "",
                  optional: "false"
                }
              ]
            }.to_json
          )
        end

        expect(dependency_set.dependencies.size).to eq(1)
        expect(dependency_set.dependencies[0].name).to eq("com.example:example-artifact")
        expect(dependency_set.dependencies[0].version).to eq("1.0.0")
      end
    end

    context "with a pom.xml file containing multiple dependencies" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "pom.xml", content: <<~XML)]
          <project>
            <modelVersion>4.0.0</modelVersion>

            <groupId>com.dependabot</groupId>
            <artifactId>test-project</artifactId>
            <version>1.0-SNAPSHOT</version>

            <dependencies>
              <dependency>
                <groupId>com.example</groupId>
                <artifactId>example-artifact</artifactId>
                <version>1.0.0</version>
              </dependency>
              <dependency>
                <groupId>com.example</groupId>
                <artifactId>example-second-artifact</artifactId>
                <version>1.0.1</version>
              </dependency>
            </dependencies>
          </project>
        XML
      end

      it "parses the dependencies correctly" do
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin)
          .and_wrap_original do |_original_method, *_args, &_block|
          File.write(
            "dependency-tree-output.json",
            {
              groupId: "com.dependabot",
              artifactId: "test-project",
              version: "1.0-SNAPSHOT",
              type: "jar",
              scope: "",
              classifier: "",
              optional: "false",
              children: [
                {
                  groupId: "com.example",
                  artifactId: "example-artifact",
                  version: "1.0.0",
                  type: "jar",
                  scope: "compile",
                  classifier: "",
                  optional: "false"
                },
                {
                  groupId: "com.example",
                  artifactId: "example-second-artifact",
                  version: "1.0.1",
                  type: "jar",
                  scope: "compile",
                  classifier: "",
                  optional: "false"
                }
              ]
            }.to_json
          )
        end

        expect(dependency_set.dependencies.size).to eq(2)
        expect(dependency_set.dependencies[0].name).to eq("com.example:example-artifact")
        expect(dependency_set.dependencies[0].version).to eq("1.0.0")
        expect(dependency_set.dependencies[1].name).to eq("com.example:example-second-artifact")
        expect(dependency_set.dependencies[1].version).to eq("1.0.1")
      end
    end

    context "with a pom.xml file containing multiple dependencies with a transitive dependency" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "pom.xml", content: <<~XML)]
          <project>
            <modelVersion>4.0.0</modelVersion>

            <groupId>com.dependabot</groupId>
            <artifactId>test-project</artifactId>
            <version>1.0-SNAPSHOT</version>

            <dependencies>
              <dependency>
                <groupId>com.example</groupId>
                <artifactId>example-artifact</artifactId>
                <version>1.0.0</version>
              </dependency>
              <dependency>
                <groupId>com.example</groupId>
                <artifactId>example-second-artifact</artifactId>
                <version>1.0.1</version>
              </dependency>
            </dependencies>
          </project>
        XML
      end

      it "parses the dependencies correctly" do
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin)
          .and_wrap_original do |_original_method, *_args, &_block|
          File.write(
            "dependency-tree-output.json",
            {
              groupId: "com.dependabot",
              artifactId: "test-project",
              version: "1.0-SNAPSHOT",
              type: "jar",
              scope: "",
              classifier: "",
              optional: "false",
              children: [
                {
                  groupId: "com.example",
                  artifactId: "example-artifact",
                  version: "1.0.0",
                  type: "jar",
                  scope: "compile",
                  classifier: "",
                  optional: "false",
                  children: [
                    {
                      groupId: "com.example",
                      artifactId: "example-transitive-artifact",
                      version: "1.0.2",
                      type: "jar",
                      scope: "compile",
                      classifier: "",
                      optional: "false"
                    }
                  ]
                },
                {
                  groupId: "com.example",
                  artifactId: "example-second-artifact",
                  version: "1.0.1",
                  type: "jar",
                  scope: "compile",
                  classifier: "",
                  optional: "false"
                }
              ]
            }.to_json
          )
        end

        expect(dependency_set.dependencies.size).to eq(3)
        expect(dependency_set.dependencies[0].name).to eq("com.example:example-artifact")
        expect(dependency_set.dependencies[0].version).to eq("1.0.0")
        expect(dependency_set.dependencies[1].name).to eq("com.example:example-transitive-artifact")
        expect(dependency_set.dependencies[1].version).to eq("1.0.2")
        expect(dependency_set.dependencies[2].name).to eq("com.example:example-second-artifact")
        expect(dependency_set.dependencies[2].version).to eq("1.0.1")
        expect(dependency_set.dependencies[1].requirements).to eq(
          [{
            requirement: "1.0.2",
            file: nil,
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              scope: "compile",
              pom_file: "pom.xml",
              pulled_in_by: "com.example:example-artifact"
            }
          }]
        )
        expect(dependency_set.dependencies[0].requirements.first[:metadata]).not_to have_key(:pulled_in_by)
      end
    end

    context "with a pom.xml file containing single dependency with a tree of transitive dependencies" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "pom.xml", content: <<~XML)]
          <project>
            <modelVersion>4.0.0</modelVersion>

            <groupId>com.dependabot</groupId>
            <artifactId>test-project</artifactId>
            <version>1.0-SNAPSHOT</version>

            <dependencies>
              <dependency>
                <groupId>com.example</groupId>
                <artifactId>example-artifact</artifactId>
                <version>1.0.0</version>
              </dependency>
            </dependencies>
          </project>
        XML
      end

      it "parses the dependencies correctly" do
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin)
          .and_wrap_original do |_original_method, *_args, &_block|
          File.write(
            "dependency-tree-output.json",
            {
              groupId: "com.dependabot",
              artifactId: "test-project",
              version: "1.0-SNAPSHOT",
              type: "jar",
              scope: "",
              classifier: "",
              optional: "false",
              children: [
                {
                  groupId: "com.example",
                  artifactId: "example-artifact",
                  version: "1.0.0",
                  type: "jar",
                  scope: "compile",
                  classifier: "",
                  optional: "false",
                  children: [
                    {
                      groupId: "com.example",
                      artifactId: "example-transitive-artifact",
                      version: "1.0.2",
                      type: "jar",
                      scope: "compile",
                      classifier: "",
                      optional: "false",
                      children: [
                        {
                          groupId: "com.example",
                          artifactId: "example-nested-artifact",
                          version: "1.0.3",
                          type: "jar",
                          scope: "compile",
                          classifier: "",
                          optional: "false"
                        }
                      ]
                    }
                  ]
                }
              ]
            }.to_json
          )
        end

        expect(dependency_set.dependencies.size).to eq(3)
        expect(dependency_set.dependencies[0].name).to eq("com.example:example-artifact")
        expect(dependency_set.dependencies[0].version).to eq("1.0.0")
        expect(dependency_set.dependencies[1].name).to eq("com.example:example-transitive-artifact")
        expect(dependency_set.dependencies[1].version).to eq("1.0.2")
        expect(dependency_set.dependencies[2].name).to eq("com.example:example-nested-artifact")
        expect(dependency_set.dependencies[2].version).to eq("1.0.3")
        expect(dependency_set.dependencies[2].requirements.first[:metadata][:pulled_in_by])
          .to eq("com.example:example-transitive-artifact")
      end
    end
  end

  describe "build_dependency_set safety and registries" do
    let(:dependency_set) { described_class.build_dependency_set(dependency_files, credentials: credentials) }
    let(:credentials) { [] }
    let(:dependency_files) do
      [Dependabot::DependencyFile.new(name: "pom.xml", content: "<project><dependencies></dependencies></project>")]
    end
    let(:tree) do
      {
        groupId: "com.dependabot", artifactId: "test-project", version: "1.0", type: "jar", scope: "",
        children: [
          { groupId: "junit", artifactId: "junit", version: "4.12", type: "jar", scope: "test", classifier: "" }
        ]
      }.to_json
    end

    it "records the scope and puts test dependencies in the test group" do
      allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin) do |output_file, **|
        File.write(output_file, tree)
      end

      requirement = dependency_set.dependencies.first.requirements.first
      expect(requirement[:groups]).to eq(["test"])
      expect(requirement[:metadata]).to eq(packaging_type: "jar", scope: "test", pom_file: "pom.xml")
    end

    context "when the scan fails or times out" do
      before do
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "[ERROR] Could not transfer from https://user:secret@registry.example.test\n" \
                     "Timed out due to inactivity after 900 seconds",
            error_context: {}
          )
        )
      end

      it "returns nil and logs one line without Maven output" do
        allow(Dependabot.logger).to receive(:warn)

        expect(dependency_set).to be_nil
        expect(Dependabot.logger).to have_received(:warn).once.with(
          "Maven dependency tree scan failed (Dependabot::SharedHelpers::HelperSubprocessFailed); " \
          "using declared dependencies only"
        )
      end
    end

    context "when the scan output is not valid JSON" do
      before do
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin) do |output_file, **|
          File.write(output_file, "not json")
        end
      end

      it { expect(dependency_set).to be_nil }
    end

    context "with registry credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            "type" => "maven_repository", "url" => "https://base.example.test/maven/", "replaces-base" => true
          ),
          Dependabot::Credential.new("type" => "maven_repository", "url" => "https://extra.example.test/maven/"),
          Dependabot::Credential.new("type" => "git_source", "host" => "github.com")
        ]
      end

      it "mirrors Central to the replaces-base registry and adds the others" do
        received = nil
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin) do |_file, **kwargs|
          received = kwargs
        end

        dependency_set

        expect(received[:mirror]).to have_attributes(
          url: "https://base.example.test/maven", mirror_of: "central"
        )
        expect(received[:repository_urls]).to eq(["https://extra.example.test/maven"])
      end
    end

    context "without registry credentials" do
      it "keeps Maven's defaults" do
        received = nil
        allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin) do |_file, **kwargs|
          received = kwargs
        end

        dependency_set

        expect(received).to eq(mirror: nil, repository_urls: [])
      end
    end
  end

  describe "create_directory_structure" do
    let(:base_depth_path) { described_class.create_directory_structure(dependency_files, temp_path) }
    let(:temp_path) { Dir.mktmpdir }

    context "with no files" do
      let(:dependency_files) do
        []
      end

      it "creates a directory structure with the correct depth" do
        expect(base_depth_path).to eq(temp_path)
        expect(Dir.exist?(base_depth_path)).to be true
      end
    end

    context "with a single pom.xml file" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(name: "pom.xml", content: "<project><dependencies></dependencies></project>"),
          Dependabot::DependencyFile.new(
            name: "subdir/pom.xml",
            content: "<project><dependencies></dependencies></project>"
          )
        ]
      end

      it "creates a directory structure with the correct depth" do
        expect(base_depth_path).to eq(temp_path)
        expect(Dir.exist?(base_depth_path)).to be true
      end
    end

    context "with multiple pom.xml files in different directories" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(name: "pom.xml", content: "<project><dependencies></dependencies></project>"),
          Dependabot::DependencyFile.new(
            name: "subdir/pom.xml",
            content: "<project><dependencies></dependencies></project>"
          ),
          Dependabot::DependencyFile.new(
            name: "another/subdir/pom.xml",
            content: "<project><dependencies></dependencies></project>"
          )
        ]
      end

      it "creates a directory structure with the correct depth" do
        expect(base_depth_path).to eq(temp_path)
        expect(Dir.exist?(base_depth_path)).to be true
      end
    end

    context "with multiple pom.xml files with relative path leading to the directories up the filesystem tree" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(name: "pom.xml", content: "<project><dependencies></dependencies></project>"),
          Dependabot::DependencyFile.new(
            name: "../pom.xml",
            content: "<project><dependencies></dependencies></project>"
          ),
          Dependabot::DependencyFile.new(
            name: "../../../pom.xml",
            content: "<project><dependencies></dependencies></project>"
          )
        ]
      end

      it "creates a directory structure with the correct depth" do
        expect(base_depth_path).to eq(File.join(temp_path, "l0/l1/l2"))
        expect(Dir.exist?(base_depth_path)).to be true
      end
    end

    context "with multiple pom.xml files with denormalized paths" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(name: "pom.xml", content: "<project><dependencies></dependencies></project>"),
          Dependabot::DependencyFile.new(
            name: "../subdir/../pom.xml",
            content: "<project><dependencies></dependencies></project>"
          )
        ]
      end

      it "creates a directory structure with the correct depth" do
        expect(base_depth_path).to eq(File.join(temp_path, "l0"))
        expect(Dir.exist?(base_depth_path)).to be true
      end
    end
  end

  describe "reading the dependency tree" do
    let(:dependency_set) { described_class.build_dependency_set([pom]) }
    let(:pom) { Dependabot::DependencyFile.new(name: "pom.xml", content: "<project/>") }
    let(:tree) do
      {
        "groupId" => "com.example", "artifactId" => "api", "version" => "1.0", "type" => "jar", "scope" => "",
        "children" => [
          {
            "groupId" => "org.example", "artifactId" => "direct", "version" => "2.0", "type" => "jar",
            "scope" => "compile", "classifier" => "",
            "children" => [
              { "groupId" => "org.example", "artifactId" => "transitive", "version" => "3.0", "type" => "jar",
                "scope" => "compile", "classifier" => "jdk8" }
            ]
          },
          { "groupId" => "junit", "artifactId" => "junit", "version" => "4.13", "type" => "jar", "scope" => "test" },
          { "groupId" => "org.example", "artifactId" => "no-version" },
          "not a node"
        ]
      }
    end

    before do
      allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin) do |output_file, **|
        File.write(output_file, JSON.generate(tree))
      end
    end

    def requirement_for(name)
      dependency_set.dependencies.find { |dep| dep.name == name }.requirements.first
    end

    it "skips the module itself and malformed nodes" do
      expect(dependency_set.dependencies.map(&:name))
        .to eq(%w(org.example:direct org.example:transitive junit:junit))
    end

    it "adds direct dependencies without pulled_in_by and drops empty values" do
      expect(requirement_for("org.example:direct")).to eq(
        requirement: "2.0",
        file: nil,
        groups: [],
        source: nil,
        metadata: { packaging_type: "jar", scope: "compile", pom_file: "pom.xml" }
      )
    end

    it "records what pulled a transitive dependency in" do
      expect(requirement_for("org.example:transitive")[:metadata]).to eq(
        packaging_type: "jar",
        classifier: "jdk8",
        scope: "compile",
        pom_file: "pom.xml",
        pulled_in_by: "org.example:direct"
      )
    end

    it "puts test-scoped dependencies in the test group" do
      expect(requirement_for("junit:junit")[:groups]).to eq(["test"])
    end

    context "when the tree is not a JSON object" do
      let(:tree) { [] }

      it { expect(dependency_set.dependencies).to be_empty }
    end
  end

  describe ".merge_requirements" do
    def requirement(**attrs)
      Dependabot::DependencyRequirement.create(
        { requirement: nil, file: nil, groups: [], source: nil, metadata: {} }.merge(attrs)
      )
    end

    subject(:merged) { described_class.merge_requirements(requirements).map(&:to_h) }

    context "with a declared and a scanned requirement from the same POM" do
      let(:requirements) do
        [
          requirement(
            requirement: "${guava.version}",
            file: "pom.xml",
            groups: [],
            metadata: { packaging_type: "jar", property_name: "guava.version", classifier: nil }
          ),
          requirement(
            requirement: "23.0",
            groups: ["test"],
            metadata: { packaging_type: "bundle", classifier: "jdk8", scope: "test", pom_file: "pom.xml" }
          )
        ]
      end

      # The file updater matches groups against the XML node's scope, e.g. a versioned
      # dependencyManagement entry (no scope) used as test scope in <dependencies>.
      it "keeps the XML requirement, file and groups and adds what the scan resolved" do
        expect(merged).to eq(
          [{
            requirement: "${guava.version}",
            file: "pom.xml",
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar", classifier: "jdk8", scope: "test",
              pom_file: "pom.xml", property_name: "guava.version"
            }
          }]
        )
      end
    end

    context "with a declared requirement whose version comes from a parent" do
      let(:requirements) do
        [
          requirement(file: "pom.xml", metadata: { packaging_type: "jar" }),
          requirement(requirement: "3.1.0", metadata: { pom_file: "pom.xml", scope: "compile" })
        ]
      end

      it "keeps the nil requirement" do
        expect(merged.map { |req| req[:requirement] }).to eq([nil])
      end
    end

    context "with scanned requirements from other POMs" do
      let(:requirements) do
        [
          requirement(requirement: "23.0", file: "model/pom.xml"),
          requirement(requirement: "23.0", metadata: { pom_file: "model/pom.xml" }),
          requirement(requirement: "23.0", metadata: { pom_file: "api/pom.xml", pulled_in_by: "com.example:model" })
        ]
      end

      it "keeps the unmatched ones as they are" do
        expect(merged.map { |req| [req[:file], req[:metadata][:pom_file]] })
          .to eq([["model/pom.xml", "model/pom.xml"], [nil, "api/pom.xml"]])
      end
    end

    context "with only declared requirements" do
      let(:requirements) { [requirement(requirement: "1.0", file: "pom.xml")] }

      it { expect(merged).to eq([requirements.first.to_h]) }
    end
  end
end
