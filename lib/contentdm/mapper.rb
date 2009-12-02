require 'rubygems'
require 'nokogiri'
require 'net/http'
require 'open-uri'
require 'uri'

module ContentDm
  
# GenericMapper acts as a fallback formatter for instances when no other Mapper is defined
class GenericMapper
  
  SaveOptions = Nokogiri::XML::Node::SaveOptions

  # Serialize the given Record to a Qualified Dublin Core XML string
  def to_xml(record, opts = {})
    builder = Nokogiri::XML::Builder.new do |doc|
      doc.qualifieddc('xmlns:qdc' => "http://epubs.cclrc.ac.uk/xmlns/qdc/", 
        'xmlns:dc' => "http://purl.org/dc/elements/1.1/", 
        'xmlns:dcterms' => "http://purl.org/dc/terms/") {
          record.metadata.each_pair { |k,v|
            (prefix,tag) = k.split(/\./)
            if v.is_a?(Array)
              v.each { |value|
                doc[prefix].send(tag.to_sym) {
                  doc.text(value)
                }
              }
            else
              doc[prefix].send(tag.to_sym) {
                doc.text(v)
              }
            end
          }
        }
    end
    builder.to_xml
  end
  
  # Serialize the given Record to an HTML string
  def to_html(record, opts = {})
    save_options = { :encoding => 'UTF-8', :save_with => (SaveOptions::AS_XML | SaveOptions::NO_DECLARATION), :indent => 2 }.merge(opts)
    builder = Nokogiri::XML::Builder.new do |doc|
      doc.span {
        record.metadata.each_pair { |k,v|
          unless v.nil? or v.to_s.empty?
            (prefix,tag) = k.split(/\./)
            # Convert from camelCase to Human Readable Label
            tag = tag.gsub(/(\S)([A-Z])/,'\1 \2').gsub(/\b('?[a-z])/) { $1.capitalize }
            doc.p {
              doc.b {
                doc.text "#{tag}:"
              }
              doc.text " "
              if v.is_a?(Array)
                doc.br
                v.each { |value|
                  doc.text value unless value.empty?
                  doc.br
                }
              else
                doc.text v
              end
            }
          end
        }
      }
    end
    builder.to_xml(save_options)
  end
  
end

# A Mapper provides information about field label, visibility, and output order for a
# specific CONTENTdm collection. This information can be screen-scraped from a 
# CONTENTdm installation, or defined programatically.
class Mapper < GenericMapper

  extend URI
  @@maps = {}
  
  attr_accessor :fields, :order
  
  def self.maps
    @@maps.keys
  end
  
  # Returns true if a Mapper has been initialized for the given collection at the specified base URI.
  def self.mapped?(uri, collection)
    return @@maps.include?(self.signature(uri,collection))
  end
  
  # Initializes Mappers for all collections at the specified base URI. See init_map
  # for details on authinfo.
  def self.init_all(base_uri, authinfo)
    uri = self.normalize(base_uri)
    response = Nokogiri::XML(open(uri.merge('cgi-bin/oai.exe?verb=ListSets')))
    sets = response.search('//xmlns:set/xmlns:setSpec/text()',response.namespaces).collect { |set| set.text }
    sets.each { |set|
      self.init_map(uri, set, authinfo)
    }
  end
  
  # Initializes the Mapper for the given collection at the specified base URI. Because this method involves
  # screen-scraping CONTENTdm's administrator interface, it requires basic authorization credentials for
  # an administrative account. The authinfo parameter can take one of three forms:
  # * A [username, password] Array
  # * A { :user => username, :pass => password } Hash
  # * A Proc or lambda function that returns one of the two above forms
  def self.init_map(base_uri, collection, authinfo)
    
    authorization_proc = lambda { |req,authinfo|
      credentials = authinfo
      unless credentials.nil?
        if credentials.is_a?(Hash)
          req.basic_auth credentials[:user], credentials[:pass]
        elsif credentials.is_a?(Array)
          req.basic_auth *credentials
        elsif credentials.is_a?(Proc)
          authorization_proc.call(req, credentials.call())
        end
      end
    }
    
    uri = self.normalize(base_uri)
    admin_uri = uri.merge("cgi-bin/admin/editconf.exe?CISODB=%2F#{collection}")
    html = Net::HTTP.start(admin_uri.host, admin_uri.port) { |http|
      req = Net::HTTP::Get.new(admin_uri.request_uri)
      authorization_proc.call(req,authinfo)
      response = http.request(req)
      if response.is_a?(Net::HTTPSuccess)
        response.body
      else
        response.error!
      end
    }
    doc = Nokogiri::HTML(html)
    rows = doc.search("//form[@action='/cgi-bin/admin/chgconf.exe']")
    map = { :fields => Hash.new { |h,k| h[k] = [] }, :order => [] }
    rows.each { |row|
      columns = row.css('.maintext').collect { |c| c.text }
      field_info = columns[2].downcase.gsub(/(\s+[a-z])/) { |ch| ch.upcase.strip }.split(/-/)
      if field_info.length == 2
        map[:fields]["dcterms.#{field_info[1]}"] << columns[1]
      else
        map[:fields]["dc.#{field_info[0]}"] << columns[1]
      end
      map[:order] << columns[1] unless columns[6] == 'Yes'
    }
    map[:fields]['dc.identifier'] << 'Permalink'
    @@maps[self.signature(uri,collection)] = self.new(map[:fields], map[:order])
  end
  
  # Assigns a map (either an initialized Map or a Hash/Array combination indicating the 
  # field mapping and field order) to a given collection.
  def self.assign_map(base_uri, collection, *args)
    uri = self.normalize(base_uri)
    if args[0].is_a?(self)
      @@maps[self.signature(uri,collection)] = args[0]
    else
      @@maps[self.signature(uri,collection)] = self.new(*args)
    end
  end
  
  # Returns the appropriate Mapper for the given collection at the specified base URI. If it
  # has not been initialized or the collection does not exist, returns nil.
  def self.from(uri, collection)
    @@maps[self.signature(uri,collection)]
  end
  
  # Creates a map based on the hash of fields
  def initialize(fields, order = nil)
    @fields = fields
    @order = order
  end
  
  # Returns a hash of field labels and data
  def map(record)
    data = record.metadata
    result = {}
    @fields.each_pair { |k,v|
      v.each_with_index { |key,index|
        value = data[k][index]
        unless value.nil?
          result[key] = value.split(/;\s*/)
          if result[key].length == 1
            result[key] = result[key].first
          end
        end
      }
    }
    result
  end

  # Serialize the given Record to a Qualified Dublin Core XML string
  def to_xml(record, opts = {})
    save_options = { :encoding => 'UTF-8', :save_with => SaveOptions::AS_XML, :indent => 2 }.merge(opts)
    data = self.map(record)
    field_order = @order || []
    builder = Nokogiri::XML::Builder.new do |doc|
      doc.qualifieddc('xmlns:qdc' => "http://epubs.cclrc.ac.uk/xmlns/qdc/", 
        'xmlns:dc' => "http://purl.org/dc/elements/1.1/", 
        'xmlns:dcterms' => "http://purl.org/dc/terms/") {
          field_order.each { |fieldname|
            field_info = @fields.find { |k,v| v.include?(fieldname) }
            unless field_info.nil?
              (prefix,tag) = field_info[0].split(/\./)
              index = field_info[1].index(fieldname)
              value = data[fieldname]
              if value.is_a?(Array)
                value = value[index]
              end
              doc[prefix].send(tag.to_sym) {
                doc.text(value)
              }
            end
          }
        }
    end
    builder.to_xml
  end
  
  # Serialize the given Record to an HTML string
  def to_html(record, opts = {})
    save_options = { :encoding => 'UTF-8', :save_with => (SaveOptions::AS_XML | SaveOptions::NO_DECLARATION), :indent => 2 }.merge(opts)
    data = self.map(record)
    field_order = @order || []
    builder = Nokogiri::XML::Builder.new do |doc|
      doc.span {
        field_order.each { |fieldname|
          unless data[fieldname].nil? or data[fieldname].empty?
            doc.p {
              doc.b {
                doc.text "#{fieldname}:"
              }
              doc.text " "
              if data[fieldname].is_a?(Array)
                doc.br
                data[fieldname].each { |value|
                  doc.text value
                  doc.br
                }
              else
                doc.text data[fieldname]
              end
            }
          end
        }
      }
    end
    builder.to_xml(save_options)
  end
  
  private
  def self.signature(uri, collection)
    "#{uri.to_s} :: #{collection}"
  end
  
end

end