module ContentDm
  
module URI
  def normalize(uri)
   local_uri = uri.is_a?(::URI) ? uri : ::URI.parse(uri)
   local_uri.path.sub!(/\/+$/,'')
   local_uri
  end
end

end