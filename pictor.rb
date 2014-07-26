#!/usr/bin/ruby

require 'erb'
require 'cgi'
require 'ostruct'
require 'openssl'
require 'base64'
require 'shellwords'
require 'json'

# TEMPLATES
PAGE_TEMPLATE = <<-ERB
<!DOCTYPE html>

<html>
  <head>
    <title>Pictor</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <script type="text/javascript>
      var files = JSON.parse(<%= images %>);

      function load = function(path) {
        var div = document.getElementById('pictures');
        div.innerHTML = '';

        while (images.length > 0) {
          var img = document.createElement('img');
          img.src = images.pop();
          div.appendChild(img);
        };
      }
    </script>

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
    <script type="text/javascript">
      load('/');
    </script>

    <div id="gallery">
    </div>

    <div id="explorer">
    </div>
  </body>
</html>
ERB

# Lib
class Context
  def self.create(data)
    OpenStruct.new(data).instance_eval { binding }
  end
end

class Renderer
  def self.render(template, locals = {})
    ERB.new(template).result(Context.create(locals))
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
    return unless ImageMagick.found? && Configuration.create_thumbnails
    @thumbnail ||= Thumbnail.create(@path)
  end

  def optimal_path
    @thumbnail ? @thumbnail.path : @path
  end

  private

  def should_resize?(path)
    Configuration.create_thumbnails
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

class ImageLister
  def images(path)
    {'/' => list(path)}
  end

  private

  def list(path)
    (Dir.entries(path) - %w(. ..)).map do |file|
      if File.directory?(file)
        {file => list(file)}
      else
        next unless file =~ Configuration.picture_extensions
        file
      end
    end.compact
  end
end


# CONFIG
Configuration = OpenStruct.new(
  picture_extensions: /\.(png|gif|jpg)$/,
  create_thumbnails: true
)

# MAIN
#


#images = ImageLister.new.images('/Users/bencemonus').to_json.inspect
images = ImageLister.new.images('.').to_json.inspect
cgi = CGI.new

output = Renderer.render(PAGE_TEMPLATE, images: images)

cgi.out { output }
