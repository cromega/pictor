#!/usr/bin/ruby

require 'erb'
require 'cgi'
require 'ostruct'
require 'json'
require 'pathname'

# TEMPLATES
PAGE_TEMPLATE = <<-HTML
<!DOCTYPE html>

<html>
  <head>
    <title>Pictor</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <script type="text/javascript">
      'use strict';

      var Gallery = function(gallery, navigator) {
        var
          files,
          directory = [];

        var _update = function() {
          var images = [];
          var subdirectories = [];

          for (var i=0; i<files.length; i++) {
            var file = files[i];

            // file is not in the current path
            if (file.slice(0, directory.length).join('/') != directory.join('/')) { continue; }

            // file is in the current directory
            if (file.length == directory.length + 1) { images.push(file.join('/')); }

            // file is in a subdirectory
            if (file.length == directory.length + 2) {
             var subdirectory = file[directory.length];
             if (subdirectories.indexOf(subdirectory) == -1) { subdirectories.push(subdirectory); }
           }
          }

          _loadImages(images);
          _loadNavigator(subdirectories);
        };

        var _loadImages = function(files) {
          gallery.innerHTML = '';

          files.forEach(function(file) {
            var div = document.createElement('div');

            var a = document.createElement('a');
            a.href = file;
            a.target = "_blank";

            var img = document.createElement('img');
            img.src = file;

            a.appendChild(img)
            div.appendChild(a);
            gallery.appendChild(div);
          });
        };

        var _loadNavigator = function(subdirectories) {
          navigator.innerHTML = '';

          if (directory.length > 0) {
            var span = document.createElement('span');
            span.textContent = 'up';
            span.onclick = function() {
              _up();
            };
            navigator.appendChild(span);
            navigator.appendChild(document.createElement('hr'));
          }

          subdirectories.forEach(function(directory) {
            var span = document.createElement('span');
            span.textContent = directory;
            span.onclick = function() {
              _enter(directory);
            };
            navigator.appendChild(span);
          });
        };

        var _enter = function(subdirectory) {
          directory.push(subdirectory)
          _update();
        };

        var _up = function() {
          directory.pop();
          _update();
        };

        return {
          load: function(data) {
            files = data;
            directory = [];
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
      #navigator {
        position: fixed;
        top: 50px;
        left: 500px;
        border: 1px solid gray;
        padding: 0 5px 0 5px;
      }
      #navigator span {
        padding: 5px;
        display: block;
        text-decoration: none;
        color: gray;
      }
      #navigator span:hover {
        color: red;
        cursor: pointer;
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

class ImageLister
  def images
    Dir['**/*.{jpg,gif,png}'].map { |path| Pathname(path).each_filename.to_a }
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
