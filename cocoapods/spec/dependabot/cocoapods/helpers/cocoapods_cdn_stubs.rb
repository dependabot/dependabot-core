# frozen_string_literal: true

require 'spec_helper'

def stub_all_cocoapods_cdn_requests
  all_pods_url = "#{COCOAPODS_CDN_HOST}/all_pods.txt"
  stub_request(:get, all_pods_url)
    .to_return(status: 200, body: COCOAPODS_ALL_PODS)

  deprecated_specs_url = "#{COCOAPODS_CDN_HOST}/deprecated_podspecs.txt"
  stub_request(:get, deprecated_specs_url)
    .to_return(status: 200, body: COCOAPODS_DEPRECATED_SPECS)

  cocoapods_version_url = "#{COCOAPODS_CDN_HOST}/CocoaPods-version.yml"
  stub_request(:get, cocoapods_version_url)
    .to_return(status: 200, body: COCOAPODS_VERSION_YAML)

  cocoapods_version_url2 = "#{COCOAPODS_CDN_HOST}//CocoaPods-version.yml"
  stub_request(:get, cocoapods_version_url2)
    .to_return(status: 200, body: COCOAPODS_VERSION_YAML)

  stub_all_pods_versions_requests
  stub_all_spec_requests
end

private

COCOAPODS_CDN_HOST = 'https://cdn.cocoapods.org'

COCOAPODS_ALL_PODS = fixture('cocoapods', 'all_pods', 'all_pods.txt')
COCOAPODS_DEPRECATED_SPECS = fixture('cocoapods', 'podspecs',
                                     'deprecated_podspecs.txt')
COCOAPODS_VERSION_YAML = fixture('cocoapods', 'CocoaPods-version.yml')

FIXTURES_PATH = File.join('spec', 'fixtures', 'cocoapods')
ALL_VERSIONS_FILES = File.join(FIXTURES_PATH, 'all_pods',
                               'all_pods_versions_*.txt')
PODSPEC_FILES = File.join(FIXTURES_PATH, 'podspecs', '*.podspec.json')

def stub_all_pods_versions_requests
  Dir[ALL_VERSIONS_FILES].each do |file|
    versions_url = "#{COCOAPODS_CDN_HOST}/#{File.basename(file)}"
    stub_request(:get, versions_url)
      .to_return(status: 200, body: File.read(file))
  end
end

def stub_all_spec_requests
  spec_paths = {
    "Nimble-2.0.0": 'Specs/d/c/d/Nimble/2.0.0/Nimble.podspec.json',
    "Nimble-3.0.0": 'Specs/d/c/d/Nimble/3.0.0/Nimble.podspec.json',
    "Alamofire-3.0.1": 'Specs/d/a/2/Alamofire/3.0.1/Alamofire.podspec.json',
    "Alamofire-3.5.1": 'Specs/d/a/2/Alamofire/3.5.1/Alamofire.podspec.json',
    "Alamofire-4.5.0": 'Specs/d/a/2/Alamofire/4.5.0/Alamofire.podspec.json',
    "Alamofire-4.5.1": 'Specs/d/a/2/Alamofire/4.5.1/Alamofire.podspec.json',
    "Alamofire-4.6.0": 'Specs/d/a/2/Alamofire/4.6.0/Alamofire.podspec.json',
    "AlamofireImage-2.5.0":
        'Specs/8/0/a/AlamofireImage/2.5.0/AlamofireImage.podspec.json',
    "AlamofireImage-4.1.0":
        'Specs/8/0/a/AlamofireImage/4.1.0/AlamofireImage.podspec.json'
  }

  Dir[PODSPEC_FILES].each do |file|
    spec = File.basename(file, '.podspec.json')
    spec_path = spec_paths[spec.to_sym]
    versions_url = "#{COCOAPODS_CDN_HOST}/#{spec_path}"

    stub_request(:get, versions_url)
      .to_return(status: 200, body: File.read(file))
  end
end
