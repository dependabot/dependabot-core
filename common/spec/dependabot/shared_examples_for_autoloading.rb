# frozen_string_literal: true

require "spec_helper"

require "dependabot/file_fetchers/base"
require "dependabot/file_parsers/base"
require "dependabot/update_checkers/base"
require "dependabot/file_updaters/base"
require "dependabot/metadata_finders/base"
require "dependabot/utils"
require "dependabot/pull_request_creator/labeler"
require "dependabot/dependency"

RSpec.shared_examples "it registers the required classes" do |pckg_mngr|
  it "registers a file fetcher" do
    klass = Dependabot::FileFetchers.for_package_manager(pckg_mngr)
    expect(klass.ancestors).to include(Dependabot::FileFetchers::Base)
  end

  it "registers a file parser" do
    klass = Dependabot::FileParsers.for_package_manager(pckg_mngr)
    expect(klass.ancestors).to include(Dependabot::FileParsers::Base)
  end

  it "registers an update checker" do
    klass = Dependabot::UpdateCheckers.for_package_manager(pckg_mngr)
    expect(klass.ancestors).to include(Dependabot::UpdateCheckers::Base)
  end

  it "registers a file updater" do
    klass = Dependabot::FileUpdaters.for_package_manager(pckg_mngr)
    expect(klass.ancestors).to include(Dependabot::FileUpdaters::Base)
  end

  it "registers a metadata finder" do
    klass = Dependabot::MetadataFinders.for_package_manager(pckg_mngr)
    expect(klass.ancestors).to include(Dependabot::MetadataFinders::Base)
  end

  it "registers a version class" do
    klass = Dependabot::Utils.version_class_for_package_manager(pckg_mngr)
    expect(klass.ancestors).to include(Gem::Version)
  end

  it "registers a requirement class" do
    klass = Dependabot::Utils.requirement_class_for_package_manager(pckg_mngr)
    expect(klass.ancestors).to include(Gem::Requirement)
  end

  it "registers its label details" do
    expect(
      Dependabot::PullRequestCreator::Labeler.
        label_details_for_package_manager(pckg_mngr)
    ).to be_a(Hash)
  end

  it "registers its production check" do
    expect(
      Dependabot::Dependency.production_check_for_package_manager(pckg_mngr)
    ).to be_a(Proc)
  end
end
