# typed: false
# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "rubygems/package"
require "stringio"
require "webrick"
require "zlib"

# Serve signed, minimal pnpm packages to real Corepack subprocesses. Ruby HTTP
# stubs cannot intercept those requests, so use a loopback server and fresh keys.
class CorepackRegistry
  VERSIONS = %w(10.0.0 10.1.0 11.0.0).freeze

  attr_reader :url
  attr_reader :requests

  def initialize(signatures: :root)
    @signatures = signatures
    @key = OpenSSL::PKey::EC.generate("prime256v1")
    @archives = VERSIONS.to_h { |version| [version, package_archive(version)] }
    @requests = []
    @server = WEBrick::HTTPServer.new(
      BindAddress: "127.0.0.1", Port: 0, AccessLog: [], Logger: WEBrick::Log.new(File::NULL, 7)
    )
    @url = "http://127.0.0.1:#{@server[:Port]}"
    @server.mount_proc "/pnpm" do |request, response|
      @requests << request.path
      status, content_type, body = registry_response(request.path)
      response.status = status
      response["Content-Type"] = content_type
      response.body = body
    end
    @thread = Thread.new { @server.start }
  end

  def integrity_keys
    JSON.generate("npm" => [{ "keyid" => "SHA256:corepack-test", "key" => Base64.strict_encode64(@key.public_to_der) }])
  end

  def close
    @server.shutdown
    @thread.join
  end

  private

  def package_archive(version)
    extension = version.start_with?("11.") ? "mjs" : "cjs"
    contents = {
      "package/package.json" => JSON.generate("name" => "pnpm", "version" => version),
      "package/bin/pnpm.#{extension}" => "console.log(#{version.to_json});\n"
    }
    tar = StringIO.new
    Gem::Package::TarWriter.new(tar) do |writer|
      writer.mkdir("package", 0o755)
      writer.mkdir("package/bin", 0o755)
      contents.each do |path, content|
        writer.add_file_simple(path, 0o644, content.bytesize) { |file| file.write(content) }
      end
    end
    Zlib.gzip(tar.string)
  end

  def metadata(version, root: false)
    integrity = "sha512-#{Base64.strict_encode64(OpenSSL::Digest::SHA512.digest(@archives.fetch(version)))}"
    dist = { "tarball" => "#{url}/pnpm/-/pnpm-#{version}.tgz", "integrity" => integrity }
    if root && @signatures != :none
      payload = @signatures == :invalid ? "invalid" : "pnpm@#{version}:#{integrity}"
      signature = Base64.strict_encode64(@key.sign("SHA256", payload))
      dist["signatures"] = [{ "keyid" => "SHA256:corepack-test", "sig" => signature }]
    end
    { "name" => "pnpm", "version" => version, "dist" => dist }
  end

  def registry_response(path)
    if path == "/pnpm"
      versions = VERSIONS.to_h { |version| [version, metadata(version, root: true)] }
      [200, "application/json", JSON.generate("versions" => versions)]
    elsif (version = VERSIONS.find { |candidate| path == "/pnpm/#{candidate}" })
      [200, "application/json", JSON.generate(metadata(version))]
    elsif (version = VERSIONS.find { |candidate| path == "/pnpm/-/pnpm-#{candidate}.tgz" })
      [200, "application/octet-stream", @archives.fetch(version)]
    else
      [404, "application/json", "{}"]
    end
  end
end
