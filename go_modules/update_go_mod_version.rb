require 'net/http'
require 'json'

GO_VERSIONS_URL = 'https://go.dev/dl/?mode=json'

def get_go_version_from_go_mod_file(file_path)
  go_version=""

  if File.exist?(file_path)
    File.readlines(file_path).each do |line|
      version_regex = /^(go\s)([\d+\.]+)$/

      match_data = line.match(version_regex)

      if match_data
        extracted_version = match_data[2]
        go_version=extracted_version
      end
    end
  else
    puts "File not found: #{file_path}"
  end

  return go_version
end


def get_latest_go_version()
  major, minor, patch = "","",""

  url = URI.parse(GO_VERSIONS_URL)

  response = Net::HTTP.get(url)
  data = JSON.parse(response)

  latest_version = data[0]['version']
  puts latest_version

  version_regex = /go(\d+)\.(\d+)\.(\d+)/

  match_data = latest_version.match(version_regex)

  if match_data
    major = match_data[1]
    minor = match_data[2]
    patch = match_data[3]
  else
    puts "No version found in the input string."
  end

  return major, minor, patch
end

if __FILE__ == $0
  current_go_mod_version = get_go_version_from_go_mod_file('go_modules/helpers/go.mod')
  major, minor, patch = get_latest_go_version

  if current_go_mod_version =~ /(\.\d+){2}$/
    p "The current_go_mod_version consists of a major, minor and patch version: #{current_go_mod_version}"
    p "and will be updated to: #{major}.#{minor}.#{patch}"
  elsif current_go_mod_version =~ /(\.\d+){1}$/
    p "The current_go_mod_version consists of a major and minor version: #{current_go_mod_version}"
    p "and will be updated to: #{major}.#{minor}"
  else
    p "the go version only contains a major version"
  end
end
