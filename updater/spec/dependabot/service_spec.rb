# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/api_client"
require "dependabot/dependency"
require "dependabot/dependency_change"
require "dependabot/dependency_file"
require "dependabot/dependency_snapshot"
require "dependabot/errors"
require "dependabot/pull_request_creator"
require "dependabot/service"
require "dependabot/experiments"

RSpec.describe Dependabot::Service do
  subject(:service) { described_class.new(client: mock_client) }

  let(:base_sha) { "mock-sha" }

  let(:mock_client) do
    api_client = instance_double(Dependabot::ApiClient, {
      create_pull_request: nil,
      update_pull_request: nil,
      close_pull_request: nil,
      record_update_job_error: nil,
      record_update_job_unknown_error: nil
    })
    allow(api_client).to receive(:is_a?).with(Dependabot::ApiClient).and_return(true)
    api_client
  end

  shared_context :a_pr_was_created do
    let(:source) do
      instance_double(Dependabot::Source, provider: "github", repo: "dependabot/dependabot-core", directory: "/")
    end

    let(:job) do
      instance_double(Dependabot::Job,
                      source: source,
                      credentials: [],
                      commit_message_options: [],
                      ignore_conditions: [])
    end

    let(:dependency_change) do
      Dependabot::DependencyChange.new(
        job: job,
        updated_dependencies: dependencies,
        updated_dependency_files: dependency_files
      )
    end

    let(:pr_message) { "update all the things" }
    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "dependabot-fortran",
          package_manager: "bundler",
          version: "1.8.0",
          previous_version: "1.7.0",
          requirements: [
            { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
          ],
          previous_requirements: [
            { file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }
          ]
        ),
        Dependabot::Dependency.new(
          name: "dependabot-pascal",
          package_manager: "bundler",
          version: "2.8.0",
          previous_version: "2.7.0",
          requirements: [
            { file: "Gemfile", requirement: "~> 2.8.0", groups: [], source: nil }
          ],
          previous_requirements: [
            { file: "Gemfile", requirement: "~> 2.7.0", groups: [], source: nil }
          ]
        )
      ]
    end

    let(:dependency_files) do
      [
        { name: "Gemfile", content: "some gems" }
      ]
    end

    before do
      allow(Dependabot::PullRequestCreator::MessageBuilder)
        .to receive_message_chain(:new, :message).and_return(
          Dependabot::PullRequestCreator::Message.new(
            pr_name: "Test PR",
            pr_message: pr_message,
            commit_message: "Commit message"
          )
        )
    end
  end

  shared_context :a_pr_was_updated do
    let(:source) do
      instance_double(Dependabot::Source, provider: "github", repo: "dependabot/dependabot-core", directory: "/")
    end

    let(:job) do
      instance_double(Dependabot::Job,
                      source: source,
                      credentials: [],
                      commit_message_options: [],
                      ignore_conditions: [])
    end

    let(:dependency_change) do
      Dependabot::DependencyChange.new(
        job: job,
        updated_dependencies: dependencies,
        updated_dependency_files: dependency_files
      )
    end

    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "dependabot-cobol",
          package_manager: "bundler",
          version: "3.8.0",
          previous_version: "3.7.0",
          requirements: [
            { file: "Gemfile", requirement: "~> 3.8.0", groups: [], source: nil }
          ],
          previous_requirements: [
            { file: "Gemfile", requirement: "~> 3.7.0", groups: [], source: nil }
          ]
        )
      ]
    end

    let(:dependency_files) do
      [
        { name: "Gemfile", content: "some gems" }
      ]
    end

    before do
      service.update_pull_request(dependency_change, base_sha)
    end
  end

  shared_context :a_pr_was_closed do
    let(:dependency_name) { "dependabot-fortran" }
    let(:reason) { :dependency_removed }

    before do
      service.close_pull_request(dependency_name, reason)
    end
  end

  shared_context :an_error_was_reported do
    before do
      service.record_update_job_error(
        error_type: :epoch_error,
        error_details: {
          message: "What is fortran doing here?!"
        }
      )
    end
  end

  shared_context :a_dependency_error_was_reported do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "dependabot-cobol",
        package_manager: "bundler",
        version: "3.8.0",
        previous_version: "3.7.0",
        requirements: [
          { file: "Gemfile", requirement: "~> 3.8.0", groups: [], source: nil }
        ],
        previous_requirements: [
          { file: "Gemfile", requirement: "~> 3.7.0", groups: [], source: nil }
        ]
      )
    end

    before do
      service.record_update_job_error(
        error_type: :unknown_error,
        error_details: {
          message: "0001 Undefined error. Inform Technical Support"
        },
        dependency: dependency
      )
    end
  end

  describe "Instance methods delegated to @client" do
    {
      mark_job_as_processed: %w(mock_sha),
      record_ecosystem_versions: %w(mock_ecosystem_versions)
    }.each do |method, arguments|
      before { allow(mock_client).to receive(method) }

      it "delegates #{method}" do
        service.send(method, *arguments)

        expect(mock_client).to have_received(method).with(*arguments)
      end
    end

    it "delegates increment_metric" do
      allow(mock_client).to receive(:increment_metric)

      service.increment_metric("apples", tags: { green: 1, red: 2 })

      expect(mock_client).to have_received(:increment_metric).with("apples", tags: { green: 1, red: 2 })
    end
  end

  describe "#create_pull_request" do
    include_context :a_pr_was_created

    before do
      Dependabot::Experiments.register("dependency_change_validation", true)
    end

    it "delegates to @client" do
      service.create_pull_request(dependency_change, base_sha)

      expect(mock_client)
        .to have_received(:create_pull_request).with(dependency_change, base_sha)
    end

    it "memoizes a shorthand summary of the PR" do
      service.create_pull_request(dependency_change, base_sha)

      expect(service.pull_requests)
        .to eql([["dependabot-fortran ( from 1.7.0 to 1.8.0 ), dependabot-pascal ( from 2.7.0 to 2.8.0 )", :created]])
    end

    context "when the change is missing a previous version" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "dependabot-fortran",
            package_manager: "bundler",
            version: "1.8.0",
            requirements: [
              { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
            ],
            previous_requirements: [
              { file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }
            ]
          )
        ]
      end

      it "raises a MissingPreviousVersion error" do
        expect { service.create_pull_request(dependency_change, base_sha) }
          .to raise_error(Dependabot::Service::MissingPreviousVersion)
      end
    end

    context "when the change is missing a requirements change" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "dependabot-fortran",
            package_manager: "bundler",
            version: "1.8.0",
            previous_version: "1.7.0",
            requirements: [
              { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
            ],
            previous_requirements: [
              { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
            ]
          )
        ]
      end

      it "raises a MissingRequirementsChange error" do
        expect { service.create_pull_request(dependency_change, base_sha) }
          .to raise_error(Dependabot::Service::MissingRequirementsChange)
      end
    end
  end

  describe "#update_pull_request" do
    include_context :a_pr_was_updated

    it "delegates to @client" do
      expect(mock_client).to have_received(:update_pull_request).with(dependency_change, base_sha)
    end

    it "memoizes a shorthand summary of the PR" do
      expect(service.pull_requests).to eql([["dependabot-cobol ( from 3.7.0 to 3.8.0 )", :updated]])
    end
  end

  describe "#close_pull_request" do
    include_context :a_pr_was_closed

    it "delegates to @client" do
      expect(mock_client).to have_received(:close_pull_request).with(dependency_name, reason)
    end

    it "memoizes a shorthand summary of the reason for closing PRs for a dependency" do
      expect(service.pull_requests).to eql([["dependabot-fortran", "closed: dependency_removed"]])
    end
  end

  describe "#record_update_job_error" do
    include_context :an_error_was_reported

    it "delegates to @client" do
      expect(mock_client).to have_received(:record_update_job_error).with(
        {
          error_type: :epoch_error,
          error_details: {
            message: "What is fortran doing here?!"
          }
        }
      )
    end

    it "memoizes a shorthand summary of the error" do
      expect(service.errors).to eql([["epoch_error", nil]])
    end
  end

  describe "#capture_exception" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?).with(:record_update_job_unknown_error).and_return(true)
      allow(mock_client).to receive(:record_update_job_unknown_error)
    end

    let(:error) do
      Dependabot::DependabotError.new("Something went wrong")
    end

    it "does not delegate to the service if the record_update_job_unknown_error experiment is disabled" do
      allow(Dependabot::Experiments).to receive(:enabled?).with(:record_update_job_unknown_error).and_return(false)

      service.capture_exception(error: error)

      expect(mock_client)
        .not_to have_received(:record_update_job_unknown_error)
    end

    it "delegates error capture to the service" do
      service.capture_exception(error: error)

      expect(mock_client)
        .to have_received(:record_update_job_unknown_error)
        .with(
          error_type: "unknown_error",
          error_details: hash_including(
            Dependabot::ErrorAttributes::MESSAGE => "Something went wrong",
            Dependabot::ErrorAttributes::CLASS => "Dependabot::DependabotError"
          )
        )
    end

    it "extracts information from a job if provided" do
      job = OpenStruct.new(id: 1234, package_manager: "bundler", repo_private?: false, repo_owner: "foo")
      service.capture_exception(error: error, job: job)

      expect(mock_client)
        .to have_received(:record_update_job_unknown_error)
        .with(
          error_type: "unknown_error",
          error_details: hash_including(
            Dependabot::ErrorAttributes::CLASS => "Dependabot::DependabotError",
            Dependabot::ErrorAttributes::MESSAGE => "Something went wrong",
            Dependabot::ErrorAttributes::JOB_ID => job.id,
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => job.package_manager
          )
        )
    end

    it "extracts information from a dependency if provided" do
      dependency = Dependabot::Dependency.new(name: "lodash", requirements: [], package_manager: "npm_and_yarn")
      service.capture_exception(error: error, dependency: dependency)

      expect(mock_client)
        .to have_received(:record_update_job_unknown_error)
        .with(
          error_type: "unknown_error",
          error_details: hash_including(
            Dependabot::ErrorAttributes::MESSAGE => "Something went wrong",
            Dependabot::ErrorAttributes::CLASS => "Dependabot::DependabotError",
            Dependabot::ErrorAttributes::DEPENDENCIES => "lodash"
          )
        )
    end

    it "extracts information from a dependency_group if provided" do
      dependency_group = OpenStruct.new(name: "all-the-things")
      allow(dependency_group).to receive(:is_a?).with(Dependabot::DependencyGroup).and_return(true)
      service.capture_exception(error: error, dependency_group: dependency_group)

      expect(mock_client)
        .to have_received(:record_update_job_unknown_error)
        .with(
          error_type: "unknown_error",
          error_details: hash_including(
            Dependabot::ErrorAttributes::MESSAGE => "Something went wrong",
            Dependabot::ErrorAttributes::CLASS => "Dependabot::DependabotError",
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => "all-the-things"
          )
        )
    end
  end

  describe "#update_dependency_list" do
    let(:dependency_snapshot) do
      dependency_snapshot = instance_double(Dependabot::DependencySnapshot,
                                            all_dependencies: [
                                              Dependabot::Dependency.new(
                                                name: "dummy-pkg-a",
                                                package_manager: "bundler",
                                                version: "2.0.0",
                                                requirements: [
                                                  { file: "Gemfile", requirement: "~> 2.0.0", groups: [:default],
                                                    source: nil }
                                                ]
                                              ),
                                              Dependabot::Dependency.new(
                                                name: "dummy-pkg-b",
                                                package_manager: "bundler",
                                                version: "1.1.0",
                                                requirements: [
                                                  { file: "Gemfile", requirement: "~> 1.1.0", groups: [:default],
                                                    source: nil }
                                                ]
                                              )
                                            ],
                                            all_dependency_files: [
                                              Dependabot::DependencyFile.new(
                                                name: "Gemfile",
                                                content: fixture("bundler/original/Gemfile"),
                                                directory: "/"
                                              ),
                                              Dependabot::DependencyFile.new(
                                                name: "Gemfile.lock",
                                                content: fixture("bundler/original/Gemfile.lock"),
                                                directory: "/"
                                              )
                                            ])
      allow(dependency_snapshot).to receive(:is_a?).and_return(true)
      dependency_snapshot
    end

    let(:expected_dependency_payload) do
      [
        {
          name: "dummy-pkg-a",
          version: "2.0.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 2.0.0",
              groups: [:default],
              source: nil
            }
          ]
        },
        {
          name: "dummy-pkg-b",
          version: "1.1.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.1.0",
              groups: [:default],
              source: nil
            }
          ]
        }
      ]
    end
    let(:expected_file_paths) do
      ["/Gemfile", "/Gemfile.lock"]
    end

    it "extracts a payload from the DependencySnapshot and delegates to the client" do
      expect(mock_client).to receive(:update_dependency_list).with(expected_dependency_payload, expected_file_paths)

      service.update_dependency_list(dependency_snapshot: dependency_snapshot)
    end
  end

  describe "#noop?" do
    it "is true by default" do
      expect(service).to be_noop
    end

    it "is false if there has been an event" do
      service.record_update_job_error(
        error_type: :epoch_error,
        error_details: {
          message: "What is fortran doing here?!"
        }
      )

      expect(service).not_to be_noop
    end

    it "is false if there has been a pull request change" do
      service.close_pull_request("dependabot-cobol", "legacy code removed")

      expect(service).not_to be_failure
    end
  end

  describe "#failure?" do
    it "is false by default" do
      expect(service).not_to be_failure
    end

    it "is true if there has been an error" do
      service.record_update_job_error(
        error_type: :epoch_error,
        error_details: {
          message: "What is fortran doing here?!"
        }
      )

      expect(service).to be_failure
    end
  end

  describe "#summary" do
    context "when there were no service events" do
      it "is empty" do
        expect(service.summary).to be_nil
      end
    end

    context "when a pr was created" do
      include_context :a_pr_was_created

      it "includes the summary of the created PR" do
        service.create_pull_request(dependency_change, base_sha)

        expect(service.summary)
          .to include("created",
                      "dependabot-fortran ( from 1.7.0 to 1.8.0 ), dependabot-pascal ( from 2.7.0 to 2.8.0 )")
      end
    end

    context "when a pr was updated" do
      include_context :a_pr_was_updated

      it "includes the summary of the updated PR" do
        expect(service.summary)
          .to include("updated", "dependabot-cobol ( from 3.7.0 to 3.8.0 )")
      end
    end

    context "when a pr was closed" do
      include_context :a_pr_was_closed

      it "includes the summary of the closed PR" do
        expect(service.summary)
          .to include("closed: dependency_removed", "dependabot-fortran")
      end
    end

    context "when there was an error" do
      include_context :an_error_was_reported

      it "includes an error count" do
        expect(service.summary)
          .to include("Dependabot encountered '1' error(s) during execution")
      end

      it "includes an error summary" do
        expect(service.summary)
          .to include("epoch_error")
      end
    end

    context "when there was an dependency error" do
      include_context :a_dependency_error_was_reported

      it "includes an error count" do
        expect(service.summary)
          .to include("Dependabot encountered '1' error(s) during execution")
      end

      it "includes an error summary" do
        expect(service.summary)
          .to include("unknown_error")
        expect(service.summary)
          .to include("dependabot-cobol")
      end
    end

    context "when there was a mix of pr activity" do
      include_context :a_pr_was_updated
      include_context :a_pr_was_closed

      it "includes the summary of the updated PR" do
        expect(service.summary)
          .to include("updated", "dependabot-cobol ( from 3.7.0 to 3.8.0 )")
      end

      it "includes the summary of the closed PR" do
        expect(service.summary)
          .to include("closed: dependency_removed", "dependabot-fortran")
      end
    end

    context "when there was a mix of pr and error activity" do
      include_context :a_pr_was_created
      include_context :a_pr_was_closed
      include_context :an_error_was_reported
      include_context :a_dependency_error_was_reported

      before do
        service.create_pull_request(dependency_change, base_sha)
      end

      it "includes the summary of the created PR" do
        expect(service.summary)
          .to include("created",
                      "dependabot-fortran ( from 1.7.0 to 1.8.0 ), dependabot-pascal ( from 2.7.0 to 2.8.0 )")
      end

      it "includes the summary of the closed PR" do
        expect(service.summary)
          .to include("closed: dependency_removed", "dependabot-fortran")
      end

      it "includes an error count" do
        expect(service.summary)
          .to include("Dependabot encountered '2' error(s) during execution")
      end

      it "includes an error summary" do
        expect(service.summary)
          .to include("epoch_error")
        expect(service.summary)
          .to include("unknown_error")
        expect(service.summary)
          .to include("dependabot-fortran")
      end
    end
  end
end
