# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/maven/file_parser/repositories_finder"
require "dependabot/maven/file_parser/pom_fetcher"

RSpec.describe Dependabot::Maven::FileParser::RepositoriesFinder do
  let(:finder) do
    described_class.new(
      pom_fetcher: pom_fetcher,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end
  let(:credentials) { [] }
  let(:dependency_files) { [base_pom] }
  let(:base_pom) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: fixture("poms", base_pom_fixture_name)
    )
  end
  let(:pom_fetcher) { Dependabot::Maven::FileParser::PomFetcher.new(dependency_files: dependency_files) }
  let(:base_pom_fixture_name) { "basic_pom.xml" }

  describe "#central_repo_url" do
    it "returns the central repo URL by default" do
      expect(finder.central_repo_url).to eq("https://repo.maven.apache.org/maven2")
    end

    context "when replaces-base is present" do
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "maven_repository",
          "url" => "https://example.com",
          "replaces-base" => true
        })]
      end

      it "returns that URL instead" do
        expect(finder.central_repo_url).to eq("https://example.com")
      end
    end
  end

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
        expect(repository_urls).to eq(
          %w(
            http://scala-tools.org/repo-releases
            http://repository.jboss.org/maven2
            http://plugin-repository.jboss.org/maven2
            https://repo.maven.apache.org/maven2
          )
        )
      end

      it "remembers what it's seen" do
        custom_pom = Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "custom_repositories_pom.xml")
        )
        expect(finder.repository_urls(pom: custom_pom)).to eq(
          %w(
            http://scala-tools.org/repo-releases
            http://repository.jboss.org/maven2
            http://plugin-repository.jboss.org/maven2
            https://repo.maven.apache.org/maven2
          )
        )
        base_pom = Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "basic_pom.xml")
        )
        expect(finder.repository_urls(pom: base_pom)).to eq(
          %w(
            http://scala-tools.org/repo-releases
            http://repository.jboss.org/maven2
            http://plugin-repository.jboss.org/maven2
            https://repo.maven.apache.org/maven2
          )
        )
        overwrite_central_pom = Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "overwrite_central_pom.xml")
        )
        expect(finder.repository_urls(pom: overwrite_central_pom)).to eq(
          %w(
            http://scala-tools.org/repo-releases
            http://repository.jboss.org/maven2
            http://plugin-repository.jboss.org/maven2
            https://example.com
          )
        )
      end

      it "snapshots repositories are returned" do
        custom_pom = Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "custom_repositories_pom.xml")
        )
        expect(finder.repository_urls(pom: custom_pom, exclude_snapshots: false)).to eq(
          %w(
            http://scala-tools.org/repo-releases
            http://repository.jboss.org/maven2
            https://oss.sonatype.org/content/repositories/releases-false-only
            https://oss.sonatype.org/content/repositories/snapshots-with-releases
            http://plugin-repository.jboss.org/maven2
            https://oss.sonatype.org/content/repositories/plugin-releases-false-only
            https://oss.sonatype.org/content/repositories/plugin-snapshots-with-releases
            https://repo.maven.apache.org/maven2
          )
        )
      end

      context "when the pom overwrites central" do
        let(:base_pom_fixture_name) { "overwrite_central_pom.xml" }

        it "does not include central" do
          expect(repository_urls).to eq(
            %w(
              https://example.com
            )
          )
        end
      end

      context "with credentials" do
        let(:base_pom_fixture_name) { "basic_pom.xml" }
        let(:credentials) do
          [
            Dependabot::Credential.new({ "type" => "maven_repository", "url" => "https://example.com" }),
            # ignored since it's not maven
            Dependabot::Credential.new({ "type" => "git_source", "url" => "https://github.com" })
          ]
        end

        it "adds the credential urls first" do
          expect(repository_urls).to eq(
            %w(
              https://example.com
              https://repo.maven.apache.org/maven2
            )
          )
        end
      end

      context "when the dependency uses properties" do
        let(:base_pom_fixture_name) { "property_repo_pom.xml" }

        it "handles the property interpolation" do
          expect(repository_urls).to eq(
            %w(
              http://download.eclipse.org/technology/m2e/releases
              http://download.eclipse.org/releases/neon
              http://eclipse-cs.sf.net/update
              https://dl.bintray.com/pmd/pmd-eclipse-plugin/updates
              http://findbugs.cs.umd.edu/eclipse
              http://download.eclipse.org/tools/orbit/downloads/drops/R20160221192158/repository
              http://repository.sonatype.org/content/groups/sonatype-public-grid
              https://repo.maven.apache.org/maven2
            )
          )
        end
      end

      context "when the dependency is in the parent POM" do
        let(:dependency_files) { [base_pom, child_pom] }
        let(:child_pom) do
          Dependabot::DependencyFile.new(
            name: "child/pom.xml",
            content: fixture("poms", child_pom_fixture_name)
          )
        end
        let(:child_pom_fixture_name) { "custom_repositories_child_pom.xml" }

        context "when checking the parent's repositories" do
          it "doesn't include the declarations from the child" do
            expect(repository_urls).to eq(
              %w(
                http://scala-tools.org/repo-releases
                http://repository.jboss.org/maven2
                http://plugin-repository.jboss.org/maven2
                https://repo.maven.apache.org/maven2
              )
            )
          end
        end

        context "when checking the child's repositories" do
          let(:pom) { child_pom }

          it "includes the declarations from the parent and the child" do
            expect(repository_urls).to eq(
              %w(
                http://child-repository.jboss.org/maven2
                http://scala-tools.org/repo-releases
                http://repository.jboss.org/maven2
                http://plugin-repository.jboss.org/maven2
                https://repo.maven.apache.org/maven2
              )
            )
          end

          context "when asked to exclude inherited repos" do
            it "excludes the declarations in the parent" do
              expect(finder.repository_urls(pom: pom, exclude_inherited: true))
                .to eq(
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
            "https://repo.maven.apache.org/maven2/" \
              "org/scala-tools/maven-scala-plugin/2.15.2/" \
              "maven-scala-plugin-2.15.2.pom"
          end
          let(:custom_url) do
            "http://child-repository.jboss.org/maven2/" \
              "org/scala-tools/maven-scala-plugin/2.15.2/" \
              "maven-scala-plugin-2.15.2.pom"
          end

          context "when specified a range of versions so can't be" do
            let(:child_pom_fixture_name) do
              "custom_repositories_child_pom_range.xml"
            end

            it "returns the repositories relevant to the child" do
              expect(repository_urls).to eq(
                %w(
                  http://child-repository.jboss.org/maven2
                  https://repo.maven.apache.org/maven2
                )
              )
            end
          end

          context "when dependency uses properties so can't be fetched" do
            let(:child_pom_fixture_name) do
              "custom_repositories_child_pom_with_props.xml"
            end

            it "returns the repositories relevant to the child" do
              expect(repository_urls).to eq(
                %w(
                  http://child-repository.jboss.org/maven2
                  https://repo.maven.apache.org/maven2
                )
              )
            end
          end

          context "when source is the central repo" do
            before do
              stub_request(:get, central_url)
                .to_return(status: 200, body: base_pom.content)
              stub_request(:get, custom_url)
                .to_return(status: 200, body: "some rubbish")
            end

            it "includes the declarations from the parent and the child" do
              expect(repository_urls).to eq(
                %w(
                  http://child-repository.jboss.org/maven2
                  http://scala-tools.org/repo-releases
                  http://repository.jboss.org/maven2
                  http://plugin-repository.jboss.org/maven2
                  https://repo.maven.apache.org/maven2
                )
              )
            end

            it "caches the call" do
              finder.repository_urls(pom: pom)
              finder.repository_urls(pom: pom)

              expect(WebMock).to have_requested(:get, central_url).once
              expect(WebMock).to have_requested(:get, custom_url).once
            end

            context "when source can't be found" do
              before do
                stub_request(:get, central_url)
                  .to_return(status: 200, body: "some rubbish")
                stub_request(:get, custom_url)
                  .to_return(status: 200, body: "some rubbish")
              end

              it "returns the repositories relevant to the child" do
                expect(repository_urls).to eq(
                  %w(
                    http://child-repository.jboss.org/maven2
                    https://repo.maven.apache.org/maven2
                  )
                )
              end
            end
          end

          context "when dependency is from the custom repo" do
            before do
              stub_request(:get, central_url)
                .to_return(status: 200, body: "some rubbish")
              stub_request(:get, custom_url)
                .to_return(status: 200, body: base_pom.content)
            end

            it "includes the declarations from the parent and the child" do
              expect(repository_urls).to eq(
                %w(
                  http://child-repository.jboss.org/maven2
                  http://scala-tools.org/repo-releases
                  http://repository.jboss.org/maven2
                  http://plugin-repository.jboss.org/maven2
                  https://repo.maven.apache.org/maven2
                )
              )
            end
          end
        end
      end
    end
  end
end
