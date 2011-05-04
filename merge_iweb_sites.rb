#!/usr/bin/env ruby

require 'fileutils'
require 'find'
require 'nokogiri'
require 'optparse'

class Merger
  def initialize(options)
    @resources_dir = File.expand_path(File.join(File.dirname(__FILE__), 'resources'))
    @src_dir = options[:src_dir]
    @dest_dir = options[:dest_dir]
    @home_page = (options[:home_page] || 'Home') + '.html'
    @home_dir = nil
  end
  
  def find_home_page
    Find.find(@src_dir) do |path|
      if File.basename(path) == @home_page
        @home_dir = File.expand_path(File.dirname(File.dirname(path)))
        puts "Found home_dir #{@home_dir}"
        break
      end
    end
    raise "Could not find '#{@home_page}'" unless @home_dir
  end
  
  def init_feed
    feed_source =<<END_FEED
<feed xmlns="http://www.w3.org/2005/Atom">
 <id>urn:iweb:2BEB0C20-05FC-4518-92D0-B91265DE8373</id>
 <title>Page list Atom feed</title>
 <updated>2011-04-12T16:32:47-07:00</updated>
 <link rel="self" href="feed.xml"/>
 <generator>iWeb</generator>
 <author>
  <name>iWeb</name>
 </author>
</feed>
END_FEED
    @nav_feed = Nokogiri::XML(feed_source)
  end

  def create_dest
    @site_dir = File.join(@dest_dir, 'Site')
    FileUtils.mkdir_p(@site_dir)
  end

  def get_feed_entries(sub_dir)
    # index.html is xhtml compliant
    # open it to find the subfolder
    puts "in dir #{sub_dir}"
    feed_dir = nil
    entries = [ ]
    index_html = Nokogiri::XML(File.open(File.join(sub_dir, 'index.html')))
    if index_html
      meta = index_html.xpath('//xhtml:meta', 'xhtml' => 'http://www.w3.org/1999/xhtml').first
      if meta
        redirect_url = meta['content'].gsub(/^.+;url=\s+/, '')
        sub_folder = File.dirname(redirect_url)
        feed_dir = File.join(sub_dir, sub_folder)
        feed_xml = Nokogiri::XML(File.open(File.join(feed_dir, 'feed.xml')))
        if feed_xml
          entries = feed_xml.xpath('//atom:entry', 'atom' => 'http://www.w3.org/2005/Atom')
        else
          puts "could not parse feed.xml"
        end
      else
        puts "could not find meta"
      end
    else
      puts "could not parse index.html"
    end
    puts "found #{entries.size} feed entries"
    [feed_dir, entries]
  end
  
  def copy_resources
    ['Media', 'Scripts'].each do |fname|
      src_entry = File.join(@resources_dir, fname)
      dst_entry = File.join(@site_dir, fname)
      puts "copy #{src_entry} to #{dst_entry}"
      FileUtils.cp_r(src_entry, dst_entry, :remove_destination => true)
    end
  end
  
  def copy_page(sub_dir, feed_dir, page)
    # copy all the page files
    page_files = page.gsub(/\.html$/, '_files')
    ['index.html', page, page_files].each do |fname|
      src_entry = File.join(feed_dir, fname)
      dst_entry = File.join(@site_dir, fname)
      puts "copy #{src_entry} to #{dst_entry}"
      FileUtils.cp_r(src_entry, dst_entry, :remove_destination => true)
    end
  end
  
  def copy_and_fix_index_html
    puts "building index.html for #{@home_page}"
    index_html_src = File.join(@home_dir, 'index.html')
    index_html_dst = File.join(@dest_dir, 'index.html')
    index_html_contents = File.open(index_html_src, 'r').read
    index_html_contents.gsub!(/\"0\;url= ([^"]+)/, "\"0;url= Site/#{@home_page}")
    File.open(index_html_dst, 'w') do |f|
      f.write(index_html_contents)
    end
  end
  
  def parse_and_copy_pages
    @all_entries = [ ]
    Dir.foreach(@src_dir) do |name|
      next if name =~ /^\./
      sub_dir = File.join(@src_dir, name)
      next unless File.directory?(sub_dir)
      is_home_dir = (sub_dir == @home_dir)
      puts "parsing #{sub_dir}: home? #{is_home_dir ? 'T' : 'F'}"
      feed_dir, feed_entries = get_feed_entries(sub_dir)
      feed_entries.each do |entry|
        link = entry.xpath('./atom:link', 'atom' => 'http://www.w3.org/2005/Atom').first
        if link
          page = link['href']
          copy_page(sub_dir, feed_dir, page)
          # put home feed entry first
          first_entry = @nav_feed.root.at('entry')
          puts "found an entry" if first_entry
          if is_home_dir && first_entry
            first_entry.before(entry)
          else
            @nav_feed.root << entry
          end
        else
          puts "could not find link"
        end
      end
    end
  end
  
  def write_feed
    @nav_feed.write_to(File.open(File.join(@site_dir, 'feed.xml'), 'w'), :encoding => 'UTF-8', :indent => 1)
  end

  def merge_sites
    find_home_page
    create_dest
    copy_resources
    init_feed
    parse_and_copy_pages
    write_feed
    copy_and_fix_index_html
  end
end

options = { }
optparser = OptionParser.new do |opts|
  opts.banner = "Usage: merge_iweb_sites.rb [options] src_dir dest_dir"
  opts.on("-h", "--home-page", "Name of home page (default 'Home')") do |h|
    options[:home_page] = h
  end
  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end
end
optparser.parse!

if ARGV.size < 2
  puts optparser
  exit(-1)
end

options[:src_dir] = ARGV[0]
options[:dest_dir] = ARGV[1]
Merger.new(options).merge_sites
