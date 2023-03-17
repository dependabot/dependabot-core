# frozen_string_literal: true

require "spec_helper"
require "dependabot/api_client"
require "dependabot/dependency_change"
require "dependabot/service"

RSpec.describe Dependabot::Service do
  let(:base_sha) { "mock-sha" }

  let(:mock_client) do
    instance_double(Dependabot::ApiClient, {
      create_pull_request: nil,
      update_pull_request: nil,
      close_pull_request: nil,
      record_update_job_error: nil
    })
  end
  subject(:service) { described_class.new(client: mock_client) }

  shared_context :a_pr_was_created do
    let(:dependency_change) do
      Dependabot::DependencyChange.new(
        job: instance_double(Dependabot::Job, source: nil, credentials: [], commit_message_options: []),
        dependencies: dependencies,
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
      allow(Dependabot::PullRequestCreator::MessageBuilder).
        to receive_message_chain(:new, :message).and_return(pr_message)

      service.create_pull_request(dependency_change, base_sha)
    end
  end

  shared_context :a_pr_was_updated do
    let(:dependency_change) do
      Dependabot::DependencyChange.new(
        job: anything,
        dependencies: dependencies,
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
      update_dependency_list: %w(mock_dependencies mock_dependency_file),
      record_package_manager_version: %w(mock_ecosystem mock_package_managers)
    }.each do |method, arguments|
      before { allow(mock_client).to receive(method) }

      it "delegates #{method}" do
        service.send(method, *arguments)

        expect(mock_client).to have_received(method).with(*arguments)
      end
    end
  end

  describe "#create_pull_request" do
    include_context :a_pr_was_created

    it "delegates to @client" do
      expect(mock_client).
        to have_received(:create_pull_request).with(dependency_change, base_sha)
    end

    it "memoizes a shorthand summary of the PR" do
      expect(service.pull_requests).
        to eql([["dependabot-fortran ( from 1.7.0 to 1.8.0 ), dependabot-pascal ( from 2.7.0 to 2.8.0 )", :created]])
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
        expect(service.summary).
          to include("created", "dependabot-fortran ( from 1.7.0 to 1.8.0 ), dependabot-pascal ( from 2.7.0 to 2.8.0 )")
      end
    end

    context "when a pr was updated" do
      include_context :a_pr_was_updated

      it "includes the summary of the updated PR" do
        expect(service.summary).
          to include("updated", "dependabot-cobol ( from 3.7.0 to 3.8.0 )")
      end
    end

    context "when a pr was closed" do
      include_context :a_pr_was_closed

      it "includes the summary of the closed PR" do
        expect(service.summary).
          to include("closed: dependency_removed", "dependabot-fortran")
      end
    end

    context "when there was an error" do
      include_context :an_error_was_reported

      it "includes an error count" do
        expect(service.summary).
          to include("Dependabot encountered '1' error(s) during execution")
      end

      it "includes an error summary" do
        expect(service.summary).
          to include("epoch_error")
      end
    end

    context "when there was an dependency error" do
      include_context :a_dependency_error_was_reported

      it "includes an error count" do
        expect(service.summary).
          to include("Dependabot encountered '1' error(s) during execution")
      end

      it "includes an error summary" do
        expect(service.summary).
          to include("unknown_error")
        expect(service.summary).
          to include("dependabot-cobol")
      end
    end

    context "when there was a mix of pr activity" do
      include_context :a_pr_was_updated
      include_context :a_pr_was_closed

      it "includes the summary of the updated PR" do
        expect(service.summary).
          to include("updated", "dependabot-cobol ( from 3.7.0 to 3.8.0 )")
      end

      it "includes the summary of the closed PR" do
        expect(service.summary).
          to include("closed: dependency_removed", "dependabot-fortran")
      end
    end

    context "when there was a mix of pr and error activity" do
      include_context :a_pr_was_created
      include_context :a_pr_was_closed
      include_context :an_error_was_reported
      include_context :a_dependency_error_was_reported

      it "includes the summary of the created PR" do
        expect(service.summary).
          to include("created", "dependabot-fortran ( from 1.7.0 to 1.8.0 ), dependabot-pascal ( from 2.7.0 to 2.8.0 )")
      end

      it "includes the summary of the closed PR" do
        expect(service.summary).
          to include("closed: dependency_removed", "dependabot-fortran")
      end

      it "includes an error count" do
        expect(service.summary).
          to include("Dependabot encountered '2' error(s) during execution")
      end

      it "includes an error summary" do
        expect(service.summary).
          to include("epoch_error")
        expect(service.summary).
          to include("unknown_error")
        expect(service.summary).
          to include("dependabot-fortran")
      end
    end
  end
end
