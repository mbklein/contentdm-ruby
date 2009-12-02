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
  def self.init_all(base_uri)
    uri = self.normalize(base_uri)
    response = Nokogiri::XML(open(uri.merge('cgi-bin/oai.exe?verb=ListSets')))
    sets = response.search('//xmlns:set/xmlns:setSpec/text()',response.namespaces).collect { |set| set.text }
    sets.each { |set|
      self.init_map(uri, set)
    }
  end
  
  # Initializes the Mapper for the given collection at the specified base URI. Because this method involves
  # screen-scraping CONTENTdm's administrator interface, it requires basic authorization credentials for
  # an administrative account. The authinfo parameter can take one of three forms:
  # * A [username, password] Array
  # * A { :user => username, :pass => password } Hash
  # * A Proc or lambda function that returns one of the two above forms
  def self.init_map(base_uri, collection)
    uri = self.normalize(base_uri)

    dc_map = self.from(uri, 'DC_MAPPING')
    if dc_map.nil?
      fields = open(uri.merge("dc.txt")) { |res| res.read }
      dc_map = {}
      fields.each_line { |field|
        field_properties = field.chomp.split(/:/)
        dc_field = self.normalize_field_name(field_properties[0])
        field_code = field_properties[1]
        dc_map[field_code] = dc_field
      }
      @@maps[self.signature(uri, 'DC_MAPPING')] = dc_map
    end

    begin
      fields = open(uri.merge("#{collection}/index/etc/config.txt")) { |res| res.read }
      map = { :fields => Hash.new { |h,k| h[k] = [] }, :order => [] }
      fields.each_line { |field|
        field_properties = field.chomp.split(/:/)
        field_label = field_properties.first
        field_code = field_properties.last
        map[:fields][dc_map[field_code]] << field_label
        map[:order] << field_label unless field_properties[-3] == 'HIDE'
      }
      map[:fields]['dc.identifier'] << 'Permalink'
      @@maps[self.signature(uri,collection)] = self.new(map[:fields], map[:order])
    rescue OpenURI::HTTPError => e
      return nil
    end
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

  def self.normalize_field_name(fieldname)
    parts = fieldname.downcase.gsub(/(\s+[a-z])/) { |ch| ch.upcase.strip }.split(/-/)
    if parts.length == 1
      "dc.#{parts[0]}"
    else
      "dcterms.#{parts[1]}"
    end
  end
  
end

end