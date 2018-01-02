require "jekyll/socialmeta/version"
require "jekyll/socialmeta/screenshot"
require "jekyll/socialmeta/renderqueue"
require "jekyll/socialmeta/tagger"
require 'phantomjs'
require 'fileutils'
require 'uri'

module Jekyll
  module SocialMeta
    #DATA_PROP = '_x_j_socialmeta'.freeze
    #FINAL_PROP = 'socialmeta'.freeze

    # Allow {{ socialmeta.* }}
    #Jekyll::Hooks.register :pages, :pre_render do |page, payload|
    #  if !page.data[DATA_PROP].nil?
    #    payload[FINAL_PROP] = page.data.delete(DATA_PROP)
    #  end
    #end

    #Jekyll::Hooks.register :documents, :pre_render do |doc, payload|
    #   if !doc.data[DATA_PROP].nil?
    #     payload[FINAL_PROP] = doc.data.delete(DATA_PROP)
    #   end
    #end

    # Generate screenshots

    Jekyll::Hooks.register :site, :post_write do |site|
      if (@screenshots.jobs > 0)
        self.start_render
        @screenshots.render
        self.end_render
      else
        self.finalize
      end
    end

    def self.screenshots(site = nil)
      @screenshots ||= RenderQueue.new(site)
    end

    def self.tagger(site = nil)
      @tagger ||= Tagger.new(site)
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
      self.info "Starting rendering..."
    end

    def self.end_render
      count = @screenshots.length
      cached = @screenshots.cached

      if @screenshots.jobs > 0
        @screenshots.finalize
      end

      @tagger.finalize

      runtime = "%.3f" % (Time.now - @start_render).to_f
      s = (cached == 1 ? '' : 's')
      self.info "#{cached} image#{s} reused" if cached > 0

      errors = @screenshots.errors

      self.info "Render time: #{runtime}s for #{count} URL(s), #{errors} error(s)" if count > 0
      total_run = "%.3f" % (runtime.to_f + @main_runtime.to_f)
      self.info "Total runtime: #{total_run}s"

      @screenshots.clear
    end

    def self.finalize
      @screenshots.finalize
      @tagger.finalize
    end

    def self.info(msg)
      Jekyll.logger.info "SocialMeta:", msg
    end

    def self.warn(msg)
      Jekyll.logger.warn "SocialMeta:", msg
    end

    def self.warn_once(msg)
      @warned ||= {}
      if !@warned[msg]
        Jekyll.logger.warn "SocialMeta:", msg
        @warned[msg] = 1
      end
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
        SocialMeta::tagger site

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

            # Skip if source file is older than image
            if screenshot.is_valid?
              stats[collection][:skipped] += 1
            else
              stats[collection][:render] += 1
            end

            # Still enqueue (not activate) even if valid because Jekyll
            #   may wipe out our dest_dirs if starting from scratch
            SocialMeta::screenshots.enqueue(screenshot)
            SocialMeta::tagger.enqueue(item, screenshot)
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
