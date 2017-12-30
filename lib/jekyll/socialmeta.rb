require "jekyll/socialmeta/version"
require "jekyll/socialmeta/screenshot"
require "jekyll/socialmeta/renderqueue"
require 'phantomjs'
require 'fileutils'
require 'uri'

module Jekyll
  DATA_PROP = '_x_j_socialmeta'.freeze
  FINAL_PROP = 'socialmeta'.freeze

  module SocialMeta
    # Allow {{ socialmeta.* }}
    Jekyll::Hooks.register :pages, :pre_render do |page, payload|
      if !page.data[DATA_PROP].nil?
        payload[FINAL_PROP] = page.data.delete(DATA_PROP)
      end
    end

    Jekyll::Hooks.register :documents, :pre_render do |doc, payload|
       if !doc.data[DATA_PROP].nil?
         payload[FINAL_PROP] = doc.data.delete(DATA_PROP)
       end
    end

    # Generate screenshots

    Jekyll::Hooks.register :site, :post_write do |site|
      if (@screenshots.jobs > 0)
        self.start_render
        @screenshots.render
        self.end_render
      else
        @screenshots.finalize
      end
    end

    def self.screenshots(site = nil)
      @screenshots ||= RenderQueue.new(site)
    end

    def self.debug_state(state = false)
      @debug ||= state
    end

    def self.start_main
      @start_main = Time.now
      self.debug "Starting main processing"
    end

    def self.end_main
      runtime = "%.3f" % (Time.now - @start_main).to_f
      if @screenshots.jobs > 0
        self.debug "Main runtime: #{runtime}s"
      else
        self.info "Total runtime: #{runtime}s"
      end
      @main_runtime = runtime
    end

    def self.start_render
      @start_render = Time.now
      self.info "Starting rendering.."
    end

    def self.end_render
      count = @screenshots.length
      prerendered = @screenshots.jobs - count

      @screenshots.finalize

      runtime = "%.3f" % (Time.now - @start_render).to_f
      s = (prerendered == 1 ? '' : 's')
      self.info "#{prerendered} image#{s} reused" if prerendered > 0

      self.info "Render time: #{runtime}s for #{count} URL(s)" if count > 0
      total_run = "%.3f" % (runtime.to_f + @main_runtime.to_f)
      self.info "Total runtime: #{total_run}s"

      @screenshots.clear
    end

    def self.info(msg)
      Jekyll.logger.info "SocialMeta:", msg
    end

    def self.warn(msg)
      Jekyll.logger.warn "SocialMeta:", msg
    end

    def self.debug(msg)
      Jekyll.logger.warn "SocialMeta:", msg if @debug
    end

    def self.error(msg)
      Jekyll.logger.error "SocialMeta:", msg
    end

    class Generator < Jekyll::Generator
      # High priority so it doesn't have to process e.g. JCP pages
      priority :high

      def generate(site)
        pconfig = site.config['socialmeta'] || {}
        return unless pconfig["enabled"].nil? || sconfig["enabled"]

        SocialMeta::debug_state pconfig["debug"]
        SocialMeta::start_main
        SocialMeta::screenshots site

        if pconfig['collection'].is_a?(String)
          pconfig['collection'] = pconfig['collection'].split(/,\s*/)
        end

        collections = [ pconfig['collection'], pconfig["collections"] ].
          flatten.compact.uniq

        collections = [ 'posts' ] if collections.empty?

        included = pconfig['include'] || []
        excluded = pconfig['exclude'] || []

        # Run through each specified collection

        stats = {}

        collections.each do |collection|
          if collection == "pages"
            items = site.pages
          else
            next if !site.collections.has_key?(collection)
            items = site.collections[collection].docs
          end

          stats[collection] = {
            :total => 0,
            :skipped => 0,
            :render => 0
          }

          items.each do |item|
            next if item.respond_to?('html?') && !item.html?

            next if (!excluded.empty? && excluded.any? { |k, values|
              match?(item, k, values)
            })

            next if !(included.empty? || included.any? { |k, values|
              match?(item, k, values)
            })

            stats[collection][:total] += 1

            screenshot = Screenshot.new(item)

            site_url = (site.config['canonical'] || site.config['url']) + site.config['baseurl'] + item.url

            meta =  %Q{  <meta property="jog:url" content="#{site_url}"/>\n} +
                    %Q{  <meta property="jog:type" content="website"/>\n} +
                    %Q{  <meta property="jog:title" content="#{item.data['title']}"/>\n} +
                    %Q{  <meta property="jog:description" content="#{item.data['description'] || site.config['description']}"/>\n} +
                    %Q{  <meta property="jog:image" content="#{screenshot.url}"/>\n}

            item.data[DATA_PROP] = {
              "hello" => "Hello,",
              "world" => "World!",
              "tags" => meta
            }

            # Skip if source file is older than image
            if screenshot.is_valid?
              SocialMeta::debug "Skipping #{item.url} (done)"
              stats[collection][:skipped] += 1
            else
              stats[collection][:render] += 1
            end

            # Still enqueue because Jekyll may wipe out _site and
            #  our dest_dirs
            SocialMeta::screenshots.enqueue(screenshot)
          end

          if !stats[collection][:render].zero?
            SocialMeta::info "[#{collection}] #{stats[collection][:total]} " +
              "seen, #{stats[collection][:skipped]} skipped, " +
              " #{stats[collection][:render]} rendering"
          end
        end

        SocialMeta::end_main
      end

      def match?(item, k, values)
        match = false
        values = [ values ].flatten
        values.each do |v|
          match ||= ((item.data.has_key?(k) && (item.data[k] == v || item.data[k] =~ /#{v}/)) ||
            (item.respond_to?(k) && (item[k] == v || item[k] =~ /#{v}/)))
        end
        match
      end

    end
  end
end
