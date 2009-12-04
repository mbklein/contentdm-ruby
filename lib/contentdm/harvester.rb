require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'uri'

module ContentDm #:nodoc:#
  
  class Harvester

    extend URI
    
    OAI_PAGE_SIZE = 1000
    
    attr_reader :base_uri
    attr_accessor :page_size
    
    # The constructor must be passed the URL of a CONTENTdm installation. This will usually
    # be the root of the server on which CONTENTdm is installed.
    def initialize(base_uri)
      @base_uri = self.class.normalize(base_uri)
      @page_size = 1000
      Mapper.init_all(@base_uri)
    end

    # Convenience method which returns a single Record when passed a URL in
    # one of two forms:
    # * A CONTENTdm URL containing CISOROOT/CISOPTR values for the desired item
    # * A CONTENTdm canonical URL in the form
    #     http://path/to/contentdm/u?[collection],[ptr]
    #   where <tt>[collection]</tt> is the CONTENTdm collection name, and <tt>[ptr]</tt> is the sequential
    #   item ID within the collection.
    def self.get_record(url)
      base_uri = self.normalize(url)
      params = {}
      if args = url.match(/^(.+\/)u\/?\?\/(.+),(\d+)$/)
        params[:base_url] = args[1]
        params[:collection] = args[2]
        params[:id] = args[3]
      else
        args = base_uri.query.split(/&/).inject({}) { |hash,arg|
          (k,v) = arg.split(/\=/,2)
          hash[k] = ::URI.decode(v)
          hash
        }
        params[:base_url] = base_uri.merge('..')
        params[:collection] = args['CISOROOT'][1..-1]
        params[:id] = args['CISOPTR']
      end
      harvester = Harvester.new(params[:base_url])
      harvester.get_record(params[:collection],params[:id])
    end
    
    # Return a hash of collection IDs and collection names
    def collections
      response = Nokogiri::XML(open(@base_uri.merge('cgi-bin/oai.exe?verb=ListSets')))
      sets = response.search('//xmlns:set',response.namespaces)
      result = {}
      sets.inject({}) { |hash,set| 
        set_id = (set / 'setSpec').text()
        set_desc = (set / 'setName').text()
        hash[set_id] = set_desc
        hash
      }
    end
    
    # Return a single Record given its collection ID and ordinal position
    # within the collection
    def get_record(collection, id)
      oai_id = "oai:%s:%s/%d" % [@base_uri.host, collection, id]
      response = get_response({ :verb => 'GetRecord', :identifier => oai_id, :metadataPrefix => 'qdc' })
      record = parse_records(response).first
      Record.new(record, { :base_uri => @base_uri, :collection => collection })
    end

    # Return an array of all the Records in a given collection
    def get_records(collection, opts = {})
      max = opts[:max].to_i
      token = "#{collection}:#{opts[:from].to_s}:#{opts[:until].to_s}:qdc:#{opts[:first].to_i || 0}"
      result = []
      until token.nil? or ((max > 0) and (result.length >= max))
        args = { :verb => 'ListRecords', :resumptionToken => token.to_s }
        response = get_response(args)
        token = response.search('/xmlns:OAI-PMH/xmlns:ListRecords/xmlns:resumptionToken/text()', response.namespaces).first
        result += parse_records(response)
      end
      if result.length > max
        result = result[0..max-1]
      end
      result.collect { |record|
        Record.new(record, { :base_uri => @base_uri, :collection => collection })
      }
    end

    private
    def parse_records(response)
      result = []
      qdcs = response.search('//qdc:qualifieddc',{ 'qdc' => 'http://epubs.cclrc.ac.uk/xmlns/qdc/' })
      qdcs.each { |qdc|
        metadata = Hash.new { |h,k| h[k] = [] }
        qdc.children.each { |child|
          if child.element?
            metadata[[child.namespace.prefix,child.name].join('.')] << child.text # unless child.text.empty?
          end
        }
        result << metadata
      }
      result
    end

    def get_response(args)
      path = 'cgi-bin/oai.exe'
      query = args.collect { |k,v| [k.to_s,::URI.encode(v)].join('=') }.join('&')
      uri = @base_uri.merge("#{path}?#{query}")
      response = Nokogiri::XML(open(uri))
    end

  end

end
