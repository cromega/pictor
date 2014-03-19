#!/usr/bin/ruby

require 'erb'
require 'cgi'
require 'ostruct'

# TEMPLATES
PAGE_TEMPLATE = <<-ERB
<DOCTYPE html>

<html>
  <head>
    <title>Pictor</title>
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

IMAGE_TEMPLATE = <<-ERB
<img src="<%= path %>" alt="<%= path %>" />
ERB



# CONFIG
PICTURE_EXTENSIONS = /\.(png|gif|jpg)$/



# MAIN

cgi = CGI.new

path = cgi.params['path'].first || '.'
pics = Dir.glob("#{path}/*").keep_if { |file| file =~ PICTURE_EXTENSIONS }

images = pics.map { |path| ERB.new(IMAGE_TEMPLATE).result(binding) }.join

context = OpenStruct.new(explorer: nil, content: images)
cgi.out { ERB.new(PAGE_TEMPLATE).result(context.instance_eval { binding }) }
