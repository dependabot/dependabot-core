# frozen_string_literal: true

require 'spec_helper'
require 'dependabot/spm/file_fetcher'
require_common_spec 'file_fetchers/shared_examples_for_file_fetchers'

RSpec.describe Dependabot::Spm::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  
end
