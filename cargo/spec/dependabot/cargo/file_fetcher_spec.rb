# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Cargo::FileFetcher do
  let(:json_header) { { "content-type" => "application/json" } }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
    stub_request(:get, url + "Cargo.toml?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_cargo_manifest.json"),
        headers: json_header
      )

    stub_request(:get, url + "Cargo.lock?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_cargo_lockfile.json"),
        headers: json_header
      )

    stub_request(:get, url + ".cargo?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_cargo_dir.json"),
        headers: json_header
      )

    stub_request(:get, url + ".cargo/config.toml?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_cargo_config.json"),
        headers: json_header
      )
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
  end

  it_behaves_like "a dependency file fetcher"

  context "with a lockfile" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_lockfile.json"),
          headers: json_header
        )
    end

    it "fetches the Cargo.toml, Cargo.lock and Cargo config" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Cargo.lock Cargo.toml .cargo/config.toml))
    end
  end

  context "with a config file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_config.json"),
          headers: json_header
        )

      stub_request(:get, url + ".cargo?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_dir.json"),
          headers: json_header
        )

      stub_request(:get, url + ".cargo/config.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_config.json"),
          headers: json_header
        )
    end

    it "fetches the Cargo.toml, Cargo.lock, and config.toml" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Cargo.lock Cargo.toml .cargo/config.toml))
    end
  end

  context "with a config file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_config.json"),
          headers: json_header
        )

      stub_request(:get, url + ".cargo?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_dir.json"),
          headers: json_header
        )

      stub_request(:get, url + ".cargo/config.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_config.json"),
          headers: json_header
        )
    end

    it "fetches the Cargo.toml, Cargo.lock, and config.toml" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Cargo.lock Cargo.toml .cargo/config.toml))
    end
  end

  context "without a lockfile" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.lock?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404, headers: json_header)
    end

    it "fetches the Cargo.toml" do
      expect(file_fetcher_instance.files.map(&:name))
        .to eq(["Cargo.toml", ".cargo/config.toml"])
    end

    it "provides the Rust channel" do
      expect(file_fetcher_instance.ecosystem_versions).to eq(
        {
          package_managers: { "cargo" => "default" }
        }
      )
    end
  end

  context "with a rust-toolchain file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_toolchain.json"),
          headers: json_header
        )

      stub_request(:get, url + "rust-toolchain?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: JSON.dump({ content: Base64.encode64("nightly-2019-01-01") }),
          headers: json_header
        )
    end

    it "fetches the Cargo.toml and rust-toolchain" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Cargo.toml .cargo/config.toml rust-toolchain))
    end

    it "raises a DependencyFileNotParseable error" do
      expect { file_fetcher_instance.ecosystem_versions }.to raise_error(Dependabot::DependencyFileNotParseable)
    end
  end

  context "with a rust-toolchain.toml file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_toolchain.json").gsub("rust-toolchain", "rust-toolchain.toml"),
          headers: json_header
        )

      stub_request(:get, url + "rust-toolchain.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: JSON.dump({ content: Base64.encode64("[toolchain]\nchannel = \"1.2.3\"") }),
          headers: json_header
        )
    end

    it "fetches the Cargo.toml and rust-toolchain" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Cargo.toml .cargo/config.toml rust-toolchain))
    end

    it "provides the Rust channel" do
      expect(file_fetcher_instance.ecosystem_versions).to eq(
        {
          package_managers: { "cargo" => "1.2.3" }
        }
      )
    end
  end

  context "with a path dependency" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 200, body: parent_fixture, headers: json_header)
    end

    let(:parent_fixture) do
      fixture("github", "contents_cargo_manifest_path_deps.json")
    end

    context "when the workspace is fetchable" do
      before do
        stub_request(:get, url + "src/s3/Cargo.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200, body: path_dep_fixture, headers: json_header)
      end

      let(:path_dep_fixture) do
        fixture("github", "contents_cargo_manifest.json")
      end

      it "fetches the path dependency's Cargo.toml" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w(Cargo.toml .cargo/config.toml src/s3/Cargo.toml))
        expect(file_fetcher_instance.files.last.support_file?)
          .to be(true)
      end

      context "with a trailing slash in the path" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_path_deps_trailing_slash.json"
          )
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml .cargo/config.toml src/s3/Cargo.toml))
        end
      end

      context "with a blank path" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_path_deps_blank.json"
          )
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml .cargo/config.toml))
        end
      end

      context "when dealing with a target dependency" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_target_path_deps.json"
          )
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml .cargo/config.toml src/s3/Cargo.toml))
        end
      end

      context "when dealing with a replacement source" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_replacement_path.json")
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml .cargo/config.toml src/s3/Cargo.toml))
        end
      end

      context "when dealing with a patched source" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_patched_path.json")
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml .cargo/config.toml src/s3/Cargo.toml))
        end
      end

      context "when a git source is also specified" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_path_deps_alt_source.json")
        end

        before do
          stub_request(:get, url + "gen/photoslibrary1/Cargo.toml?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 200, body: path_dep_fixture, headers: json_header)
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml .cargo/config.toml gen/photoslibrary1/Cargo.toml))
        end
      end

      context "with a directory" do
        let(:source) do
          Dependabot::Source.new(
            provider: "github",
            repo: "gocardless/bump",
            directory: "my_dir/"
          )
        end

        let(:url) do
          "https://api.github.com/repos/gocardless/bump/contents/my_dir/"
        end

        before do
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/bump/" \
            "contents/my_dir?ref=sha"
          )
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_cargo_without_lockfile.json"),
              headers: json_header
            )
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml .cargo/config.toml src/s3/Cargo.toml))
          expect(file_fetcher_instance.files.map(&:path))
            .to match_array(%w(/my_dir/Cargo.toml /my_dir/.cargo/config.toml /my_dir/src/s3/Cargo.toml))
        end
      end

      context "when including another path dependency" do
        let(:path_dep_fixture) do
          fixture("github", "contents_cargo_manifest_path_deps.json")
        end

        before do
          stub_request(:get, url + "src/s3/src/s3/Cargo.toml?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_cargo_manifest.json"),
              headers: json_header
            )
        end

        it "fetches the nested path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(
              %w(Cargo.toml .cargo/config.toml src/s3/Cargo.toml src/s3/src/s3/Cargo.toml)
            )
        end
      end
    end

    context "when the workspace is not fetchable" do
      before do
        stub_request(:get, url + "src/s3/Cargo.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404, headers: json_header)
        stub_request(:get, url + "src/s3?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404, headers: json_header)
        stub_request(:get, url + "src?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404, headers: json_header)
      end

      it "raises a PathDependenciesNotReachable error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::PathDependenciesNotReachable) do |error|
            expect(error.dependencies).to eq(["src/s3/Cargo.toml"])
          end
      end

      context "when dealing with a replacement source" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_replacement_path.json")
        end

        it "raises a PathDependenciesNotReachable error" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::PathDependenciesNotReachable) do |error|
              expect(error.dependencies).to eq(["src/s3/Cargo.toml"])
            end
        end
      end

      context "when a git source is also specified" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_path_deps_alt_source.json")
        end

        before do
          stub_request(:get, url + "gen/photoslibrary1/Cargo.toml?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404, headers: json_header)
          stub_request(:get, url + "gen/photoslibrary1?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404, headers: json_header)
          stub_request(:get, url + "gen?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404, headers: json_header)
        end

        it "ignores that it can't fetch the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml .cargo/config.toml))
        end
      end
    end
  end

  context "with a workspace dependency" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 200, body: parent_fixture, headers: json_header)
    end

    let(:parent_fixture) do
      fixture("github", "contents_cargo_manifest_workspace_root.json")
    end

    context "when the workspace is fetchable" do
      before do
        stub_request(:get, url + "lib/sub_crate/Cargo.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200, body: child_fixture, headers: json_header)
      end

      let(:child_fixture) do
        fixture("github", "contents_cargo_manifest_workspace_child.json")
      end

      it "fetches the workspace dependency's Cargo.toml" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w(Cargo.toml .cargo/config.toml lib/sub_crate/Cargo.toml))
      end

      context "when specifying the dependency implicitly" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_workspace_implicit.json")
        end

        before do
          stub_request(:get, url + "src/s3/Cargo.toml?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 200, body: child_fixture, headers: json_header)
        end

        it "fetches the workspace dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml .cargo/config.toml src/s3/Cargo.toml))
          expect(file_fetcher_instance.files.map(&:support_file?))
            .to contain_exactly(false, true, false)
        end
      end

      context "when specifying the dependency as a path dependency as well" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_workspace_and_path_root.json"
          )
        end

        it "fetches the workspace dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(Cargo.toml lib/sub_crate/Cargo.toml .cargo/config.toml))
          expect(file_fetcher_instance.files.map(&:support_file?))
            .to contain_exactly(false, false, true)
        end
      end
    end

    context "when the workspace is not fetchable" do
      before do
        stub_request(:get, url + "lib/sub_crate/Cargo.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404, headers: json_header)
        # additional requests due to submodule searching
        stub_request(:get, url + "lib/sub_crate?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404, headers: json_header)
        stub_request(:get, url + "lib?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404, headers: json_header)
      end

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when the project is in a submodule" do
      before do
        # This file doesn't exist because sub_crate is a submodule, so returns a 404
        stub_request(:get, url + "lib/sub_crate/Cargo.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404, headers: json_header)
        # This returns type: submodule, we're in the common submodule logic now
        stub_request(:get, url + "lib/sub_crate?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200, headers: json_header, body: fixture("github", "contents_cargo_submodule.json"))
        # Attempt to find the Cargo.toml in the submodule's repo.
        submodule_root = "https://api.github.com/repos/runconduit/conduit"
        stub_request(:get, submodule_root + "/contents/?ref=453df4efd57f5e8958adf17d728520bd585c82c9")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200, headers: json_header, body: fixture("github", "contents_cargo_without_lockfile.json"))
        # Found it, so download it!
        stub_request(:get, submodule_root + "/contents/Cargo.toml?ref=453df4efd57f5e8958adf17d728520bd585c82c9 ")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200, headers: json_header, body: fixture("github", "contents_cargo_manifest.json"))
      end

      it "places the found Cargo.toml in the correct directories" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w(Cargo.toml .cargo/config.toml lib/sub_crate/Cargo.toml))
        expect(file_fetcher_instance.files.map(&:path))
          .to match_array(%w(/Cargo.toml /.cargo/config.toml /lib/sub_crate/Cargo.toml))
      end
    end

    context "when specifying a directory of packages" do
      let(:parent_fixture) do
        fixture("github", "contents_cargo_manifest_workspace_root_glob.json")
      end
      let(:child_fixture) do
        fixture("github", "contents_cargo_manifest_workspace_child.json")
      end
      let(:child_fixture2) do
        # This fixture also requires the first child as a path dependency,
        # so we're testing whether the first child gets fetched twice here, as
        # well as whether the second child gets fetched.
        fixture("github", "contents_cargo_manifest_workspace_child2.json")
      end

      before do
        stub_request(:get, url + "packages?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_cargo_packages.json"),
            headers: json_header
          )
        stub_request(:get, url + "packages/sub_crate/Cargo.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200, body: child_fixture, headers: json_header)
        stub_request(:get, url + "packages/sub_crate2/Cargo.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200, body: child_fixture2, headers: json_header)
      end

      it "fetches the workspace dependency's Cargo.toml" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(
            %w(Cargo.toml
               .cargo/config.toml
               packages/sub_crate/Cargo.toml
               packages/sub_crate2/Cargo.toml)
          )
        expect(file_fetcher_instance.files.map(&:type).uniq)
          .to eq(["file"])
      end

      context "with a glob that excludes some directories" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_workspace_root_partial_glob.json"
          )
        end

        before do
          stub_request(:get, url + "packages?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_cargo_packages_extra.json"),
              headers: json_header
            )
        end

        it "fetches the workspace dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(
              %w(Cargo.toml
                 .cargo/config.toml
                 packages/sub_crate/Cargo.toml
                 packages/sub_crate2/Cargo.toml)
            )
          expect(file_fetcher_instance.files.map(&:type).uniq)
            .to eq(["file"])
        end
      end
    end
  end

  context "with another workspace that uses excluded dependency" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 200, body: parent_fixture, headers: json_header)

      stub_request(:get, url + "member/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 200, body: member_fixture, headers: json_header)

      stub_request(:get, url + "excluded/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 200, body: excluded_fixture, headers: json_header)
    end

    let(:parent_fixture) do
      fixture("github", "contents_cargo_manifest_workspace_excluded_dependencies_root.json")
    end
    let(:member_fixture) do
      fixture("github", "contents_cargo_manifest_workspace_excluded_dependencies_member.json")
    end
    let(:excluded_fixture) do
      fixture("github", "contents_cargo_manifest_workspace_excluded_dependencies_excluded.json")
    end

    it "uses excluded dependency as a support file" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Cargo.toml member/Cargo.toml excluded/Cargo.toml .cargo/config.toml))
      expect(file_fetcher_instance.files.map(&:support_file?))
        .to contain_exactly(false, false, true, true)
    end
  end

  context "with a Cargo.toml that is unparseable" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_manifest_unparseable.json"),
          headers: json_header
        )
    end

    it "raises a DependencyFileNotParseable error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotParseable)
    end
  end

  context "without a Cargo.toml" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_python.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404, headers: json_header)
    end

    it "raises a DependencyFileNotFound error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a workspace root containing a path dependency to a member" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture(
            "github",
            "path_dependency_in_workspace_root",
            "contents_cargo_manifest_workspace.json"
          ),
          headers: json_header
        )
      stub_request(:get, url + "child/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture(
            "github",
            "path_dependency_in_workspace_root",
            "contents_cargo_manifest_child.json"
          ),
          headers: json_header
        )
    end

    it "fetches the dependencies successfully" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(.cargo/config.toml Cargo.toml child/Cargo.toml))
      expect(file_fetcher_instance.files.map(&:path))
        .to match_array(%w(/.cargo/config.toml /Cargo.toml /child/Cargo.toml))
    end
  end

  context "with a path dependency to a workspace member" do
    let(:root_url) do
      "https://api.github.com/repos/gocardless/bump/"
    end
    let(:url) do
      root_url + "contents/"
    end

    before do
      # No root Cargo.toml
      stub_request(:get, root_url + "Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404, headers: json_header)

      # Contents of these dirs aren't important
      stub_request(:get, root_url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "path_dependency_workspace_member", "contents_dir_detached_crate_success.json"),
          headers: json_header
        )
      stub_request(:get, /#{Regexp.escape(url)}detached_crate_(success|fail_1|fail_2)\?ref=sha/)
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "path_dependency_workspace_member", "contents_dir_detached_crate_success.json"),
          headers: json_header
        )

      # Ignoring any .cargo requests
      stub_request(:get, %r{#{Regexp.escape(url)}\w+/\.cargo\?ref=sha})
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404, headers: json_header)

      # All the manifest requests
      stub_request(:get, url + "detached_crate_fail_1/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture(
            "github",
            "path_dependency_workspace_member",
            "contents_cargo_manifest_detached_crate_fail_1.json"
          ),
          headers: json_header
        )
      stub_request(:get, url + "detached_crate_fail_2/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture(
            "github",
            "path_dependency_workspace_member",
            "contents_cargo_manifest_detached_crate_fail_2.json"
          ),
          headers: json_header
        )
      stub_request(:get, url + "detached_crate_success/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture(
            "github",
            "path_dependency_workspace_member",
            "contents_cargo_manifest_detached_crate_success.json"
          ),
          headers: json_header
        )
      stub_request(:get, url + "detached_workspace_member/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture(
            "github",
            "path_dependency_workspace_member",
            "contents_cargo_manifest_detached_workspace_member.json"
          ),
          headers: json_header
        )
      stub_request(:get, url + "incorrect_detached_workspace_member/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture(
            "github",
            "path_dependency_workspace_member",
            "contents_cargo_manifest_incorrect_detached_workspace_member.json"
          ),
          headers: json_header
        )
      stub_request(:get, url + "incorrect_workspace/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture(
            "github",
            "path_dependency_workspace_member",
            "contents_cargo_manifest_incorrect_workspace.json"
          ),
          headers: json_header
        )
      stub_request(:get, url + "workspace/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "path_dependency_workspace_member", "contents_cargo_manifest_workspace.json"),
          headers: json_header
        )
      stub_request(:get, url + "workspace/nested_one/nested_two/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture(
            "github",
            "path_dependency_workspace_member",
            "contents_cargo_manifest_workspace_nested_one_nested_two.json"
          ),
          headers: json_header
        )

      # nested_one dir has nothing of interest
      stub_request(:get, url + "workspace/nested_one?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 200, body: "[]", headers: json_header)
      stub_request(:get, url + "workspace/nested_one/Cargo.toml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404, headers: json_header)
    end

    context "with a resolvable workspace root" do
      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "gocardless/bump",
          directory: "detached_crate_success/"
        )
      end

      it "fetches the dependencies successfully" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(
            %w(
              Cargo.toml
              ../detached_workspace_member/Cargo.toml
              ../workspace/Cargo.toml
              ../workspace/nested_one/nested_two/Cargo.toml
            )
          )
        expect(file_fetcher_instance.files.map(&:path))
          .to match_array(
            %w(
              /detached_crate_success/Cargo.toml
              /detached_workspace_member/Cargo.toml
              /workspace/Cargo.toml
              /workspace/nested_one/nested_two/Cargo.toml
            )
          )
      end
    end

    context "with no workspace root via parent directory search" do
      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "gocardless/bump",
          directory: "detached_crate_fail_1/"
        )
      end

      it "fetches as many dependencies as possible, without erroring" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(
            %w(
              ../incorrect_workspace/Cargo.toml Cargo.toml
            )
          )
        expect(file_fetcher_instance.files.map(&:path))
          .to match_array(
            %w(
              /detached_crate_fail_1/Cargo.toml /incorrect_workspace/Cargo.toml
            )
          )
      end
    end

    context "with no workspace root via package.workspace key" do
      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "gocardless/bump",
          directory: "detached_crate_fail_2/"
        )
      end

      it "fetches as many dependencies as possible, without erroring" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(
            %w(
              ../incorrect_detached_workspace_member/Cargo.toml Cargo.toml
            )
          )
        expect(file_fetcher_instance.files.map(&:path))
          .to match_array(
            %w(
              /detached_crate_fail_2/Cargo.toml /incorrect_detached_workspace_member/Cargo.toml
            )
          )
      end
    end
  end

  describe "#expand_workspaces" do
    let(:file_fetcher_instance) do
      described_class.new(source: source, credentials: credentials)
    end
    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "test/repo",
        directory: "/"
      )
    end

    before do
      allow(file_fetcher_instance).to receive_messages(commit: "sha", directory: "")
    end

    context "when workspace path is a simple glob pattern" do
      it "expands workspace paths with wildcards" do
        allow(file_fetcher_instance).to receive(:repo_contents)
          .with(dir: "packages/", raise_errors: false)
          .and_return([
            OpenStruct.new(type: "dir", path: "packages/crate1"),
            OpenStruct.new(type: "dir", path: "packages/crate2"),
            OpenStruct.new(type: "file", path: "packages/README.md")
          ])

        result = file_fetcher_instance.send(:expand_workspaces, "packages/*")
        expect(result).to contain_exactly("packages/crate1", "packages/crate2")
      end
    end

    context "when workspace path is exactly '*'" do
      it "handles the edge case without throwing nil error" do
        allow(file_fetcher_instance).to receive(:repo_contents)
          .with(dir: "", raise_errors: false)
          .and_return([
            OpenStruct.new(type: "dir", path: "crate1"),
            OpenStruct.new(type: "dir", path: "crate2"),
            OpenStruct.new(type: "file", path: "README.md")
          ])

        result = file_fetcher_instance.send(:expand_workspaces, "*")
        expect(result).to match_array(%w(crate1 crate2))
      end
    end

    context "when workspace path starts with '*'" do
      it "handles paths that start with wildcard" do
        allow(file_fetcher_instance).to receive(:repo_contents)
          .with(dir: "", raise_errors: false)
          .and_return([
            OpenStruct.new(type: "dir", path: "test-crate"),
            OpenStruct.new(type: "dir", path: "prod-crate"),
            OpenStruct.new(type: "file", path: "README.md")
          ])

        result = file_fetcher_instance.send(:expand_workspaces, "*-crate")
        expect(result).to match_array(%w(test-crate prod-crate))
      end
    end

    context "when workspace path contains multiple wildcards" do
      it "handles multiple wildcards correctly" do
        allow(file_fetcher_instance).to receive(:repo_contents)
          .with(dir: "src/", raise_errors: false)
          .and_return([
            OpenStruct.new(type: "dir", path: "src/bin-crate-v1"),
            OpenStruct.new(type: "dir", path: "src/lib-crate-v2"),
            OpenStruct.new(type: "dir", path: "src/other")
          ])

        result = file_fetcher_instance.send(:expand_workspaces, "src/*-crate-*")
        expect(result).to contain_exactly("src/bin-crate-v1", "src/lib-crate-v2")
      end
    end

    context "when no directories match the pattern" do
      it "returns empty array when no matches found" do
        allow(file_fetcher_instance).to receive(:repo_contents)
          .with(dir: "nonexistent/", raise_errors: false)
          .and_return([])

        result = file_fetcher_instance.send(:expand_workspaces, "nonexistent/*")
        expect(result).to eq([])
      end
    end

    context "when workspace path has nested wildcards" do
      it "handles nested directory patterns" do
        allow(file_fetcher_instance).to receive(:repo_contents)
          .with(dir: "apps/", raise_errors: false)
          .and_return([
            OpenStruct.new(type: "dir", path: "apps/web/frontend"),
            OpenStruct.new(type: "dir", path: "apps/api/backend"),
            OpenStruct.new(type: "file", path: "apps/config.json")
          ])

        result = file_fetcher_instance.send(:expand_workspaces, "apps/*/frontend")
        expect(result).to contain_exactly("apps/web/frontend")
      end
    end
  end

  describe "#uses_workspace_dependencies?" do
    let(:file_fetcher_instance) do
      described_class.new(source: source, credentials: credentials)
    end

    context "when manifest has regular workspace dependencies" do
      let(:manifest_with_workspace_deps) do
        {
          "dependencies" => {
            "serde" => { "workspace" => true },
            "tokio" => "1.0"
          }
        }
      end

      it "returns true" do
        expect(file_fetcher_instance.send(:uses_workspace_dependencies?, manifest_with_workspace_deps)).to be(true)
      end
    end

    context "when manifest has dev workspace dependencies" do
      let(:manifest_with_dev_workspace_deps) do
        {
          "dev-dependencies" => {
            "criterion" => { "workspace" => true }
          }
        }
      end

      it "returns true" do
        expect(file_fetcher_instance.send(:uses_workspace_dependencies?, manifest_with_dev_workspace_deps)).to be(true)
      end
    end

    context "when manifest has build workspace dependencies" do
      let(:manifest_with_build_workspace_deps) do
        {
          "build-dependencies" => {
            "cc" => { "workspace" => true }
          }
        }
      end

      it "returns true" do
        expect(
          file_fetcher_instance.send(
            :uses_workspace_dependencies?,
            manifest_with_build_workspace_deps
          )
        ).to be(true)
      end
    end

    context "when manifest has target-specific workspace dependencies" do
      let(:manifest_with_target_workspace_deps) do
        {
          "target" => {
            "wasm32-unknown-unknown" => {
              "dependencies" => {
                "wasm-bindgen" => { "workspace" => true }
              }
            }
          }
        }
      end

      it "returns true" do
        expect(
          file_fetcher_instance.send(
            :uses_workspace_dependencies?,
            manifest_with_target_workspace_deps
          )
        ).to be(true)
      end
    end

    context "when manifest has no workspace dependencies" do
      let(:manifest_without_workspace_deps) do
        {
          "dependencies" => {
            "serde" => "1.0",
            "tokio" => "1.0"
          },
          "dev-dependencies" => {
            "criterion" => "0.4"
          }
        }
      end

      it "returns false" do
        expect(file_fetcher_instance.send(:uses_workspace_dependencies?, manifest_without_workspace_deps)).to be(false)
      end
    end

    context "when manifest is empty" do
      let(:empty_manifest) { {} }

      it "returns false" do
        expect(file_fetcher_instance.send(:uses_workspace_dependencies?, empty_manifest)).to be(false)
      end
    end
  end

  describe "workspace root fetching for workspace dependencies" do
    let(:file_fetcher_instance) do
      described_class.new(source: source, credentials: credentials)
    end

    describe "integration with fetch_workspace_files" do
      let(:workspace_member_file) do
        Dependabot::DependencyFile.new(
          name: "internal/Cargo.toml",
          content: "[package]\nname = \"internal\"\n\n[dependencies]\nanstyle = { workspace = true }\n"
        )
      end

      let(:workspace_root_file) do
        Dependabot::DependencyFile.new(
          name: "Cargo.toml",
          content: "[workspace]\nmembers = [\"internal\"]\n\n[workspace.dependencies]\nanstyle = \"1.0.8\"\n"
        )
      end

      before do
        allow(file_fetcher_instance).to receive(:find_workspace_root)
          .with(workspace_member_file)
          .and_return(workspace_root_file)
      end

      it "includes workspace root when workspace member uses workspace dependencies" do
        # Mock the workspace dependency paths from the root file
        allow(file_fetcher_instance).to receive(:workspace_dependency_paths_from_file)
          .with(workspace_root_file)
          .and_return(["internal/Cargo.toml"])

        # Mock the workspace dependency paths from the member file (recursive call)
        allow(file_fetcher_instance).to receive(:workspace_dependency_paths_from_file)
          .with(workspace_member_file)
          .and_return([])

        allow(file_fetcher_instance).to receive(:fetch_file_from_host)
          .with("internal/Cargo.toml", fetch_submodules: true)
          .and_return(workspace_member_file)

        # Mock the cargo_toml method call
        allow(file_fetcher_instance).to receive(:fetch_file_from_host)
          .with("Cargo.toml")
          .and_return(workspace_root_file)

        # Call the method under test
        result = file_fetcher_instance.send(
          :fetch_workspace_files,
          file: workspace_root_file,
          previously_fetched_files: []
        )

        # Should include both the workspace member and the workspace root
        expect(result.map(&:name)).to include("internal/Cargo.toml", "Cargo.toml")
      end
    end

    describe "integration with fetch_files" do
      let(:main_cargo_file) do
        Dependabot::DependencyFile.new(
          name: "Cargo.toml",
          content: "[package]\nname = \"test\"\n\n[dependencies]\nserde = { workspace = true }\n"
        )
      end

      let(:workspace_root_file) do
        Dependabot::DependencyFile.new(
          name: "../Cargo.toml",
          content: "[workspace]\nmembers = [\"test\"]\n\n[workspace.dependencies]\nserde = \"1.0\"\n"
        )
      end

      before do
        allow(file_fetcher_instance).to receive_messages(
          cargo_toml: main_cargo_file,
          cargo_lock: nil,
          cargo_config: nil,
          rust_toolchain: nil,
          fetch_path_dependency_and_workspace_files: []
        )
        allow(file_fetcher_instance).to receive(:find_workspace_root)
          .with(main_cargo_file)
          .and_return(workspace_root_file)
      end

      it "includes workspace root when main Cargo.toml uses workspace dependencies" do
        files = file_fetcher_instance.fetch_files

        expect(files.map(&:name)).to include("Cargo.toml", "../Cargo.toml")
      end
    end

    describe "integration with fetch_path_dependency_files" do
      let(:main_file) do
        Dependabot::DependencyFile.new(
          name: "Cargo.toml",
          content: "[package]\nname = \"main\"\n\n[dependencies]\ninternal = { path = \"../internal\" }\n"
        )
      end

      let(:path_dep_file) do
        Dependabot::DependencyFile.new(
          name: "../internal/Cargo.toml",
          content: "[package]\nname = \"internal\"\n\n[dependencies]\nserde = { workspace = true }\n"
        )
      end

      let(:workspace_root_file) do
        Dependabot::DependencyFile.new(
          name: "../Cargo.toml",
          content: "[workspace]\nmembers = [\"internal\"]\n\n[workspace.dependencies]\nserde = \"1.0\"\n"
        )
      end

      before do
        allow(file_fetcher_instance).to receive(:path_dependency_paths_from_file)
          .with(main_file)
          .and_return(["../internal/Cargo.toml"])

        # Mock for the path dependency file itself (no further path dependencies)
        allow(file_fetcher_instance).to receive(:path_dependency_paths_from_file)
          .with(path_dep_file)
          .and_return([])

        allow(file_fetcher_instance).to receive(:fetch_file_from_host)
          .with("../internal/Cargo.toml", fetch_submodules: true)
          .and_return(path_dep_file)

        # Mock workspace_member? to return true for our test case
        allow(file_fetcher_instance).to receive(:workspace_member?)
          .and_return(false)
        allow(file_fetcher_instance).to receive(:workspace_member?)
          .with(hash_including("dependencies" => hash_including("serde" => { "workspace" => true })))
          .and_return(true)

        allow(file_fetcher_instance).to receive(:find_workspace_root)
          .with(path_dep_file)
          .and_return(workspace_root_file)
      end

      it "includes workspace root when path dependency uses workspace dependencies" do
        result = file_fetcher_instance.send(
          :fetch_path_dependency_files,
          file: main_file,
          previously_fetched_files: []
        )

        # Should include the path dependency and its workspace root
        expect(result.map(&:name)).to include("../internal/Cargo.toml", "../Cargo.toml")
      end
    end
  end
end
