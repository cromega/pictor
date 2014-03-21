#!/usr/bin/ruby

require 'erb'
require 'cgi'
require 'ostruct'
require 'pathname'

# TEMPLATES
PAGE_TEMPLATE = <<-ERB
<!DOCTYPE html>

<html>
  <head>
    <title>Pictor</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <style type="text/css">
      .img-frame {
        width: 800px
      }
      img {
        width: 100%
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
  <a href="<%= url_base + dir %>"><%= dir %></a>
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



# MAIN

cgi = CGI.new
path = cgi.params['path'].first || '.'
file_entries = Dir.glob("#{path}/*")

# build explorer
directories = file_entries.select { |entry| File.directory? entry }.map { |dir| dir.split('/').last }

script_name = $0.split('/').last
url_base = "#{script_name}?path=#{path}/"
context = OpenStruct.new(directories: directories, url_base:url_base).instance_eval { binding }
explorer_source = ERB.new(EXPLORER_TEMPLATE).result(context)


#build picture list
images = file_entries.select { |entry| entry =~ PICTURE_EXTENSIONS }

context = OpenStruct.new(images: images).instance_eval { binding }
images_source = ERB.new(IMAGES_TEMPLATE).result(context)

context = OpenStruct.new(explorer: explorer_source, content: images_source).instance_eval { binding }
output = ERB.new(PAGE_TEMPLATE).result(context)

cgi.out { output }
