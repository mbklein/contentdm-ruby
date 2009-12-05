module ContentDm
  
class Record
  
  attr_reader :metadata, :source
  
  def initialize(data, source)
    @metadata = data.dup
    @source = source

    # Account for bug in single-record output
    parts = self.permalink.split(/\t/)
    if parts.length > 1
      self.permalink = @source[:base_uri].merge(parts.last).to_s
    end
    
    (collection, record_id) = @metadata['dc.identifier'][-1].scan(/\?\/(.+),([0-9]+)$/).flatten
    @source[:collection] = collection
    @source[:id] = record_id.to_i
  end
  
  def img_href(opts = {})
    params = { 
      'CISOROOT' => "/#{@source[:collection]}", 
      'CISOPTR' => @source[:id],
      'DMSCALE' => 100,
      'DMWIDTH' => 0,
      'DMHEIGHT' => 0,
      'DMX' => 0,
      'DMY' => 0,
      'DMTEXT' => '',
      'DMTHUMB' => '',
      'DMROTATE' => 0
    }
    opts.each_pair { |k,v|
      case k
        when :width  then params['DMWIDTH'] = v
        when :height then params['DMHEIGHT'] = v
        when :scale  then params['DMSCALE'] = v
        else              params[k] = v
      end
    }
    query = params.collect { |k,v| "#{k}=#{::URI.encode(v.to_s)}" }.join('&')
    @source[:base_uri].merge("cgi-bin/getimage.exe?#{query}")
  end
  
  def thumbnail_href
    params = { 
      'CISOROOT' => "/#{@source[:collection]}", 
      'CISOPTR' => @source[:id],
    }
    query = params.collect { |k,v| "#{k}=#{::URI.encode(v.to_s)}" }.join('&')
    @source[:base_uri].merge("cgi-bin/thumbnail.exe?#{query}")
  end
  
  def permalink
    @metadata['dc.identifier'][-1]
  end
  
  def permalink=(value)
    @metadata['dc.identifier'][-1] = value
  end
  
  def mapper
    Mapper.from(@source[:base_uri],@source[:collection]) || GenericMapper.new
  end
  
  # Serialize the Record to a Qualified Dublin Core XML string. If
  # a Mapper has been initialized for the Record's owning collection,
  # it will be used. Otherwise, the GenericMapper will be used.
  def to_xml(opts = {})
    mapper.to_xml(self, opts)
  end
  
  # Serialize the Record to an HTML string.  If a Mapper has been
  # initialized for the Record's owning collection, it will be 
  # used. Otherwise, the GenericMapper will be used.
  def to_html(opts = {})
    mapper.to_html(self, opts)
  end
  
end

end