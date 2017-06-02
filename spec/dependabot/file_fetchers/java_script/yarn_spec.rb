# frozen_string_literal: true
require "dependabot/file_fetchers/java_script/yarn"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::JavaScript::Yarn do
  it_behaves_like "a dependency file fetcher"
end
