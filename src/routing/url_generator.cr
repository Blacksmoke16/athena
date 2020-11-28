class Athena::Routing::URLGenerator
  include Athena::Routing::URLGeneratorInterface

  def initialize(@routes : ART::RouteCollection, @request : HTTP::Request); end

  def generate(route_name : String, params : Hash(String, _)? = nil, reference_type : ART::URLGeneratorInterface::ReferenceType = :absolute_path) : String
    route = @routes.get route_name

    fragment = params.try &.delete("_fragment").to_s.presence

    # Create a hash of params based on passed in params object as well as route argument defaults.
    merged_params = route.arguments.to_h do |argument|
      if !argument.has_default? && !argument.nilable? && !params.try(&.has_key?(argument.name))
        raise ArgumentError.new "Route argument '#{argument.name}' is not nilable and was not provided nor has a default value."
      end

      # Cast the value to a string since everything is going to be a string anyway; avoids a compiler type error :shrug:.
      value = if !params.try &.has_key? argument.name
                argument.default
              else
                params_value = params.try &.[argument.name]
                raise ArgumentError.new "Route argument '#{argument.name}' is not nilable." if params_value.nil? && !argument.nilable? && argument.default.nil?
                params_value
              end.to_s

      # Validate the param matches any route constraints for that param defined on the route.
      if requirements = route.constraints[argument.name]?
        raise ArgumentError.new "Route argument '#{argument.name}' for route '#{route.name}' must match '#{requirements}', got '#{value}'." unless value.matches? requirements
      end

      # Skip params whose value isn't the same as the default,
      # Allows the value to be added as query params.
      if (param = route.params.find(&.name.==(argument.name))) && (param.default.to_s != value)
        next {"", ""}
      end

      params.try &.delete argument.name

      {":#{argument.name}", value}
    end

    # Use any extra passed in params as query params.
    query = if params && !params.empty?
              params.compact!
              HTTP::Params.encode params.transform_values &.to_s
            end

    # If the port is not a common one, 80 or 443, use it as the port; otherwise, don't bother setting it.
    port = if (p = (@request.host_with_port.try &.split(':').last?.try &.to_i)) && !p.in? 80, 443
             p
           end

    uri = URI.new(
      scheme: "https", # TODO: Should this be configurable in some way?
      host: @request.host || "localhost",
      port: port,
      path: route.path.gsub(/(?:(:\w+))/, merged_params).gsub(/\/+$/, ""),
      query: query,
      fragment: fragment
    )

    case reference_type
    in .absolute_path? then uri.full_path
    in .absolute_url?  then uri.to_s
    in .relative_path? then raise NotImplementedError.new("Relative path reference type is currently not supported.")
    in .network_path?
      uri.scheme = nil
      uri.to_s
    end
  end
end
