require 'premailer'

Premailer.class_eval do
  protected
  # When using the 'stylesheet_link_tag' helper in Rails, css URIs are given with
  # a leading slash and a cache buster (e.g. ?12412422).
  # This override handles these cases, while falling back to the default implementation.
  def load_css_from_local_file_with_rails_path!(path)
    # Remove query string and the path
    clean_path = path.sub(/\?.*$/, '').sub(%r(^https?://[^/]*/), '')
    rails_path = Rails.root.join('public', clean_path)
    if File.file?(rails_path)
      load_css_from_string(File.read(rails_path))
    elsif (asset = Rails.application.assets.find_asset(clean_path.sub("#{Rails.configuration.assets.prefix}/", '')))
      load_css_from_string(asset.source)
    else
      load_css_from_local_file_without_rails_path!(path)
    end
  end
  alias_method_chain :load_css_from_local_file!, :rails_path

  def load_css_from_html!
    if (@options[:adapter] == :nokogiri)
      tags = @doc.search("link[@rel='stylesheet']:not([@data-premailer='ignore'])", "//style[not(contains(@data-premailer,'ignore'))]")
    else
      tags = @doc.search("link[@rel='stylesheet']:not([@data-premailer='ignore']), style:not([@data-premailer='ignore'])")
    end
    if tags
      tags.each do |tag|
        if tag.to_s.strip =~ /^\<link/i && tag.attributes['href'] && media_type_ok?(tag.attributes['media']) && @options[:include_link_tags]
          # A user might want to <link /> to a local css file that is also mirrored on the site
          # but the local one is different (e.g. newer) than the live file, premailer will now choose the local file

          if tag.attributes['href'].to_s.include? @base_url.to_s and @html_file.kind_of?(String)
            if @options[:with_html_string]
              link_uri = tag.attributes['href'].to_s.sub(@base_url.to_s, '').sub(/\A\/*/, '')
            else
              link_uri = File.join(File.dirname(@html_file), tag.attributes['href'].to_s.sub!(@base_url.to_s, ''))
              # if the file does not exist locally, try to grab the remote reference
              unless File.exists?(link_uri)
                link_uri = Premailer.resolve_link(tag.attributes['href'].to_s, @html_file)
              end
            end
          else
            link_uri = tag.attributes['href'].to_s
          end

          if Rails.env.development?
            clean_path = link_uri.sub(/\?.*$/, '').sub(%r(^https?://[^/]*/), '/').sub(/(-.*?\..{3,4}$)/, '')
            asset = Rails.application.assets.find_asset(clean_path.sub("#{Rails.configuration.assets.prefix}/", ''))
            load_css_from_string(asset.source)
          elsif Premailer.local_data?(link_uri)
            $stderr.puts "Loading css from local file: " + link_uri if @options[:verbose]
            load_css_from_local_file!(link_uri)
          else
            $stderr.puts "Loading css from uri: " + link_uri if @options[:verbose]
            @css_parser.load_uri!(link_uri, {:only_media_types => [:screen, :handheld]})
          end

        elsif tag.to_s.strip =~ /^\<style/i && @options[:include_style_tags]
          @css_parser.add_block!(tag.inner_html, :base_uri => @base_url, :base_dir => @base_dir, :only_media_types => [:screen, :handheld])
        end
      end
      tags.remove unless @options[:preserve_styles]
    end
  end
end
