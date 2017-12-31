require 'fastimage'

module Jekyll
  module SocialMeta
    WORK_DIR ='.jekyll-socialmeta'.freeze

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

        images_path = File.join(image_path_prefix, 'socialmeta')

        @@temp_dir = File.join(site.source, WORK_DIR, 'screenshots', images_path)
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

        site_url = site.config['url'] + site.config['baseurl']
        @@site_url = "#{site_url}/#{images_path}"

        @@base_params = {
          #'debug': true,
          #'proxy-type': 'none',
          'web-security': false,
          'ssl-protocol': 'tlsv1',
          #'ssl-protocol': 'any',
          'ignore-ssl-errors': true,
          'local-to-remote-url-access': true,
          'disk-cache': true,
          'disk-cache-path': @@cache_dir
        }.merge(config['phantomjs'] || {})

        @@base_image = {
          "resize" => true,
          "center" => false,
          "top" => 0,
          "left" => 0,
          "width" => 1200,
          "height" => 630,
          "viewWidth" => 1200,
          "viewHeight" => 630,
          "centerTop" => 0,
          "centerLeft" => 0,
          "scrollTop" => 0,
          "scrollLeft" => 0,
          "zoom" => 1
        }.merge(config['crop'] || {})

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

        @url = "#{@@site_url}/#{inner_path}/#{@name}"

        item_props = item.data['socialmeta'] || {}

        # TODO merge_hash
        item_image = item_props['image']
        puts
        puts "ITEM_IMAGE: #{item_image.inspect}"

        if !item_image
          img = {}
        elsif item_image.is_a?(Hash)
          img = item_image
        else
          img = { 'source' => item_image }
        end

        puts
        puts "IMG: #{img.inspect}"

        image_props = (@@config['image'] || {}).merge(img)

        puts
        puts "IMAGE PROPS: #{image_props.inspect}"

        @image = @@base_image.merge(image_props)
        puts
        puts "ORIG IMAGE: #{@image.inspect}"

        if src = @image['source']
          source_url = preprocess_image(src)

        elsif item.content =~ /!\[.*?\]\(|<img.*?src=['"]/
          src = find_largest_image(item)
          source_url = preprocess_image(src)

        else
          source_url = 'file://' + @source[:html]
        end

        puts
        puts "AFTER IMAGE: #{@image.inspect}"

        # TODO build_params so screenshot can be adjusted before rendering
        #      Need to expose source, w, h, vw, vh, top, left, scroll
        @params = @@base_params.map {
          |k,v| "--#{k}=#{v.to_s}"
        }

        # Work around scrollPosition bug
        zoom = @image['zoom'].to_f

        scroll_top = @image['scrollTop'].to_i
        @image['top'] += scroll_top
        @image['viewHeight'] += scroll_top

        scroll_left = @image['scrollLeft'].to_i
        @image['left'] += scroll_left
        @image['viewWidth'] += scroll_left

        # Some styling

        puts "CENTER? #{@image['center']}"

        if @image['center']
          #item_props['style'] = 'text-align: center; ' + item_props['style'].to_s
          #@image['style'] = 'margin: auto; '+@image['style'].to_s

          @image['style'] = "margin-top: #{@image['centerTop']}px; margin-left: #{@image['centerLeft']}px; "+@image['style'].to_s
        end


        puts
        puts "FINAL IMAGE: #{@image.inspect}"

        origin = "#{@image['top'].to_i},#{@image['left'].to_i}"
        dim = "#{@image['width'].to_i}x#{@image['height'].to_i}"
        view_dim = "#{@image['viewWidth'].to_i}x#{@image['viewHeight'].to_i}"
        scroll = "#{@image['scrollTop'].to_i},#{@image['scrollLeft'].to_i}"

        @params += [
          @@script,
          source_url,
          @temp_path,
          origin,
          dim,
          view_dim,
          scroll,
          @image['zoom'].to_s,
          item_props['style'].to_s,
          @image['style'].to_s
        ]
      end

      def render
        pj_start = Time.now

        puts @params.inspect
        ENV['hello'] = 'world'
        ENV['site_base'] = 'file://'+@@source+'/'
        puts "SITE BASE: #{ENV['site_base']}"

        error = false
        Phantomjs.run(*@params) { |msg|
          pj_info = msg.split(' ',2)

          if pj_info.first == 'error'
            SocialMeta::error "Phantomjs: #{pj_info[1]}"
            error = true
          elsif pj_info.first == 'debug'
            SocialMeta::debug "Phantomjs: #{pj_info[1]}"
          else
            SocialMeta::debug "Phantomjs #{msg}"
          end
        }

        pj_runtime = "%.3f" % (Time.now - pj_start).to_f
        if !error
          SocialMeta::debug "Phantomjs: #{@source[:url]} done in #{pj_runtime}s"
        end

        error
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

      def adjust_image(image, size)
        r_width = width = actual_width = size.first.to_f
        r_height = height = actual_height = size.last.to_f

        zoom = image['zoom']
        top = image['top']
        left = image['left']
        center_top = 0
        center_left = 0

        # The proportional height
        desired_ratio = 630 / 1200.0
        height = (width * desired_ratio).to_i

        # Expected height given the width and vice-versa
        expected_height = actual_width * desired_ratio
        expected_width = actual_height / desired_ratio

        # Crop from center
        if actual_height < actual_width
          if height < actual_height
            puts "TOP 1"
            top += (actual_height - height) / 2
          #else
          #  puts "TOP 2"
            #top += (630 - expected_height) / 2
          end
        end

        if image['resize']
          if actual_height > actual_width
            puts "R resize 1a"
            zoom *= (630.0 / actual_height)
            r_height = 630
            r_width = actual_width * zoom
          else
            puts "R resize 1b"
            zoom *= (1200.0 / actual_width)
            r_height = actual_height * zoom
            r_width = 1200
          end

          top *= zoom
          width *= zoom
          height *= zoom


          width = 1200
          height = 630

          v_width = 1200 * 2
          v_height = 630 * 2

        else
          r_width = width

          if actual_height < actual_width
            puts "R noresize 2a"
            v_height = height * 2
            v_width = width * 2
            r_height = actual_height

          else
            puts "R noresize 2b"
            r_height = height = actual_height
            width = expected_width
            v_height = height * 2
            v_width = width * 2
          end

        end

        center_left = ((width - r_width) / 2) / zoom
        center_top = (top + (height - r_height) / 2) / zoom

        puts "CL = (#{width.to_i} - #{r_width.to_i}) / 2 = #{center_left.to_i}"
        puts "CT = (#{height.to_i} - #{r_height.to_i}) /2  = #{center_top.to_i}"

        image['top'] = top.to_i
        image['left'] = left.to_i
        image['width'] = width.to_i
        image['height'] = height.to_i
        image['centerTop'] = center_top.to_i
        image['centerLeft'] = center_left.to_i
        image['viewWidth'] = v_width.to_i
        image['viewHeight'] = v_height.to_i
        image['zoom'] = "%.8f" % zoom
      end

      def preprocess_image(src)
        #((src !~ /^.*?:\/\//) || (src =~ /^file:\/\//) || )
        images_re = /\.(gif|jpe?g|png|tiff|bmp|ico|cur|psd|svg|webp)$/i
        if src && (src =~ images_re)
          # Local or remote image
          puts "SRC: #{src}"
          if m = /^file:\/\/(.+)/.match(src)
            source_img = m[1]
            source_url = src
          elsif src =~ /:\/\//
            source_img = src
            source_url = src
          else
            source_img = File.join(@@dest, src)
            source_url = 'file://' + source_img
          end

          puts "SOURCE IMAGE: #{source_img} SOURCE_URL: #{source_url}"
          # See what dimensions it has
          size = FastImage.size(source_img)
          puts "FASTIMAGE SIZE: #{size.inspect}"
          if size
            adjust_image(@image, size)
          else
            SocialMeta::warn "Unable to determine size, results not optimized"
          end

          puts "NEW IMAGE #{@image.inspect}"
          #puts "SIZE: #{size.inspect}"
        else
          source_url = src
        end

        source_url
      end

      def find_largest_image(item)
        image_tag_re = /!\[.*?\]\((.*?)\)|<img.*?src=['"](.*?)['"]/i

        # Find all local images

        src = ""

        item.content.scan(image_tag_re).each do |img|
          puts "IMG: #{img.inspect}"
          src = (img[0] || img[1]).strip
          puts "SAW IMAGE SRC #{src}"

          if m = /^file:\/\/(.+)$/.match(src)
            src = m[1]
          elsif src !~ /:\/\//
            if src =~ /^\//
              print "FULL PATH #{src}"
              src = File.join(@@dest, src.split('/'))
              puts " SRC=#{src}"
            else
              src = File.join(@@dest, item.url, src)
              puts "ITEM URL: #{item.url} SRC=#{src}"
            end
          # else use remote source as-is
          end
        end

        "file://#{src}"

      end

      private
      def copy(src, dest)
        dest_path = Pathname(dest).dirname
        if !File.exist?(dest_path)
          FileUtils.mkdir_p dest_path
        end
        FileUtils.cp(src, dest)
      end

    end

  end
end
