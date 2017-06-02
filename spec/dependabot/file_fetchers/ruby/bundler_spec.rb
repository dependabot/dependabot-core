# frozen_string_literal: true
require "dependabot/file_fetchers/ruby/bundler"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Ruby::Bundler do
  it_behaves_like "a dependency file fetcher"
end
