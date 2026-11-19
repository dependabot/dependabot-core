# typed: true
# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "time"
require "webrick"

# Serve fixed package metadata and an empty audit report to real npm subprocesses. Ruby HTTP
# stubs cannot intercept those requests, so use a loopback server instead of the public registry.
#
# The newest version is published a day before the registry starts so that release-age gates
# have something to filter: a gate of a few days excludes it, while no gate (or 0) admits it.
class NpmRegistry
  PACKAGE = "acorn"
  OLD_VERSION = "5.5.3"
  STABLE_VERSION = "5.7.4"
  FRESH_VERSION = "5.7.5"
  FRESH_VERSION_AGE_SECONDS = 24 * 60 * 60

  attr_reader :url
  attr_reader :requests

  def initialize
    @requests = []
    @versions = {
      OLD_VERSION => "2018-02-23T12:00:00.000Z",
      STABLE_VERSION => "2018-12-24T12:00:00.000Z",
      FRESH_VERSION => Time.at(Time.now.to_i - FRESH_VERSION_AGE_SECONDS).utc.iso8601(3)
    }
    @server = WEBrick::HTTPServer.new(
      BindAddress: "127.0.0.1", Port: 0, AccessLog: [], Logger: WEBrick::Log.new(File::NULL, 7)
    )
    @url = "http://127.0.0.1:#{@server[:Port]}"
    @server.mount_proc "/" do |request, response|
      @requests << "#{request.request_method} #{request.path}"
      status, body = registry_response(request)
      response.status = status
      response["Content-Type"] = "application/json"
      response.body = body
    end
    @thread = Thread.new { @server.start }
  end

  def tarball_url(version)
    "#{url}/#{PACKAGE}/-/#{PACKAGE}-#{version}.tgz"
  end

  def integrity(version)
    "sha512-#{Base64.strict_encode64(Digest::SHA512.digest("#{PACKAGE}@#{version}"))}"
  end

  def close
    @server.shutdown
    @thread.join
  end

  private

  def registry_response(request)
    if request.path == "/#{PACKAGE}"
      [200, JSON.generate(packument)]
    elsif request.request_method == "POST" && request.path.end_with?("/-/npm/v1/security/advisories/bulk")
      [200, "{}"]
    else
      [404, "{}"]
    end
  end

  def packument
    {
      "name" => PACKAGE,
      "dist-tags" => { "latest" => FRESH_VERSION },
      "versions" => @versions.keys.to_h { |version| [version, version_metadata(version)] },
      "time" => { "created" => @versions.values.first, "modified" => @versions.values.last }.merge(@versions)
    }
  end

  def version_metadata(version)
    {
      "name" => PACKAGE,
      "version" => version,
      "dist" => {
        "tarball" => tarball_url(version),
        "integrity" => integrity(version),
        "shasum" => Digest::SHA1.hexdigest("#{PACKAGE}@#{version}")
      }
    }
  end
end
