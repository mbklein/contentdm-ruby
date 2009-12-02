module ContentDm
  
class Record
  
  attr_reader :metadata, :source
  
  def initialize(data, source)
    @metadata = data
    @source = source
  end
  
  # Serialize the Record to a Qualified Dublin Core XML string. If
  # a Mapper has been initialized for the Record's owning collection,
  # it will be used. Otherwise, the GenericMapper will be used.
  def to_xml(opts = {})
    mapper = Mapper.from(@source[:base_uri],@source[:collection])
    if mapper
      mapper.to_xml(self, opts)
    else
      GenericMapper.new.to_xml(self, opts)
    end
  end
  
  # Serialize the Record to an HTML string.  If a Mapper has been
  # initialized for the Record's owning collection, it will be 
  # used. Otherwise, the GenericMapper will be used.
  def to_html(opts = {})
    mapper = Mapper.from(@source[:base_uri],@source[:collection])
    if mapper
      mapper.to_html(self, opts)
    else
      GenericMapper.new.to_html(self, opts)
    end
  end
  
end

end