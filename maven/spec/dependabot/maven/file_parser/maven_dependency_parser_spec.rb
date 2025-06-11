# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
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
          File.write("dependency-tree-output.json", "{
            \"groupId\": \"com.dependabot\",
            \"artifactId\": \"test-project\",
            \"version\": \"1.0-SNAPSHOT\",
            \"type\": \"jar\",
            \"scope\": \"\",
            \"classifier\": \"\",
            \"optional\": \"false\",
            \"children\": [{
              \"groupId\": \"com.example\",
              \"artifactId\": \"example-artifact\",
              \"version\": \"1.0.0\",
              \"type\": \"jar\",
              \"scope\": \"compile\",
              \"classifier\": \"\",
              \"optional\": \"false\"
            }]
          }")
        end

        expect(dependency_set.dependencies.size).to eq(2)
        expect(dependency_set.dependencies[0].name).to eq("com.dependabot:test-project")
        expect(dependency_set.dependencies[0].version).to eq("1.0-SNAPSHOT")
        expect(dependency_set.dependencies[1].name).to eq("com.example:example-artifact")
        expect(dependency_set.dependencies[1].version).to eq("1.0.0")
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
          File.write("dependency-tree-output.json", "{
            \"groupId\": \"com.dependabot\",
            \"artifactId\": \"test-project\",
            \"version\": \"1.0-SNAPSHOT\",
            \"type\": \"jar\",
            \"scope\": \"\",
            \"classifier\": \"\",
            \"optional\": \"false\",
            \"children\": [
              {
                \"groupId\": \"com.example\",
                \"artifactId\": \"example-artifact\",
                \"version\": \"1.0.0\",
                \"type\": \"jar\",
                \"scope\": \"compile\",
                \"classifier\": \"\",
                \"optional\": \"false\"
              },
              {
                \"groupId\": \"com.example\",
                \"artifactId\": \"example-second-artifact\",
                \"version\": \"1.0.1\",
                \"type\": \"jar\",
                \"scope\": \"compile\",
                \"classifier\": \"\",
                \"optional\": \"false\"
              }
            ]
          }")
        end

        expect(dependency_set.dependencies.size).to eq(3)
        expect(dependency_set.dependencies[0].name).to eq("com.dependabot:test-project")
        expect(dependency_set.dependencies[0].version).to eq("1.0-SNAPSHOT")
        expect(dependency_set.dependencies[1].name).to eq("com.example:example-artifact")
        expect(dependency_set.dependencies[1].version).to eq("1.0.0")
        expect(dependency_set.dependencies[2].name).to eq("com.example:example-second-artifact")
        expect(dependency_set.dependencies[2].version).to eq("1.0.1")
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
          File.write("dependency-tree-output.json", "{
            \"groupId\": \"com.dependabot\",
            \"artifactId\": \"test-project\",
            \"version\": \"1.0-SNAPSHOT\",
            \"type\": \"jar\",
            \"scope\": \"\",
            \"classifier\": \"\",
            \"optional\": \"false\",
            \"children\": [
              {
                \"groupId\": \"com.example\",
                \"artifactId\": \"example-artifact\",
                \"version\": \"1.0.0\",
                \"type\": \"jar\",
                \"scope\": \"compile\",
                \"classifier\": \"\",
                \"optional\": \"false\",
                \"children\": [
                  {
                    \"groupId\": \"com.example\",
                    \"artifactId\": \"example-transitive-artifact\",
                    \"version\": \"1.0.2\",
                    \"type\": \"jar\",
                    \"scope\": \"compile\",
                    \"classifier\": \"\",
                    \"optional\": \"false\"
                  }
                ]
              },
              {
                \"groupId\": \"com.example\",
                \"artifactId\": \"example-second-artifact\",
                \"version\": \"1.0.1\",
                \"type\": \"jar\",
                \"scope\": \"compile\",
                \"classifier\": \"\",
                \"optional\": \"false\"
              }
            ]
          }")
        end

        expect(dependency_set.dependencies.size).to eq(4)
        expect(dependency_set.dependencies[0].name).to eq("com.dependabot:test-project")
        expect(dependency_set.dependencies[0].version).to eq("1.0-SNAPSHOT")
        expect(dependency_set.dependencies[1].name).to eq("com.example:example-artifact")
        expect(dependency_set.dependencies[1].version).to eq("1.0.0")
        expect(dependency_set.dependencies[2].name).to eq("com.example:example-transitive-artifact")
        expect(dependency_set.dependencies[2].version).to eq("1.0.2")
        expect(dependency_set.dependencies[3].name).to eq("com.example:example-second-artifact")
        expect(dependency_set.dependencies[3].version).to eq("1.0.1")
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
          File.write("dependency-tree-output.json", "{
            \"groupId\": \"com.dependabot\",
            \"artifactId\": \"test-project\",
            \"version\": \"1.0-SNAPSHOT\",
            \"type\": \"jar\",
            \"scope\": \"\",
            \"classifier\": \"\",
            \"optional\": \"false\",
            \"children\": [
              {
                \"groupId\": \"com.example\",
                \"artifactId\": \"example-artifact\",
                \"version\": \"1.0.0\",
                \"type\": \"jar\",
                \"scope\": \"compile\",
                \"classifier\": \"\",
                \"optional\": \"false\",
                \"children\": [
                  {
                    \"groupId\": \"com.example\",
                    \"artifactId\": \"example-transitive-artifact\",
                    \"version\": \"1.0.2\",
                    \"type\": \"jar\",
                    \"scope\": \"compile\",
                    \"classifier\": \"\",
                    \"optional\": \"false\",
                    \"children\": [
                      {
                        \"groupId\": \"com.example\",
                        \"artifactId\": \"example-nested-artifact\",
                        \"version\": \"1.0.3\",
                        \"type\": \"jar\",
                        \"scope\": \"compile\",
                        \"classifier\": \"\",
                        \"optional\": \"false\"
                      }
                    ]
                  }
                ]
              }
            ]
          }")
        end

        expect(dependency_set.dependencies.size).to eq(4)
        expect(dependency_set.dependencies[0].name).to eq("com.dependabot:test-project")
        expect(dependency_set.dependencies[0].version).to eq("1.0-SNAPSHOT")
        expect(dependency_set.dependencies[1].name).to eq("com.example:example-artifact")
        expect(dependency_set.dependencies[1].version).to eq("1.0.0")
        expect(dependency_set.dependencies[2].name).to eq("com.example:example-transitive-artifact")
        expect(dependency_set.dependencies[2].version).to eq("1.0.2")
        expect(dependency_set.dependencies[3].name).to eq("com.example:example-nested-artifact")
        expect(dependency_set.dependencies[3].version).to eq("1.0.3")
      end
    end
  end
end
