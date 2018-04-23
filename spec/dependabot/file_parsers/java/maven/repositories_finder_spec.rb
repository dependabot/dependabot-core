# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/java/maven/repositories_finder"

RSpec.describe Dependabot::FileParsers::Java::Maven::RepositoriesFinder do
  let(:finder) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [base_pom] }
  let(:base_pom) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: fixture("java", "poms", base_pom_fixture_name)
    )
  end
  let(:base_pom_fixture_name) { "basic_pom.xml" }

  describe "#repository_urls" do
    subject(:repository_urls) { finder.repository_urls(pom: pom) }
    let(:pom) { base_pom }

    context "when there are no parents, and no repository declarations" do
      let(:base_pom_fixture_name) { "basic_pom.xml" }
      it { is_expected.to eq(["https://repo.maven.apache.org/maven2"]) }
    end

    context "when there are repository declarations" do
      let(:base_pom_fixture_name) { "custom_repositories_pom.xml" }

      it "includes the additional declarations" do
        expect(repository_urls).to match_array(
          %w(
            https://repo.maven.apache.org/maven2
            http://repository.jboss.org/maven2
            http://scala-tools.org/repo-releases
            http://plugin-repository.jboss.org/maven2
          )
        )
      end

      context "in the parent POM" do
        let(:dependency_files) { [base_pom, child_pom] }
        let(:child_pom) do
          Dependabot::DependencyFile.new(
            name: "child/pom.xml",
            content: fixture("java", "poms", child_pom_fixture_name)
          )
        end
        let(:child_pom_fixture_name) { "custom_repositories_child_pom.xml" }

        context "checking the parent's repositories" do
          it "doesn't include the declarations from the child" do
            expect(repository_urls).to match_array(
              %w(
                https://repo.maven.apache.org/maven2
                http://repository.jboss.org/maven2
                http://scala-tools.org/repo-releases
                http://plugin-repository.jboss.org/maven2
              )
            )
          end
        end

        context "checking the child's repositories" do
          let(:pom) { child_pom }

          it "includes the declarations from the parent and the child" do
            expect(repository_urls).to match_array(
              %w(
                https://repo.maven.apache.org/maven2
                http://repository.jboss.org/maven2
                http://scala-tools.org/repo-releases
                http://plugin-repository.jboss.org/maven2
                http://child-repository.jboss.org/maven2
              )
            )
          end

          context "when asked to exclude inherited repos" do
            it "excludes the declarations in the parent" do
              expect(finder.repository_urls(pom: pom, exclude_inherited: true)).
                to match_array(
                  %w(
                    http://child-repository.jboss.org/maven2
                    https://repo.maven.apache.org/maven2
                  )
                )
            end
          end
        end

        context "when the parent has to be fetched remotely" do
          let(:dependency_files) { [child_pom] }
          let(:pom) { child_pom }

          let(:central_url) do
            "https://repo.maven.apache.org/maven2/"\
            "org/scala-tools/maven-scala-plugin/2.15.2/"\
            "maven-scala-plugin-2.15.2.pom"
          end
          let(:custom_url) do
            "http://child-repository.jboss.org/maven2/"\
            "org/scala-tools/maven-scala-plugin/2.15.2/"\
            "maven-scala-plugin-2.15.2.pom"
          end

          context "from the central repo" do
            before do
              stub_request(:get, central_url).
                to_return(status: 200, body: base_pom.content)
              stub_request(:get, custom_url).
                to_return(status: 200, body: "some rubbish")
            end

            it "includes the declarations from the parent and the child" do
              expect(repository_urls).to match_array(
                %w(
                  https://repo.maven.apache.org/maven2
                  http://repository.jboss.org/maven2
                  http://scala-tools.org/repo-releases
                  http://plugin-repository.jboss.org/maven2
                  http://child-repository.jboss.org/maven2
                )
              )
            end

            it "caches the call" do
              finder.repository_urls(pom: pom)
              finder.repository_urls(pom: pom)

              expect(WebMock).to have_requested(:get, central_url).once
              expect(WebMock).to have_requested(:get, custom_url).once
            end

            context "and can't be found" do
              before do
                stub_request(:get, central_url).
                  to_return(status: 200, body: "some rubbish")
                stub_request(:get, custom_url).
                  to_return(status: 200, body: "some rubbish")
              end

              it "returns the repositories relevant to the child" do
                expect(repository_urls).to match_array(
                  %w(
                    http://child-repository.jboss.org/maven2
                    https://repo.maven.apache.org/maven2
                  )
                )
              end
            end
          end

          context "from the custom repo" do
            before do
              stub_request(:get, central_url).
                to_return(status: 200, body: "some rubbish")
              stub_request(:get, custom_url).
                to_return(status: 200, body: base_pom.content)
            end

            it "includes the declarations from the parent and the child" do
              expect(repository_urls).to match_array(
                %w(
                  https://repo.maven.apache.org/maven2
                  http://repository.jboss.org/maven2
                  http://scala-tools.org/repo-releases
                  http://plugin-repository.jboss.org/maven2
                  http://child-repository.jboss.org/maven2
                )
              )
            end
          end
        end
      end
    end
  end
end
