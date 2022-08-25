# frozen_string_literal: true

require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"

TMP_DIR_PATH = File.expand_path("../tmp", __dir__)

RSpec.shared_context "in a temporary bundler directory" do
  let(:project_name) { "gemfile" }

  let(:tmp_path) do
    FileUtils.mkdir_p(TMP_DIR_PATH) 
    dir = Dir.mktmpdir("native_helper_spec_", TMP_DIR_PATH)
    Pathname.new(dir).expand_path
  end

  before do
    project_dependency_files(project_name).each do |file|
      File.write(File.join(tmp_path, file[:name]), file[:content])
    end
  end

  def in_tmp_folder(&block)
    Dir.chdir(tmp_path, &block)
  end
end

RSpec.shared_context "without caching rubygems" do
  before do
    # Stub Bundler to stop it using a cached versions of Rubygems
    allow_any_instance_of(Bundler::CompactIndexClient::Updater).
      to receive(:etag_for).and_return("")
  end
end

RSpec.shared_context "stub rubygems compact index" do
  include_context "without caching rubygems"

  before do
    # Stub the Rubygems index
    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(
        status: 200,
        body: fixture("rubygems_responses", "index")
      )

    # Stub the Rubygems response for each dependency we have a fixture for
    fixtures =
      Dir[File.join("../../spec", "fixtures", "rubygems_responses", "info-*")]
    fixtures.each do |path|
      dep_name = path.split("/").last.gsub("info-", "")
      stub_request(:get, "https://index.rubygems.org/info/#{dep_name}").
        to_return(
          status: 200,
          body: fixture("rubygems_responses", "info-#{dep_name}")
        )
    end
  end
end
