@[ADI::Register("@configuration_resolver", tags: ["athena.event_dispatcher.listener"])]
# Handles [Cross-Origin Resource Sharing](https://enable-cors.org) (CORS).
#
# Handles CORS preflight `OPTIONS` requests as well as adding CORS headers to each response.
# See `ART::Config::CORS` for information on configuring the listener.
struct Athena::Routing::Listeners::CORS
  include AED::EventListenerInterface
  include ADI::Service

  # :nodoc:
  ALLOW_SET_ORIGIN = "athena.routing.cors.allow_set_origin"
  private WILDCARD         = "*"

  # Encapsulates logic to set CORS response headers
  private struct ResponseHeaders
    def initialize(@headers : HTTP::Headers)
    end

    {% for header in %w[allow-origin allow-methods allow-headers allow-credentials expose-headers] %}
      {% method_name = header.tr("-", "_").id %}
      def {{method_name}}=(value : String) : Nil
        @headers[{{"access-control-#{header.id}"}}] = value
      end

      def {{method_name}}=(value : Bool) : Nil
        return unless value
        self.{{method_name}} = "true"
      end

      def {{method_name}}=(value : Array(String)) : Nil
        return if value.empty?
        self.{{method_name}} = value.join(", ")
      end

      def {{method_name}}=(value : Nil) : Nil
      end

      def delete_{{method_name}} : Nil
        @headers.delete({{"access-control-#{header.id}"}})
      end
    {% end %}

    def max_age=(value : Int32) : Nil
      return unless value > 0
      @headers["access-control-max-age"] = value.to_s
    end

    def vary=(value : String) : Nil
      @headers["vary"] = value
    end
  end

  # Encapsulates logic to query CORS request headers
  private struct RequestHeaders
    def initialize(@headers : HTTP::Headers)
    end

    def request_method : String?
      @headers["access-control-request-method"]?.try(&.upcase)
    end

    def request_headers : Array(String)
      @headers["access-control-request-headers"]?.try(&.split(/,\ ?/)) || [] of String
    end

    def origin : String?
      @headers["origin"]?
    end

    def has_request_method? : Bool
      @headers.has_key?("access-control-request-method")
    end
  end

  private SIMPLE_HEADERS = {
    "accept",
    "accept-language",
    "content-language",
    "content-type",
    "origin",
  }

  def self.subscribed_events : AED::SubscribedEvents
    AED::SubscribedEvents{
      ART::Events::Request  => 250,
      ART::Events::Response => 0,
    }
  end

  def initialize(@configuration_resolver : ACF::ConfigurationResolverInterface); end

  def call(event : ART::Events::Request, dispatcher : AED::EventDispatcherInterface) : Nil
    request = event.request
    request_headers = RequestHeaders.new(request.headers)

    # Return early if there is no configuration.
    return unless config = @configuration_resolver.resolve(ART::Config::CORS)

    # Return early if not a CORS request.
    # TODO: optimize this by also checking if origin matches the request's host.
    return unless request.headers.has_key? "origin"

    # If the request is a preflight, return the proper response.
    if request.method == "OPTIONS" && request_headers.has_request_method?
      set_preflight_response config, event.request, event.response

      return event.finish_request
    end

    return unless check_origin config, event.request

    event.request.attributes[ALLOW_SET_ORIGIN] = true
  end

  def call(event : ART::Events::Response, dispatcher : AED::EventDispatcherInterface) : Nil
    # Return early if the request shouldn't have CORS set.
    return unless event.request.attributes[ALLOW_SET_ORIGIN]?

    # Return early if there is no configuration.
    return unless config = @configuration_resolver.resolve(ART::Config::CORS)

    request_headers = RequestHeaders.new(event.request.headers)
    response_headers = ResponseHeaders.new(event.response.headers)

    # TODO: Add a configuration option to allow setting this explicitly
    response_headers.allow_origin = request_headers.origin
    response_headers.allow_credentials = config.allow_credentials
    response_headers.expose_headers = config.expose_headers
  end

  # Configures the given *response* for CORS preflight
  private def set_preflight_response(config : ART::Config::CORS, request : HTTP::Request, response : HTTP::Server::Response) : Nil
    response_headers = ResponseHeaders.new(response.headers)
    request_headers = RequestHeaders.new(request.headers)

    response_headers.vary = "origin"
    response_headers.allow_credentials = config.allow_credentials
    response_headers.max_age = config.max_age
    response_headers.allow_methods = config.allow_methods

    response_headers.allow_headers = config.allow_headers.includes?(WILDCARD) ? request_headers.request_headers : config.allow_headers

    unless check_origin config, request
      return response_headers.delete_allow_origin
    end

    response_headers.allow_origin = request_headers.origin

    unless config.allow_methods.includes? request_headers.request_method
      return response.status = :method_not_allowed
    end

    unless config.allow_headers.includes? WILDCARD
      request_headers.request_headers.each do |header|
        next if SIMPLE_HEADERS.includes? header
        next if config.allow_headers.includes? header

        raise ART::Exceptions::Forbidden.new "Unauthorized header: '#{header}'"
      end
    end
  end

  private def check_origin(config : ART::Config::CORS, request : HTTP::Request) : Bool
    return true if config.allow_origin.includes?(WILDCARD)

    # Use case equality in case an origin is a Regex
    # TODO: Allow Regex when custom YAML tags are allowed
    config.allow_origin.any? &.===(request.headers["origin"])
  end
end
