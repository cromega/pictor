#!/usr/bin/ruby

require 'erb'
require 'cgi'
require 'ostruct'
require 'json'

# TEMPLATES
PAGE_TEMPLATE = <<-HTML
<!DOCTYPE html>

<html>
  <head>
    <title>Pictor</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <script type="text/javascript">
      var Gallery = function(gallery, navigator) {
        var
          files,
          directory = [];

        var _update = function() {
          // load pictures
          gallery.innerHTML = '';

          var images = files.filter(function(file) {
            //we care about pictures that have enough directory depth
            if (file.length != directory.length + 1) { return false; }

            //and they are in the current parent directory
            return JSON.stringify(directory) == JSON.stringify(file.slice(0, -1));
          });

          images.forEach(function(file) {
            var div = document.createElement('div');
            div.className = 'img-frame';

            var a = document.createElement('a');
            a.href = file.join('/');

            var img = document.createElement('img');
            img.src = file;
            a.appendChild(img)
            div.appendChild(a);
            gallery.appendChild(div);
          });
        };

        return {
          load: function(data) {
            files = data;
            directory = [];
            _update();
          },
          update: _update,
          up: function() {
            directory.pop();
            _update();
          }
        };
      };

      window.onload = function() {
        var container = document.getElementById('gallery');
        var navigator = document.getElementById('navigator');
        var gallery = Gallery(container, navigator);

        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
          if (xhr.readyState != 4) { return; }
          if (xhr.status == 200) { gallery.load(JSON.parse(xhr.responseText)); }
          else { console.log('request fail', xhr.status, xhr.responseText); }
        };

        xhr.open("GET", window.location.href + '?action=list', true);
        xhr.send();
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
    <div id="gallery">
    </div>

    <div id="navigator">
    </div>
  </body>
</html>
HTML

# Lib
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
  def images
    Dir['**/*.{jpg,gif,png}'].select { |f| File.file?(f) }.map { |f| File.split(f) - ['.'] }
  end
end

class App
  def initialize(cgi)
    @cgi = cgi
  end

  def index
    @cgi.out { PAGE_TEMPLATE }
  end

  def list
    list = ImageLister.new.images.to_json
    @cgi.out('application./json') { list }
  end
end


# CONFIG
Configuration = OpenStruct.new(
  create_thumbnails: false
)

# MAIN
cgi = CGI.new
action = cgi.params['action'].first || 'index'
App.new(cgi).send(action)
