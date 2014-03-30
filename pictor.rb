#!/usr/bin/ruby

require 'erb'
require 'cgi'
require 'ostruct'
require 'openssl'
require 'base64'

# TEMPLATES
PAGE_TEMPLATE = <<-ERB
<!DOCTYPE html>

<html>
  <head>
    <title>Pictor</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <style type="text/css">
      #pictures div {
        width: 800px;
        margin: 10px;
      }
      img {
        padding: 10px;
        height: auto;
        max-width: 780px;
        border: 1px solid gray;
      }
      #explorer {
        position: fixed;
        left: 900px;
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
    <a href="<%= image %>" target="_blank">
      <img src="<%= image %>" alt="<%= image %>" />
    </a>
  </div>
<% end %>
ERB


# CONFIG
PICTURE_EXTENSIONS = /\.(png|gif|jpg)$/
ENCRYPTION_TOKEN = "super secret token" # at least 256 bits


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
    cipher.key = ENCRYPTION_TOKEN
    encoded = cipher.update(data) + cipher.final
    [encoded, iv]
  end

  def self.decrypt(data, iv)
    cipher = OpenSSL::Cipher::AES256.new(:CBC)
    cipher.decrypt
    cipher.iv = iv
    cipher.key = ENCRYPTION_TOKEN
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
images = file_entries.select { |entry| entry =~ PICTURE_EXTENSIONS }

context = Context.create(images: images)
images_source = ERB.new(IMAGES_TEMPLATE).result(context)

context = Context.create(explorer: explorer_source, content: images_source)
output = ERB.new(PAGE_TEMPLATE).result(context)

cgi.out { output }
