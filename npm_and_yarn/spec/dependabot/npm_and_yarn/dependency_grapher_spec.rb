# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn"
require "dependabot/dependency_graphers"

RSpec.describe Dependabot::NpmAndYarn::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("npm_and_yarn").new(
      file_parser: parser
    )
  end

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("npm_and_yarn").new(
      dependency_files: dependency_files,
      repo_contents_path: nil,
      source: source,
      credentials: credentials
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "test/npm-project",
      directory: "/",
      branch: "main"
    )
  end

  let(:credentials) do
    [
      Dependabot::Credential.new(
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      )
    ]
  end

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_corepack_for_npm_and_yarn).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_private_registry_for_corepack).and_return(true)
  end

  describe "#relevant_dependency_file" do
    context "when a lockfile exists" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_lockfile") }

      it "returns the lockfile" do
        expect(grapher.relevant_dependency_file.name).to eq("package-lock.json")
      end
    end

    context "when no lockfile exists" do
      let(:dependency_files) { project_dependency_files("grapher/npm_exact_versions_no_lockfile") }

      before do
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: Dependabot::DependencyFile.new(
            name: "package-lock.json",
            content: { "lockfileVersion" => 3, "packages" => {} }.to_json,
            directory: "/"
          )
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "returns the package.json" do
        expect(grapher.relevant_dependency_file.name).to eq("package.json")
      end
    end
  end

  describe "#resolved_dependencies" do
    context "with a lockfile present" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_lockfile") }

      it "correctly serializes the resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.count).to be >= 1

        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.package_url).to eq("pkg:npm/is-number@7.0.0")
        expect(is_number.direct).to be(true)
        expect(is_number.runtime).to be(true)
      end
    end

    context "with an aliased dependency" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_alias") }

      it "includes the real aliased package in resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        # The aliased package (is-number aliased as my-is-number) should appear
        # under its real name
        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.package_url).to eq("pkg:npm/is-number@7.0.0")
        expect(is_number.direct).to be(true)
        expect(is_number.runtime).to be(true)
      end

      it "includes non-aliased dependencies normally" do
        resolved_dependencies = grapher.resolved_dependencies

        etag = resolved_dependencies["pkg:npm/etag@1.8.1"]
        expect(etag).not_to be_nil
        expect(etag.direct).to be(true)
      end
    end

    context "with an aliased dependency that creates multiple versions of the same package" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_alias_multiversion") }

      it "marks the direct version as direct" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number7 = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number7).not_to be_nil
        expect(is_number7.direct).to be(true)
        expect(is_number7.dependencies).to eq([])
      end

      it "marks the aliased version as direct" do
        resolved_dependencies = grapher.resolved_dependencies

        # The aliased version appears under its real name and is still direct
        # because the manifest explicitly declares it (via the alias)
        is_number3 = resolved_dependencies["pkg:npm/is-number@3.0.0"]
        expect(is_number3).not_to be_nil
        expect(is_number3.direct).to be(true)
        expect(is_number3.dependencies).to include("pkg:npm/kind-of@3.2.2")
      end

      it "marks transitive versions as not direct" do
        resolved_dependencies = grapher.resolved_dependencies

        # is-number@2.1.0 is brought in transitively by fill-range
        is_number2 = resolved_dependencies["pkg:npm/is-number@2.1.0"]
        expect(is_number2).not_to be_nil
        expect(is_number2.direct).to be(false)

        # is-number@4.0.0 is brought in transitively by randomatic
        is_number4 = resolved_dependencies["pkg:npm/is-number@4.0.0"]
        expect(is_number4).not_to be_nil
        expect(is_number4.direct).to be(false)
      end

      it "resolves subdependencies of the aliased version correctly" do
        resolved_dependencies = grapher.resolved_dependencies

        kind_of = resolved_dependencies["pkg:npm/kind-of@3.2.2"]
        expect(kind_of).not_to be_nil
        expect(kind_of.direct).to be(false)
        expect(kind_of.dependencies).to include("pkg:npm/is-buffer@1.1.6")
      end
    end

    context "with a yarn aliased dependency" do
      let(:dependency_files) { project_dependency_files("grapher/yarn_with_alias") }

      it "includes the real aliased package in resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        fetch_factory = resolved_dependencies["pkg:npm/fetch-factory@0.0.1"]
        expect(fetch_factory).not_to be_nil
        expect(fetch_factory.package_url).to eq("pkg:npm/fetch-factory@0.0.1")
        expect(fetch_factory.direct).to be(true)
        expect(fetch_factory.runtime).to be(true)
      end

      it "includes non-aliased dependencies normally" do
        resolved_dependencies = grapher.resolved_dependencies

        etag = resolved_dependencies["pkg:npm/etag@1.8.1"]
        expect(etag).not_to be_nil
        expect(etag.direct).to be(true)
      end
    end

    context "with a pnpm aliased dependency" do
      let(:dependency_files) { project_dependency_files("grapher/pnpm_with_alias") }

      it "includes the real aliased package in resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        fetch_factory = resolved_dependencies["pkg:npm/fetch-factory@0.0.2"]
        expect(fetch_factory).not_to be_nil
        expect(fetch_factory.package_url).to eq("pkg:npm/fetch-factory@0.0.2")
        expect(fetch_factory.direct).to be(true)
        expect(fetch_factory.runtime).to be(true)
      end

      it "includes non-aliased dependencies normally" do
        resolved_dependencies = grapher.resolved_dependencies

        etag = resolved_dependencies["pkg:npm/etag@1.8.1"]
        expect(etag).not_to be_nil
        expect(etag.direct).to be(true)
      end
    end

    context "with a lockfile containing subdependencies" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_subdeps") }

      it "includes subdependency edges for packages with children" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.direct).to be(true)
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end

      it "reports leaf packages with empty dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(false)
        expect(is_number.dependencies).to eq([])
      end
    end

    context "with a v1 lockfile containing subdependencies" do
      let(:dependency_files) { project_dependency_files("grapher/npm_v1_with_subdeps") }

      it "includes subdependency edges for packages with children" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.direct).to be(true)
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end

      it "reports leaf packages with empty dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(false)
        expect(is_number.dependencies).to eq([])
      end
    end

    context "with an ephemeral lockfile containing subdependencies" do
      let(:dependency_files) { project_dependency_files("grapher/npm_no_lockfile") }

      let(:ephemeral_lockfile_content) do
        {
          "name" => "grapher-npm-no-lockfile",
          "version" => "1.0.0",
          "lockfileVersion" => 3,
          "packages" => {
            "" => {
              "name" => "grapher-npm-no-lockfile",
              "version" => "1.0.0",
              "dependencies" => { "to-regex-range" => "^5.0.1" }
            },
            "node_modules/to-regex-range" => {
              "version" => "5.0.1",
              "dependencies" => { "is-number" => "^7.0.0" }
            },
            "node_modules/is-number" => {
              "version" => "7.0.0"
            }
          }
        }.to_json
      end

      before do
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: Dependabot::DependencyFile.new(
            name: "package-lock.json",
            content: ephemeral_lockfile_content,
            directory: "/"
          )
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "includes subdependency edges from the generated lockfile" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end

      it "reports the package.json as the relevant file, not the ephemeral lockfile" do
        grapher.resolved_dependencies
        expect(grapher.relevant_dependency_file.name).to eq("package.json")
      end
    end

    context "with a yarn lockfile containing subdependencies" do
      let(:dependency_files) { project_dependency_files("grapher/yarn_with_subdeps") }

      it "includes subdependency edges for packages with children" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.direct).to be(true)
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end

      it "reports leaf packages with empty dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(false)
        expect(is_number.dependencies).to eq([])
      end
    end

    context "with a pnpm lockfile containing subdependencies" do
      let(:dependency_files) { project_dependency_files("grapher/pnpm_with_subdeps") }

      it "includes subdependency edges for packages with children" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.direct).to be(true)
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end

      it "reports leaf packages with empty dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(false)
        expect(is_number.dependencies).to eq([])
      end
    end

    context "with a pnpm v9 lockfile containing subdependencies" do
      let(:dependency_files) { project_dependency_files("grapher/pnpm_v9_with_subdeps") }

      it "includes subdependency edges from the snapshots section" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.direct).to be(true)
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end

      it "reports leaf packages with empty dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(false)
        expect(is_number.dependencies).to eq([])
      end
    end

    context "with multiple versions of the same transitive dependency" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_multiversion_subdeps") }

      it "includes both versions as separate resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        # is-number@6.0.0 is a direct top-level dependency
        is_number6 = resolved_dependencies["pkg:npm/is-number@6.0.0"]
        expect(is_number6).not_to be_nil
        expect(is_number6.direct).to be(true)

        # is-number@7.0.0 is a nested transitive dependency of to-regex-range
        is_number7 = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number7).not_to be_nil
        expect(is_number7.direct).to be(false)
      end

      it "correctly maps subdependencies to the nested version" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.direct).to be(true)
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end
    end

    context "with multiple versions of a dependency that each have their own subdependencies" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_multiversion_subdeps_nested") }

      it "includes both versions of kind-of as separate resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        kind_of6 = resolved_dependencies["pkg:npm/kind-of@6.0.3"]
        expect(kind_of6).not_to be_nil
        expect(kind_of6.direct).to be(true)
        expect(kind_of6.dependencies).to eq([])

        kind_of3 = resolved_dependencies["pkg:npm/kind-of@3.2.2"]
        expect(kind_of3).not_to be_nil
        expect(kind_of3.direct).to be(false)
        expect(kind_of3.dependencies).to include("pkg:npm/is-buffer@1.1.6")
      end

      it "correctly maps the dependency chain through is-number to kind-of@3" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@3.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(true)
        expect(is_number.dependencies).to include("pkg:npm/kind-of@3.2.2")
      end
    end

    context "with a yarn lockfile with multiple versions of the same transitive dependency" do
      let(:dependency_files) { project_dependency_files("grapher/yarn_with_multiversion_subdeps") }

      it "includes both versions as separate resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number6 = resolved_dependencies["pkg:npm/is-number@6.0.0"]
        expect(is_number6).not_to be_nil
        expect(is_number6.direct).to be(true)

        is_number7 = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number7).not_to be_nil
        expect(is_number7.direct).to be(false)
      end

      it "correctly maps subdependencies to the nested version" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end
    end

    context "with a yarn lockfile with multiple versions that each have their own subdependencies" do
      let(:dependency_files) { project_dependency_files("grapher/yarn_with_multiversion_subdeps_nested") }

      it "includes both versions of kind-of as separate resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        kind_of6 = resolved_dependencies["pkg:npm/kind-of@6.0.3"]
        expect(kind_of6).not_to be_nil
        expect(kind_of6.direct).to be(true)
        expect(kind_of6.dependencies).to eq([])

        kind_of3 = resolved_dependencies["pkg:npm/kind-of@3.2.2"]
        expect(kind_of3).not_to be_nil
        expect(kind_of3.direct).to be(false)
        expect(kind_of3.dependencies).to include("pkg:npm/is-buffer@1.1.6")
      end

      it "correctly maps the dependency chain through is-number to kind-of@3" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@3.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(true)
        expect(is_number.dependencies).to include("pkg:npm/kind-of@3.2.2")
      end
    end

    context "with a pnpm lockfile with multiple versions of the same transitive dependency" do
      let(:dependency_files) { project_dependency_files("grapher/pnpm_with_multiversion_subdeps") }

      it "includes both versions as separate resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number6 = resolved_dependencies["pkg:npm/is-number@6.0.0"]
        expect(is_number6).not_to be_nil
        expect(is_number6.direct).to be(true)

        is_number7 = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number7).not_to be_nil
        expect(is_number7.direct).to be(false)
      end

      it "correctly maps subdependencies to the nested version" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end
    end

    context "with a pnpm lockfile with multiple versions that each have their own subdependencies" do
      let(:dependency_files) { project_dependency_files("grapher/pnpm_with_multiversion_subdeps_nested") }

      it "includes both versions of kind-of as separate resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        kind_of6 = resolved_dependencies["pkg:npm/kind-of@6.0.3"]
        expect(kind_of6).not_to be_nil
        expect(kind_of6.direct).to be(true)
        expect(kind_of6.dependencies).to eq([])

        kind_of3 = resolved_dependencies["pkg:npm/kind-of@3.2.2"]
        expect(kind_of3).not_to be_nil
        expect(kind_of3.direct).to be(false)
        expect(kind_of3.dependencies).to include("pkg:npm/is-buffer@1.1.6")
      end

      it "correctly maps the dependency chain through is-number to kind-of@3" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@3.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(true)
        expect(is_number.dependencies).to include("pkg:npm/kind-of@3.2.2")
      end
    end

    context "with multiple versions of a scoped package" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_multiversion_scoped") }

      it "includes both versions of @octokit/types as separate resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        types13 = resolved_dependencies["pkg:npm/%40octokit/types@13.10.0"]
        expect(types13).not_to be_nil
        expect(types13.direct).to be(false)
        expect(types13.dependencies).to include("pkg:npm/%40octokit/openapi-types@24.2.0")

        types9 = resolved_dependencies["pkg:npm/%40octokit/types@9.3.2"]
        expect(types9).not_to be_nil
        expect(types9.direct).to be(false)
        expect(types9.dependencies).to include("pkg:npm/%40octokit/openapi-types@18.1.1")
      end

      it "correctly resolves the scoped dependency chain" do
        resolved_dependencies = grapher.resolved_dependencies

        endpoint = resolved_dependencies["pkg:npm/%40octokit/endpoint@9.0.6"]
        expect(endpoint).not_to be_nil
        expect(endpoint.direct).to be(true)
        expect(endpoint.dependencies).to include("pkg:npm/%40octokit/types@13.10.0")

        request_error = resolved_dependencies["pkg:npm/%40octokit/request-error@3.0.3"]
        expect(request_error).not_to be_nil
        expect(request_error.direct).to be(true)
        expect(request_error.dependencies).to include("pkg:npm/%40octokit/types@9.3.2")
      end
    end

    context "with a pnpm v9 lockfile with multiple versions of the same transitive dependency" do
      let(:dependency_files) { project_dependency_files("grapher/pnpm_v9_with_multiversion_subdeps") }

      it "includes both versions as separate resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number6 = resolved_dependencies["pkg:npm/is-number@6.0.0"]
        expect(is_number6).not_to be_nil
        expect(is_number6.direct).to be(true)

        is_number7 = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number7).not_to be_nil
        expect(is_number7.direct).to be(false)
      end

      it "correctly maps subdependencies to the nested version" do
        resolved_dependencies = grapher.resolved_dependencies

        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end
    end

    context "with an npm lockfile containing a workspace link (no version)" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_workspace_link") }

      it "gracefully skips workspace link entries and resolves versioned deps correctly" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(true)

        # Workspace link entry (no version) should not produce a malformed purl
        malformed = resolved_dependencies.keys.select { |k| k.end_with?("@") }
        expect(malformed).to be_empty
      end
    end

    context "with a yarn lockfile using grouped requirement keys" do
      let(:dependency_files) { project_dependency_files("grapher/yarn_with_grouped_keys") }

      it "resolves the correct version from grouped lockfile keys" do
        resolved_dependencies = grapher.resolved_dependencies

        # is-number@^6.0.0 and is-number@^7.0.0 are grouped into one entry resolving to 7.0.0
        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.direct).to be(true)

        # to-regex-range depends on is-number@^7.0.0 which is in the grouped key
        to_regex_range = resolved_dependencies["pkg:npm/to-regex-range@5.0.1"]
        expect(to_regex_range).not_to be_nil
        expect(to_regex_range.dependencies).to include("pkg:npm/is-number@7.0.0")
      end
    end

    context "with a pnpm lockfile containing peer metadata suffixes" do
      let(:dependency_files) { project_dependency_files("grapher/pnpm_with_peer_metadata") }

      it "strips peer metadata suffixes and produces clean purls" do
        resolved_dependencies = grapher.resolved_dependencies

        # react-dom@18.2.0 has key "react-dom@18.2.0(react@18.2.0)" in snapshots
        react_dom = resolved_dependencies["pkg:npm/react-dom@18.2.0"]
        expect(react_dom).not_to be_nil
        expect(react_dom.direct).to be(true)
        # Its subdeps should reference clean versions (no parenthesized suffixes)
        expect(react_dom.dependencies).to include("pkg:npm/scheduler@0.23.0")
        expect(react_dom.dependencies).to include("pkg:npm/react@18.2.0")

        # No purls should contain parenthesized peer metadata
        all_purls = resolved_dependencies.values.flat_map(&:dependencies) + resolved_dependencies.keys
        expect(all_purls.select { |p| p.include?("(") }).to be_empty
      end
    end

    context "without a lockfile - exact versions" do
      let(:dependency_files) { project_dependency_files("grapher/npm_exact_versions_no_lockfile") }

      before do
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: Dependabot::DependencyFile.new(
            name: "package-lock.json",
            content: { "lockfileVersion" => 3, "packages" => {} }.to_json,
            directory: "/"
          )
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "includes dependencies with exact versions from package.json" do
        resolved_dependencies = grapher.resolved_dependencies

        # With exact versions (no lockfile), the parser can still extract versions
        lodash = resolved_dependencies["pkg:npm/lodash@4.17.21"]
        expect(lodash).not_to be_nil
        expect(lodash.package_url).to eq("pkg:npm/lodash@4.17.21")
        expect(lodash.direct).to be(true)
      end
    end

    context "without a lockfile - range versions" do
      let(:dependency_files) { project_dependency_files("grapher/npm_no_lockfile") }

      context "when lockfile generation fails" do
        before do
          lockfile_generator = instance_double(
            Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator
          ).tap do |gen|
            allow(gen).to receive(:generate).and_raise(
              Dependabot::DependencyFileNotResolvable.new(
                "Could not resolve dependencies. This may be due to conflicting peer dependencies."
              )
            )
          end
          allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
            .to receive(:new).and_return(lockfile_generator)
        end

        it "does not emit a misleading warning about generating a temporary lockfile" do
          allow(Dependabot.logger).to receive(:info)
          allow(Dependabot.logger).to receive(:warn)

          grapher.resolved_dependencies

          expect(Dependabot.logger).to have_received(:info).with(/No lockfile found/)
          expect(Dependabot.logger).not_to have_received(:warn).with(/No lockfile was found/)
        end

        it "sets the error flag for degraded status" do
          grapher.resolved_dependencies

          expect(grapher.errored_fetching_subdependencies).to be(true)
        end

        it "stores the classified error as the subdependency error" do
          grapher.resolved_dependencies

          expect(grapher.subdependency_error).to be_a(Dependabot::DependencyFileNotResolvable)
          expect(grapher.subdependency_error.message).to include("conflicting peer dependencies")
        end

        it "returns dependencies without relationship data" do
          resolved_dependencies = grapher.resolved_dependencies

          resolved_dependencies.each_value do |dep|
            expect(dep.dependencies).to eq([])
          end
        end
      end

      context "when lockfile generation fails with a 401 authentication error" do
        before do
          lockfile_generator = instance_double(
            Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator
          ).tap do |gen|
            allow(gen).to receive(:generate).and_raise(
              Dependabot::PrivateSourceAuthenticationFailure.new(
                "https://npm.pkg.github.com/@dsp-testing%2fbake-off-utils"
              )
            )
          end
          allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
            .to receive(:new).and_return(lockfile_generator)
        end

        it "stores the PrivateSourceAuthenticationFailure as the subdependency error" do
          grapher.resolved_dependencies

          expect(grapher.subdependency_error).to be_a(Dependabot::PrivateSourceAuthenticationFailure)
        end

        it "includes the registry URL in the error message" do
          grapher.resolved_dependencies

          expect(grapher.subdependency_error.message).to include(
            "npm.pkg.github.com/@dsp-testing%2fbake-off-utils"
          )
          expect(grapher.subdependency_error.message).not_to include("npm warn")
          expect(grapher.subdependency_error.message).not_to include("complete log of this run")
        end

        it "sets the error flag for degraded status" do
          grapher.resolved_dependencies

          expect(grapher.errored_fetching_subdependencies).to be(true)
        end
      end

      context "when lockfile generation fails with a 403 forbidden error" do
        before do
          lockfile_generator = instance_double(
            Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator
          ).tap do |gen|
            allow(gen).to receive(:generate).and_raise(
              Dependabot::PrivateSourceAuthenticationFailure.new(
                "https://registry.npmjs.org/@private%2fpkg"
              )
            )
          end
          allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
            .to receive(:new).and_return(lockfile_generator)
        end

        it "stores the PrivateSourceAuthenticationFailure as the subdependency error" do
          grapher.resolved_dependencies

          expect(grapher.subdependency_error).to be_a(Dependabot::PrivateSourceAuthenticationFailure)
          expect(grapher.subdependency_error.message).to include(
            "registry.npmjs.org/@private%2fpkg"
          )
        end
      end

      context "when lockfile generation fails with a yarn authentication error" do
        before do
          lockfile_generator = instance_double(
            Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator
          ).tap do |gen|
            allow(gen).to receive(:generate).and_raise(
              Dependabot::PrivateSourceAuthenticationFailure.new(
                "https://npm.pkg.github.com/@scope%2fpkg"
              )
            )
          end
          allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
            .to receive(:new).and_return(lockfile_generator)
        end

        it "stores the PrivateSourceAuthenticationFailure as the subdependency error" do
          grapher.resolved_dependencies

          expect(grapher.subdependency_error).to be_a(Dependabot::PrivateSourceAuthenticationFailure)
          expect(grapher.subdependency_error.message).to include(
            "npm.pkg.github.com/@scope%2fpkg"
          )
        end
      end

      context "when lockfile generation fails with a non-auth error" do
        before do
          lockfile_generator = instance_double(
            Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator
          ).tap do |gen|
            allow(gen).to receive(:generate).and_raise(
              Dependabot::DependencyFileNotResolvable.new(
                "Could not resolve dependencies. This may be due to conflicting peer dependencies."
              )
            )
          end
          allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
            .to receive(:new).and_return(lockfile_generator)
        end

        it "preserves the error as a DependabotError" do
          grapher.resolved_dependencies

          expect(grapher.subdependency_error).to be_a(Dependabot::DependencyFileNotResolvable)
          expect(grapher.subdependency_error.message).to include("conflicting peer dependencies")
        end
      end

      context "when lockfile generation succeeds" do
        before do
          lockfile_generator = instance_double(
            Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
            generate: Dependabot::DependencyFile.new(
              name: "package-lock.json",
              content: { "lockfileVersion" => 3, "packages" => {} }.to_json,
              directory: "/"
            )
          )
          allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
            .to receive(:new).and_return(lockfile_generator)
        end

        it "emits a warning about missing lockfile" do
          allow(Dependabot.logger).to receive(:info)
          allow(Dependabot.logger).to receive(:warn)

          grapher.resolved_dependencies

          expect(Dependabot.logger).to have_received(:info).with(/No lockfile found/)
          expect(Dependabot.logger).to have_received(:warn).with(/No lockfile was found/)
        end

        it "reports package.json as the relevant dependency file, not the ephemeral lockfile" do
          grapher.resolved_dependencies
          expect(grapher.relevant_dependency_file.name).to eq("package.json")
        end
      end
    end
  end

  describe "lockfile parse errors" do
    context "with an npm lockfile that errors during relationship extraction" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_subdeps") }

      before do
        # Pre-populate dependencies via the parser (which reads the valid lockfile)
        grapher.send(:prepare!)
        # Now swap in a corrupt lockfile for relationship extraction
        corrupt_lockfile = Dependabot::DependencyFile.new(
          name: "package-lock.json", content: "not valid json {{{", directory: "/"
        )
        grapher.instance_variable_set(:@npm_lockfile, corrupt_lockfile)
      end

      it "sets the errored_fetching_subdependencies flag" do
        grapher.resolved_dependencies

        expect(grapher.errored_fetching_subdependencies).to be(true)
      end

      it "stores the parse error as subdependency_error" do
        grapher.resolved_dependencies

        expect(grapher.subdependency_error).to be_a(JSON::ParserError)
      end

      it "still returns dependencies without relationship data" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies).not_to be_empty
        resolved_dependencies.each_value do |dep|
          expect(dep.dependencies).to eq([])
        end
      end
    end

    context "with a yarn lockfile that errors during relationship extraction" do
      let(:dependency_files) { project_dependency_files("grapher/yarn_with_subdeps") }

      before do
        # Pre-populate dependencies via the parser (which reads the valid lockfile)
        grapher.send(:prepare!)
        # Now swap in a corrupt lockfile for relationship extraction
        corrupt_lockfile = Dependabot::DependencyFile.new(
          name: "yarn.lock", content: "\x00\x01 invalid", directory: "/"
        )
        grapher.instance_variable_set(:@yarn_lockfile, corrupt_lockfile)
      end

      it "sets the errored_fetching_subdependencies flag" do
        grapher.resolved_dependencies

        expect(grapher.errored_fetching_subdependencies).to be(true)
      end

      it "stores the error as subdependency_error" do
        grapher.resolved_dependencies

        expect(grapher.subdependency_error).to be_a(StandardError)
      end

      it "still returns dependencies without relationship data" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies).not_to be_empty
        resolved_dependencies.each_value do |dep|
          expect(dep.dependencies).to eq([])
        end
      end
    end

    context "with a pnpm lockfile that errors during relationship extraction" do
      let(:dependency_files) { project_dependency_files("grapher/pnpm_with_subdeps") }

      before do
        # Pre-populate dependencies via the parser (which reads the valid lockfile)
        grapher.send(:prepare!)
        # Now swap in a corrupt lockfile for relationship extraction
        corrupt_lockfile = Dependabot::DependencyFile.new(
          name: "pnpm-lock.yaml", content: ": :\n  invalid: [yaml", directory: "/"
        )
        grapher.instance_variable_set(:@pnpm_lockfile, corrupt_lockfile)
      end

      it "sets the errored_fetching_subdependencies flag" do
        grapher.resolved_dependencies

        expect(grapher.errored_fetching_subdependencies).to be(true)
      end

      it "stores the parse error as subdependency_error" do
        grapher.resolved_dependencies

        expect(grapher.subdependency_error).to be_a(Psych::SyntaxError)
      end

      it "still returns dependencies without relationship data" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies).not_to be_empty
        resolved_dependencies.each_value do |dep|
          expect(dep.dependencies).to eq([])
        end
      end
    end
  end

  describe "package manager detection" do
    context "with npm project (packageManager field)" do
      let(:package_json_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "packageManager" => "npm@10.0.0",
          "dependencies" => { "lodash" => "4.17.21" }
        }.to_json
      end

      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: package_json_content,
            directory: "/"
          )
        ]
      end

      before do
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: Dependabot::DependencyFile.new(
            name: "package-lock.json",
            content: "{}",
            directory: "/"
          )
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "detects npm as the package manager" do
        expect(grapher.send(:detected_package_manager)).to eq("npm")
      end
    end

    context "with yarn project (packageManager field)" do
      let(:package_json_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "packageManager" => "yarn@3.6.0",
          "dependencies" => { "lodash" => "4.17.21" }
        }.to_json
      end

      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: package_json_content,
            directory: "/"
          )
        ]
      end

      before do
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: Dependabot::DependencyFile.new(
            name: "yarn.lock",
            content: "",
            directory: "/"
          )
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "detects yarn as the package manager" do
        expect(grapher.send(:detected_package_manager)).to eq("yarn")
      end
    end

    context "with pnpm project (packageManager field)" do
      let(:package_json_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "packageManager" => "pnpm@8.6.0",
          "dependencies" => { "lodash" => "4.17.21" }
        }.to_json
      end

      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: package_json_content,
            directory: "/"
          )
        ]
      end

      before do
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: Dependabot::DependencyFile.new(
            name: "pnpm-lock.yaml",
            content: "",
            directory: "/"
          )
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "detects pnpm as the package manager" do
        expect(grapher.send(:detected_package_manager)).to eq("pnpm")
      end
    end
  end

  describe "purl generation" do
    let(:dependency_files) { project_dependency_files("grapher/npm_with_lockfile") }

    it "uses 'npm' as the purl type" do
      resolved_dependencies = grapher.resolved_dependencies

      resolved_dependencies.each_key do |purl|
        expect(purl).to start_with("pkg:npm/")
      end
    end

    context "with scoped packages" do
      let(:package_json_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "dependencies" => { "@scope/package" => "1.0.0" }
        }.to_json
      end

      let(:package_lock_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "lockfileVersion" => 3,
          "packages" => {
            "" => {
              "name" => "test",
              "version" => "1.0.0",
              "dependencies" => { "@scope/package" => "1.0.0" }
            },
            "node_modules/@scope/package" => {
              "version" => "1.0.0",
              "resolved" => "https://registry.npmjs.org/@scope/package/-/package-1.0.0.tgz"
            }
          }
        }.to_json
      end

      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: package_json_content,
            directory: "/"
          ),
          Dependabot::DependencyFile.new(
            name: "package-lock.json",
            content: package_lock_content,
            directory: "/"
          )
        ]
      end

      it "URL-encodes the @ symbol in scoped package names" do
        resolved_dependencies = grapher.resolved_dependencies

        scoped_purl = resolved_dependencies.keys.find { |k| k.include?("scope") }
        expect(scoped_purl).to include("%40scope/package")
      end
    end
  end

  describe "registration" do
    it "is registered as the grapher for npm_and_yarn" do
      grapher_class = Dependabot::DependencyGraphers.for_package_manager("npm_and_yarn")
      expect(grapher_class).to eq(described_class)
    end
  end
end
