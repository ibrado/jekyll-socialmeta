require 'fastimage'

module Jekyll
  module OpenGraph
    WORK_DIR ='.jekyll-opengraph'.freeze

    class Screenshot
      attr_reader :source, :url, :temp_path, :full_path, :live_path

      def self.setup(site, config)
        @@config = config || {}
        @@dest = site.dest
        @@source = site.source

        if config['images']
          image_path_prefix = File.join(config['images'])
        else
          image_path_prefix = File.join('assets', 'images')
        end

        images_path = File.join(image_path_prefix, 'opengraph')

        @@temp_dir = File.join(Dir.home(), WORK_DIR, 'screenshots', images_path)
        @@source_dir = File.join(site.source, images_path)
        @@dest_dir = File.join(site.dest, images_path)

        @@cache_dir = File.join(site.source, WORK_DIR, 'cache')

        FileUtils.mkdir_p @@temp_dir
        FileUtils.mkdir_p @@source_dir

        # Doesn't work at this point if _site was erased
        # Jekyll resets it
        #FileUtils.mkdir_p @@dest_dir

        FileUtils.mkdir_p @@cache_dir

        pwd = Pathname.new(File.dirname(__FILE__))
        @@script = "#{pwd}/screenshot.js"

        site_url = (site.config['canonical'] || site.config['url']) + site.config['baseurl']

        @@base_url = "#{site_url}/#{images_path}"

        @@base_params = {
          #'web-security': false,
          'ssl-protocol': 'tlsv1',
          'ignore-ssl-errors': true,
          'local-to-remote-url-access': true,
          'disk-cache': true,
          'disk-cache-path': @@cache_dir
        }.merge(config['phantomjs'] || {})

        @@base_crop = {
          "top" => 0,
          "left" => 0,
          "width" => 1200,
          "height" => 630,
          "viewWidth" => 1200,
          "viewHeight" => 630
        }.merge(config['crop'] || {})

        @@base_zoom = 1;

      end

      def self.save_all
        FileUtils.cp_r "#{@@temp_dir}/.", "#{@@source_dir}"
      end

      def self.activate_all
        FileUtils.cp_r "#{@@source_dir}/.", "#{@@dest_dir}"
      end

      def self.clean_all
        FileUtils.rm_r "#{@@temp_dir}"
      end

      def initialize(item)
        @source = {
          :url => item.url,
          :base => @@dest,
          :file => item.path,
          :html => item.destination('')
        }

        @name = 'og-image.jpg' # XXX

        # Setup temp folder
        # e.g. 2017-12-28-my-test
        inner_path = File.join(File.basename(item.path, File.extname(item.path)))

        # Create folders
        FileUtils.mkdir_p File.join(@@temp_dir, inner_path)
        FileUtils.mkdir_p File.join(@@source_dir, inner_path)

        # e.g. 2017-12-28-my-test/og-image.png
        @path = File.join(inner_path, @name)

        @temp_path = File.join(@@temp_dir, @path)
        @full_path = File.join(@@source_dir, @path)
        @live_path = File.join(@@dest_dir, @path)

        @url = "#{@@base_url}/#{inner_path}/#{@name}"

        item_props = item.data['opengraph'] || {}

        # TODO merge_hash
        item_crop = (@@config['crop'] || {}).merge(item_props['crop'] || {})
        @crop = @@base_crop.merge(item_crop)

        @zoom = item_props['zoom'] || @@base_zoom

        if img = item_props['image']
          if img !~ /^.*?:\/\//
            local_fn = File.join(@@dest, img)
            # See what dimensions it has
            size = FastImage.size(local_fn)
            (@zoom, @crop) = adjust_image(size)

            puts "NEW CROP #{@crop.inspect}"
            source = 'file://' + local_fn

            puts "SIZE: #{size.inspect}"
          end
        else
          source = 'file://' + @source[:html]
        end

        #puts "SOURCE: #{source}"
        @params = @@base_params.map {
          |k,v| "--#{k}=#{v.to_s}"
        }

        @params += [
          @@script,
          source,
          @temp_path,
          @crop['top'].to_s,
          @crop['left'].to_s,
          @crop['width'].to_s,
          @crop['height'].to_s,
          @crop['viewWidth'].to_s,
          @crop['viewHeight'].to_s,
          @zoom.to_s
        ]
      end

      def render
        pj_start = Time.now

        Phantomjs.run(*@params) { |msg|
          pj_info = msg.split(' ',2)

          if pj_info.first == 'error'
            OpenGraph::error "Phantomjs: #{pj_info[1]}"
          elsif pj_info.first == 'debug'
            OpenGraph::debug "Phantomjs: #{pj_info[1]}"
          else
            OpenGraph::debug "Phantomjs #{msg}"
          end
        }

        pj_runtime = "%.3f" % (Time.now - pj_start).to_f
        OpenGraph::debug "Phantomjs: #{@source[:url]} done in #{pj_runtime}s"

      end

      def activate
        if !is_saved?
          if is_available? 
            copy(@temp_path, @full_path)
          else
            save
          end
        end

        copy(@full_path, @live_path)
      end

      def save
        if !is_available? 
          render
        end

        copy(@temp_path, @full_path)
      end

      def is_available?
        File.exist? @temp_path
      end

      def is_saved?
        File.exist? @full_path
      end

      def is_live?
        File.exist? @live_path
      end

      def is_rendered?
        is_saved? || is_available?
      end

      def exist?
        is_rendered?
      end

      def is_valid?
        (is_saved? && (File.mtime(@source[:file]) <= File.mtime(@full_path))) ||
          (is_available? && (File.mtime(@source[:file]) <= File.mtime(@temp_path)))
      end

      def is_expired?
        !valid?
      end

      private
      def copy(src, dest)
        dest_path = Pathname(dest).dirname
        if !File.exist?(dest_path)
          FileUtils.mkdir_p dest_path
        end
        FileUtils.cp(src, dest)
      end

      private
      def adjust_image(size)
        width = size.first.to_f
        height = size.last.to_f

        zoom = 1
        if width < 1200 && height > 630
          ratio = width / 1200.0
          puts "RATIO: #{ratio}"
          new_height = 630 * ratio 
          top = (height - new_height) / 2
          left = 0
          zoom = 1 / ratio
        end

        return [ "%.2f" % zoom, {
          'top' => top*zoom,
          'left' => left,
          'width' => width*zoom,
          'height' => new_height*zoom,
          'viewWidth' => width*2,
          'viewHeight' => height*2
        }]

      end

    end

  end
end
