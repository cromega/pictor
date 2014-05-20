#!/usr/bin/ruby

require 'erb'
require 'cgi'
require 'ostruct'
require 'openssl'
require 'base64'
require 'shellwords'

# TEMPLATES
PAGE_TEMPLATE = <<-ERB
<!DOCTYPE html>

<html>
  <head>
    <title>Pictor</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <style type="text/css">
      #pictures div {
        width: 400px;
        margin: 10px;
      }
      img {
        padding: 10px;
        height: auto;
        max-width: 380px;
        border: 1px solid gray;
      }
      #explorer {
        position: fixed;
        left: 500px;
        border: 1px solid gray;
      }
      #explorer a {
        padding: 5px;
        display: block;
        text-decoration: none;
        color: gray;
      }
      #explorer a:hover {
        color: red;
      }
    </style>
  </head>

  <body>
    <div id="explorer">
      <%= explorer %>
    </div>

    <div id="pictures">
      <%= content %>
    </div>
  </body>
</html>
ERB

EXPLORER_TEMPLATE = <<-ERB
<% directories.each do |dir| %>
  <a href="<%= url_base + dir.encoded_path %>">&gt; <%= dir.name %></a>
<% end %>
ERB

IMAGES_TEMPLATE = <<-ERB
<% images.each do |image| %>
  <div class="img-frame">
    <a href="<%= image.path %>" target="_blank">
      <img src="<%= image.optimal_path %>" alt="<%= image.optimal_path %>" />
    </a>
  </div>
<% end %>
ERB

# Lib
class Context
  def self.create(data)
    OpenStruct.new(data).instance_eval { binding }
  end
end

class Cipher
  def self.encrypt(data)
    cipher = OpenSSL::Cipher::AES256.new(:CBC)
    cipher.encrypt
    iv = cipher.random_iv
    cipher.key = Configuration.encryption_token
    encoded = cipher.update(data) + cipher.final
    [encoded, iv]
  end

  def self.decrypt(data, iv)
    cipher = OpenSSL::Cipher::AES256.new(:CBC)
    cipher.decrypt
    cipher.iv = iv
    cipher.key = Configuration.encryption_token
    cipher.update(data) + cipher.final
  end
end

class Directory
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def encoded_path
    encoded, iv = Cipher.encrypt(@name)
    [encoded, iv].map { |param| Base64::strict_encode64(param) }.map { |param| CGI::escape(param) }.join(',')
  end

  def self.decode_path(raw)
    data, iv = raw.split(',').map { |param| Base64::decode64(param) }
    name = Cipher.decrypt(data, iv)
    new(name)
  end
end

class ImageMagick
  def initialize(src, out)
    @src = src
    @out = out
    @operations = []
  end

  def <<(operation)
    @operations << operation
  end

  def run
    system(cmdline)
    $? == 0
  end

  def self.found?
    `which convert`
    $? == 0
  end

  private

  def cmdline
    operations = @operations.join(' ')
    "convert #{operations} #{Shellwords.escape(@src)} #{Shellwords.escape(@out)}"
  end
end

class Image
  attr_reader :path

  def initialize(path)
    @path = path
  end

  def thumbnail
    return unless Configuration.create_thumbnails && ImageMagick.found?
    @thumbnail ||= Thumbnail.create(@path)
  end

  def optimal_path
    @thumbnail ? @thumbnail.path : @path
  end
end

class Thumbnail
  attr_reader :path

  def initialize(path)
    @path = path
  end

  def self.create(path)
    dir = "#{File.dirname(path)}/.pictor"
    filename = File.basename(path)
    Dir.mkdir(dir) unless File.directory?(dir)
    thumbnail_path = "#{dir}/#{filename}"

    # the thumbnail exists and is up to date, no need for conversion
    if File.exists?(thumbnail_path) && File.ctime(path) <= File.ctime(thumbnail_path)
      return new(thumbnail_path)
    end

    convert = ImageMagick.new(path, thumbnail_path)
    convert << '-scale 380'
    success = convert.run

    raise "converting picture failed" unless success
    new(thumbnail_path)
  end
end

# CONFIG
Configuration = OpenStruct.new(
  picture_extensions: /\.(png|gif|jpg)$/,
  encryption_token: "super secret token" # at least 256 bits
  create_thumbnails: true,
)

# MAIN
cgi = CGI.new
param = cgi.params['path'].first
path = param ? Directory.decode_path(param).name : '.'

file_entries = Dir.glob("#{path}/*")

# build explorer
directories = file_entries.select { |entry| File.directory? entry }.map { |dir| dir.split('/').last }.map { |dir| Directory.new(dir) }

script_name = $0.split('/').last
url_base = "#{script_name}?path="
context = Context.create(directories: directories, url_base: url_base)
explorer_source = ERB.new(EXPLORER_TEMPLATE).result(context)


#build picture list
images = file_entries.select { |entry| entry =~ Configuration.picture_extensions }.map { |file| Image.new(file) }

context = Context.create(images: images)
images_source = ERB.new(IMAGES_TEMPLATE).result(context)

context = Context.create(explorer: explorer_source, content: images_source)
output = ERB.new(PAGE_TEMPLATE).result(context)

cgi.out { output }
