# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dependency_file_helpers"

require "dependabot/bundler"
require "dependabot/dependency_file"
require "dependabot/dependency_snapshot"
require "dependabot/job"

require "github_api/dependency_submission"
require "github_api/ecosystem_mapper"

RSpec.shared_examples "dependency_submission" do |empty|
  subject(:dependency_submission) do
    described_class.new(
      job_id: "9999",
      branch: branch,
      sha: sha,
      package_manager: "bundler",
      manifest_snapshots: [
        Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
          manifest_file: empty ? empty_file : lockfile,
          resolved_dependencies: empty ? {} : resolved_dependencies
        )
      ]
    )
  end

  let(:branch) { "main" }
  let(:sha) { "fake-sha" }

  let(:directory) { "/" }

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("bundler/original/Gemfile.lock"),
      directory: directory
    )
  end

  let(:empty_file) do
    Dependabot::DependencyFile.new(
      name: "",
      content: "",
      directory: directory
    )
  end

  let(:resolved_dependencies) do
    {
      "dummy-pkg-a" => Dependabot::DependencyGraphers::ResolvedDependency.new(
        package_url: "pkg:gem/dummy-pkg-a@2.0.0",
        direct: true,
        runtime: true,
        dependencies: []
      ),
      "dummy-pkg-b" => Dependabot::DependencyGraphers::ResolvedDependency.new(
        package_url: "pkg:gem/dummy-pkg-b@1.1.0",
        direct: false,
        runtime: false,
        dependencies: []
      )
    }
  end

  describe "::job_correlator" do
    [
      {
        context: "with a typical RubyGems project in directory root",
        directory: "/",
        expected_correlator: "dependabot-bundler"
      },
      {
        context: "with a RubyGems project in a subdirectory",
        directory: "ruby/backend-api/",
        expected_correlator: "dependabot-bundler-ruby-backend--api"
      },
      {
        context: "with mixed case in the file path",
        directory: "Ruby/backend-api/",
        expected_correlator: "dependabot-bundler-Ruby-backend--api"
      },
      # If we're given something pathologically long, we use a SHA256 to limit length
      {
        context: "with a RubyGems project in a pathological directory tree",
        directory: "lorem/ipsum/dolor/sit/amet/consectetur/adipiscing/elit/nunc/turpis/justo/" \
                   "maximus/ac/eleifend/sit/amet/malesuada/eu/nisi/donec/faucibus/lobortis/" \
                   "augue/vitae/venenatis/nunc/euismod/auctor/suspendisse/eget",
        expected_correlator: /dependabot-bundler-[a-fA-F0-9]{64}/
      }
    ].each do |tc|
      context tc[:context] do
        let(:directory) { tc[:directory] }

        it "uses the expected value for job.correlator" do
          payload = dependency_submission.payload

          expect(payload[:job][:correlator]).to match(tc[:expected_correlator])
        end
      end
    end
  end

  describe "payload" do
    it "generates submission metadata correctly" do
      payload = dependency_submission.payload

      # Check metadata
      expect(payload[:version]).to eq(described_class::SNAPSHOT_VERSION)
      expect(payload[:detector][:name]).to eq(described_class::SNAPSHOT_DETECTOR_NAME)
      expect(payload[:detector][:url]).to eq(described_class::SNAPSHOT_DETECTOR_URL)
      expect(payload[:detector][:version]).to eq(Dependabot::VERSION)
      expect(payload[:job][:correlator]).to eq("dependabot-bundler")
      expect(payload[:job][:id]).to eq("9999")

      # Check dependabot-specific metadata keys
      expect(payload[:metadata][:status]).to eql("ok")
      expect(payload[:metadata][:reason]).to be_nil
      expect(payload[:metadata][:scanned_manifest_path]).to eql("rubygems::/")
    end

    it "affixes to use the updater sha if available" do
      allow(Dependabot::Environment).to receive(:updater_sha).and_return("totally-legit-sha")

      payload = dependency_submission.payload

      expect(payload[:detector][:version]).to eq("#{Dependabot::VERSION}-totally-legit-sha")
    end

    it "generates git attributes correctly" do
      payload = dependency_submission.payload

      expect(payload[:sha]).to eq(sha)
      expect(payload[:ref]).to eql("refs/heads/main")
    end

    context "when given a symbolic reference for the job's branch" do
      let(:branch) { "refs/heads/release" }

      it "does not add an additional refs/heads/ prefix" do
        payload = dependency_submission.payload

        expect(payload[:sha]).to eq(sha)
        expect(payload[:ref]).to eql("refs/heads/release")
      end
    end

    context "when given a symbolic reference for the job's branch with a leading /" do
      let(:branch) { "/refs/heads/release" }

      it "removes the leading slash" do
        payload = dependency_submission.payload

        expect(payload[:sha]).to eq(sha)
        expect(payload[:ref]).to eql("refs/heads/release")
      end
    end

    it "generates a valid manifest list" do
      payload = dependency_submission.payload

      if dependency_submission.resolved_dependencies.empty?
        expect(payload[:manifests]).to be_empty
        next
      end

      # We only expect a lockfile to be returned
      expect(payload[:manifests].length).to eq(1)

      # Lockfile data is correct
      lockfile = payload[:manifests].fetch("/Gemfile.lock")
      expect(lockfile[:name]).to eq("/Gemfile.lock")
      expect(lockfile[:file][:source_location]).to eq("Gemfile.lock")

      # Ecosystem is mapped from the package manager
      expect(lockfile[:metadata][:ecosystem]).to eq("rubygems")

      # Blob OID matches the Git blob SHA-1 of the fixture file
      expect(lockfile[:metadata][:blob_oid]).to eq("1f21c435958a7c58ef0b4021e1f981017e6d49f2")

      # Resolved dependencies are correct
      expect(lockfile[:resolved].length).to eq(2)

      dependency1 = lockfile[:resolved]["dummy-pkg-a"]
      expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a@2.0.0")
      expect(dependency1[:relationship]).to eql("direct")
      expect(dependency1[:scope]).to eql("runtime")

      dependency2 = lockfile[:resolved]["dummy-pkg-b"]
      expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b@1.1.0")
      expect(dependency2[:relationship]).to eql("indirect")
      expect(dependency2[:scope]).to eql("development")
    end
  end
end

RSpec.describe GithubApi::DependencySubmission do
  include DependencyFileHelpers

  context "with resolved dependencies" do
    it_behaves_like "dependency_submission", false
  end

  context "without resolved dependencies" do
    it_behaves_like "dependency_submission", true
  end

  context "with a skipped status and a file fetch error reason" do
    subject(:dependency_submission) do
      described_class.new(
        job_id: "9999",
        branch: "main",
        sha: "fake-sha",
        package_manager: "bundler",
        manifest_snapshots: [
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: empty_file,
            resolved_dependencies: {}
          )
        ],
        status: described_class::SnapshotStatus::SKIPPED,
        reason: described_class::SKIPPED_REASON_FILE_FETCH_ERROR
      )
    end

    let(:empty_file) do
      Dependabot::DependencyFile.new(name: "", content: "", directory: "/broken")
    end

    it "surfaces the skipped status and reason in the payload metadata" do
      payload = dependency_submission.payload

      expect(payload[:manifests]).to be_empty
      expect(payload[:metadata][:status])
        .to eq(described_class::SnapshotStatus::SKIPPED.serialize)
      expect(payload[:metadata][:reason]).to eq("unable to fetch files")
    end
  end

  context "with a manifest file but no resolved dependencies" do
    subject(:dependency_submission) do
      described_class.new(
        job_id: "9999",
        branch: "main",
        sha: "fake-sha",
        package_manager: "bundler",
        manifest_snapshots: [
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: lockfile,
            resolved_dependencies: {}
          )
        ]
      )
    end

    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/original/Gemfile.lock"),
        directory: "/"
      )
    end

    it "still reports the manifest with an empty resolved collection" do
      payload = dependency_submission.payload

      expect(payload[:manifests].length).to eq(1)

      manifest = payload[:manifests].fetch("/Gemfile.lock")
      expect(manifest[:name]).to eq("/Gemfile.lock")
      expect(manifest[:file][:source_location]).to eq("Gemfile.lock")
      expect(manifest[:metadata][:ecosystem]).to eq("rubygems")
      expect(manifest[:resolved]).to be_empty
    end
  end

  context "with multiple manifest group snapshots for a single directory" do
    subject(:dependency_submission) do
      described_class.new(
        job_id: "9999",
        branch: "main",
        sha: "fake-sha",
        package_manager: "pip",
        manifest_snapshots: [
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: base_txt,
            resolved_dependencies: {
              "starlette" => Dependabot::DependencyGraphers::ResolvedDependency.new(
                package_url: "pkg:pypi/starlette@0.40.0", direct: true, runtime: true, dependencies: []
              )
            }
          ),
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: test_txt,
            resolved_dependencies: {
              "pytest" => Dependabot::DependencyGraphers::ResolvedDependency.new(
                package_url: "pkg:pypi/pytest@8.3.3", direct: true, runtime: false, dependencies: []
              )
            }
          )
        ]
      )
    end

    let(:base_txt) do
      Dependabot::DependencyFile.new(name: "base-requirements.txt", content: "starlette==0.40.0\n", directory: "/")
    end

    let(:test_txt) do
      Dependabot::DependencyFile.new(name: "test-requirements.txt", content: "pytest==8.3.3\n", directory: "/")
    end

    it "emits one manifest entry per snapshot, each with only its own dependencies" do
      manifests = dependency_submission.payload[:manifests]

      expect(manifests.keys).to contain_exactly("/base-requirements.txt", "/test-requirements.txt")

      expect(manifests.fetch("/base-requirements.txt")[:resolved].keys).to contain_exactly("starlette")
      expect(manifests.fetch("/test-requirements.txt")[:resolved].keys).to contain_exactly("pytest")
    end
  end

  context "when a root scan's representative manifest lives in a subdirectory that is also scanned independently" do
    subject(:root_scan_submission) do
      described_class.new(
        job_id: "9999",
        branch: "main",
        sha: "fake-sha",
        package_manager: "pip",
        manifest_snapshots: [
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: root_scan_manifest,
            resolved_dependencies: {}
          )
        ]
      )
    end

    let(:docs_scan_submission) do
      described_class.new(
        job_id: "9999",
        branch: "main",
        sha: "fake-sha",
        package_manager: "pip",
        manifest_snapshots: [
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: docs_scan_manifest,
            resolved_dependencies: {}
          )
        ]
      )
    end

    # A root ("/") scan whose first layer-primary manifest happens to live in "/docs" -
    # a legitimate outcome of layered manifest selection, not a bug in itself.
    let(:root_scan_manifest) do
      Dependabot::DependencyFile.new(name: "docs/requirements.txt", content: "", directory: "/")
    end

    # A separate job configured to scan the "/docs" directory directly.
    let(:docs_scan_manifest) do
      Dependabot::DependencyFile.new(name: "requirements.txt", content: "", directory: "/docs")
    end

    it "gives the two distinct scan directories distinct job.correlator values" do
      root_correlator = root_scan_submission.payload[:job][:correlator]
      docs_correlator = docs_scan_submission.payload[:job][:correlator]

      expect(root_correlator).to eq("dependabot-pip")
      expect(docs_correlator).to eq("dependabot-pip-docs")
      expect(root_correlator).not_to eq(docs_correlator)
    end

    it "matches the directory-derived scanned_manifest_path, which already disambiguates them" do
      expect(root_scan_submission.payload[:metadata][:scanned_manifest_path]).to eq("pypi::/")
      expect(docs_scan_submission.payload[:metadata][:scanned_manifest_path]).to eq("pypi::/docs")
    end
  end

  context "when scanning sibling directories whose names only differ by a slash or a dash" do
    subject(:svc_web_dash_submission) do
      described_class.new(
        job_id: "9999",
        branch: "main",
        sha: "fake-sha",
        package_manager: "pip",
        manifest_snapshots: [
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: svc_web_dash_manifest,
            resolved_dependencies: {}
          )
        ]
      )
    end

    let(:svc_web_slash_submission) do
      described_class.new(
        job_id: "9999",
        branch: "main",
        sha: "fake-sha",
        package_manager: "pip",
        manifest_snapshots: [
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: svc_web_slash_manifest,
            resolved_dependencies: {}
          )
        ]
      )
    end

    # "/svc-web" and "/svc/web" are different directories and should not sanitise to the same correlator.
    let(:svc_web_dash_manifest) do
      Dependabot::DependencyFile.new(name: "requirements.txt", content: "", directory: "/svc-web")
    end

    let(:svc_web_slash_manifest) do
      Dependabot::DependencyFile.new(name: "requirements.txt", content: "", directory: "/svc/web")
    end

    it "gives the two distinct scan directories distinct job.correlator values" do
      dash_correlator = svc_web_dash_submission.payload[:job][:correlator]
      slash_correlator = svc_web_slash_submission.payload[:job][:correlator]

      expect(dash_correlator).to eq("dependabot-pip-svc--web")
      expect(slash_correlator).to eq("dependabot-pip-svc-web")
      expect(dash_correlator).not_to eq(slash_correlator)
    end

    it "matches the directory-derived scanned_manifest_path, which already disambiguates them" do
      expect(svc_web_dash_submission.payload[:metadata][:scanned_manifest_path]).to eq("pypi::/svc-web")
      expect(svc_web_slash_submission.payload[:metadata][:scanned_manifest_path]).to eq("pypi::/svc/web")
    end
  end

  context "when the commit SHA is 64 characters (SHA-256 repo)" do
    subject(:dependency_submission) do
      described_class.new(
        job_id: "9999",
        branch: "main",
        sha: sha256_sha,
        package_manager: "bundler",
        manifest_snapshots: [
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: lockfile,
            resolved_dependencies: resolved_dependencies
          )
        ]
      )
    end

    let(:sha256_sha) { "a" * 64 }
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/original/Gemfile.lock"),
        directory: "/"
      )
    end
    let(:resolved_dependencies) do
      {
        "dummy-pkg-a" => Dependabot::DependencyGraphers::ResolvedDependency.new(
          package_url: "pkg:gem/dummy-pkg-a@2.0.0",
          direct: true,
          runtime: true,
          dependencies: []
        )
      }
    end

    it "uses SHA-256 for the blob OID" do
      manifest = dependency_submission.payload[:manifests].fetch("/Gemfile.lock")
      expect(manifest[:metadata][:blob_oid])
        .to eq("54bf0378f9dd16ad2b60250c6156132f3ec9232e85b6ef87958aa439e29a4cec")
    end
  end
end
