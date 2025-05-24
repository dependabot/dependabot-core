require "rspec"
require "webmock/rspec"
require "vcr"

require "dependabot/julia"

RSpec.configure do |config|
  config.include WebMock::API

  config.before(:suite) do
    WebMock.enable!
  end

  config.before(:each) do
    # Stub Julia registry
    stub_request(:get, /github.com\/JuliaRegistries\/General/)
      .to_return(
        status: 200,
        body: fixture("registry_responses", "General.toml"),
      )
  end
end

def fixture(*args)
  File.read(
    File.join("spec", "fixtures", "julia", *args)
  )
end

RSpec.describe Dependabot::Julia do
  it_behaves_like "a dependabot ecosystem module"
end

def project_dependency_files(project_name)
  project_path = File.join("spec", "fixtures", "projects", project_name)
  Dir.children(project_path).map do |file_name|
    full_path = File.join(project_path, file_name)
    content = File.read(full_path)

    Dependabot::DependencyFile.new(
      name: file_name,
      content: content,
      directory: "/"
    )
  end
end
