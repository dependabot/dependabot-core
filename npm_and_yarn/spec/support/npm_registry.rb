# typed: strict
# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "rubygems/package"
require "stringio"
require "time"
require "webrick"
require "zlib"

# Serve fixed package metadata and an empty audit report to real npm subprocesses. Ruby HTTP
# stubs cannot intercept those requests, so use a loopback server instead of the public registry.
#
# The newest version is published a day before the registry starts so that release-age gates
# have something to filter: a gate of a few days excludes it, while no gate (or 0) admits it.
class NpmRegistry
  extend T::Sig

  PACKAGE = "acorn"
  OLD_VERSION = "5.5.3"
  STABLE_VERSION = "5.7.4"
  FRESH_VERSION = "5.7.5"
  FRESH_VERSION_AGE_SECONDS = T.let(24 * 60 * 60, Integer)

  Manifest = T.type_alias { T::Hash[String, T.any(String, T::Hash[String, String])] }

  sig { returns(String) }
  attr_reader :url

  sig { returns(T::Array[String]) }
  attr_reader :requests

  sig { params(packages: T::Hash[String, T::Array[Manifest]]).void }
  def initialize(packages: {})
    @packages = packages
    @archives = T.let(package_archives(packages), T::Hash[String, String])
    @requests = T.let([], T::Array[String])
    @versions = T.let(
      {
        OLD_VERSION => "2018-02-23T12:00:00.000Z",
        STABLE_VERSION => "2018-12-24T12:00:00.000Z",
        FRESH_VERSION => Time.at(Time.now.to_i - FRESH_VERSION_AGE_SECONDS).utc.iso8601(3)
      },
      T::Hash[String, String]
    )
    @server = T.let(
      WEBrick::HTTPServer.new(
        BindAddress: "127.0.0.1", Port: 0, AccessLog: [], Logger: WEBrick::Log.new(File::NULL, 7)
      ),
      WEBrick::HTTPServer
    )
    @url = T.let("http://127.0.0.1:#{@server[:Port]}", String)
    @server.mount_proc "/" do |request, response|
      @requests << "#{request.request_method} #{request.path}"
      status, body = registry_response(request)
      response.status = status
      response["Content-Type"] = "application/json"
      response.body = body
    end
    @thread = T.let(Thread.new { @server.start }, Thread)
  end

  sig { params(version: String).returns(String) }
  def tarball_url(version)
    "#{url}/#{PACKAGE}/-/#{PACKAGE}-#{version}.tgz"
  end

  sig { params(version: String).returns(String) }
  def integrity(version)
    "sha512-#{Base64.strict_encode64(Digest::SHA512.digest("#{PACKAGE}@#{version}"))}"
  end

  sig { void }
  def close
    @server.shutdown
    @thread.join
  end

  private

  sig { params(packages: T::Hash[String, T::Array[Manifest]]).returns(T::Hash[String, String]) }
  def package_archives(packages)
    packages.flat_map do |name, manifests|
      manifests.map do |manifest|
        ["/#{name}/-/#{name.split('/').last}-#{manifest.fetch('version')}.tgz", package_archive(manifest)]
      end
    end.to_h
  end

  sig { params(request: WEBrick::HTTPRequest).returns([Integer, String]) }
  def registry_response(request)
    if @packages.any?
      custom_registry_response(request.path)
    elsif request.path == "/#{PACKAGE}"
      [200, JSON.generate(packument)]
    elsif request.request_method == "POST" && request.path.end_with?("/-/npm/v1/security/advisories/bulk")
      [200, "{}"]
    else
      [404, "{}"]
    end
  end

  sig { params(path: String).returns([Integer, String]) }
  def custom_registry_response(path)
    archive = @archives[path]
    return [200, archive] if archive

    name = URI.decode_www_form_component(path.delete_prefix("/"))
    manifests = @packages[name]
    return [404, "{}"] unless manifests

    versions = manifests.to_h do |manifest|
      version = T.cast(manifest.fetch("version"), String)
      archive_path = "/#{name}/-/#{name.split('/').last}-#{version}.tgz"
      dist = { "tarball" => "#{url}#{archive_path}", "shasum" => Digest::SHA1.hexdigest(@archives.fetch(archive_path)) }
      [version, manifest.merge("dist" => dist)]
    end
    [200, JSON.generate(
      "name" => name,
      "dist-tags" => { "latest" => versions.keys.max_by { |version| Gem::Version.new(version) } },
      "versions" => versions,
      "time" => versions.keys.to_h { |version| [version, "2018-01-01T00:00:00.000Z"] }
    )]
  end

  sig { params(manifest: Manifest).returns(String) }
  def package_archive(manifest)
    content = JSON.generate(manifest)
    tar = StringIO.new
    Gem::Package::TarWriter.new(tar) do |writer|
      writer.mkdir("package", 0o755)
      writer.add_file_simple("package/package.json", 0o644, content.bytesize) { |file| file.write(content) }
    end
    Zlib.gzip(tar.string)
  end

  sig { returns(T::Hash[String, Object]) }
  def packument
    {
      "name" => PACKAGE,
      "dist-tags" => { "latest" => FRESH_VERSION },
      "versions" => @versions.keys.to_h { |version| [version, version_metadata(version)] },
      "time" => { "created" => @versions.values.first, "modified" => @versions.values.last }.merge(@versions)
    }
  end

  sig { params(version: String).returns(T::Hash[String, Object]) }
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
