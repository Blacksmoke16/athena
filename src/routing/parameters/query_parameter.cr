struct Athena::Routing::Parameters::QueryParameter(T) < Athena::Routing::Parameters::Parameter(T)
  # :inherit:
  def extract(request : HTTP::Request) : String?
    request.query_params[@name]?
  end

  # :inherit:
  def parameter_type : String
    "query"
  end
end
