require "./param_fetcher_interface"

@[ADI::Register]
class Athena::Routing::Params::ParamFetcher
  include Athena::Routing::Params::ParamFetcherInterface

  private getter params : Hash(String, ART::Params::ParamInterfaceBase) do
    self.request.action.params.each_with_object({} of String => ART::Params::ParamInterfaceBase) do |param, params|
      params[param.name] = param
    end
  end

  def initialize(
    @request_store : ART::RequestStore,
    @validator : AVD::Validator::ValidatorInterface
  )
  end

  def each(strict : Bool? = nil, & : -> Nil) : Nil
    self.params.each do |key, param|
      yield key, self.get(key, strict)
    end
  end

  def get(name : String, strict : Bool? = nil)
    param = self.params.fetch(name) { raise KeyError.new "Unknown parameter '#{name}'." }

    default = param.default

    self.validate_param(
      param,
      param.parse_value(self.request, default),
      strict.nil? ? param.strict? : strict,
      default
    )
  end

  private def validate_param(param : ART::Params::ParamInterfaceBase, value : _, strict : Bool, default : _)
    self.check_not_incompatible_params param

    begin
      value = param.type.from_parameter value
    rescue ex : ArgumentError
      # Catch type cast errors and bubble it up as an BadRequest
      raise ART::Exceptions::BadRequest.new "Required parameter '#{param.name}' with value '#{value}' could not be converted into a valid '#{param.type}'", cause: ex
    end

    return value if !default.nil? && default == value
    return value if (constraints = param.constraints).empty?

    begin
      errors = @validator.validate value, constraints
    rescue ex : AVD::Exceptions::ValidatorError
      violation = AVD::Violation::ConstraintViolation.new(
        ex.message || "Unhandled exception while validating '#{param.name}' param.",
        ex.message || "Unhandled exception while validating '#{param.name}' param.",
        Hash(String, String).new,
        value,
        "",
        AVD::ValueContainer.new(value),
      )

      errors = AVD::Violation::ConstraintViolationList.new [violation]
    end

    unless errors.empty?
      raise ART::Exceptions::InvalidParameter.with_violations param, errors if strict
      return default.nil? ? "" : default
    end

    value
  end

  private def check_not_incompatible_params(param : ART::Params::ParamInterfaceBase) : Nil
    return if param.parse_value(self.request, nil).nil?

    param.incompatibilities.each do |incompatible_param_name|
      incompatible_param = self.params.fetch(incompatible_param_name) { raise KeyError.new "Unknown parameter '#{incompatible_param_name}'." }

      unless incompatible_param.parse_value(self.request, nil).nil?
        raise ART::Exceptions::BadRequest.new "'#{param.name}' param is incompatible with '#{incompatible_param.name}' param."
      end
    end
  end

  private def request : HTTP::Request
    @request_store.request
  end
end
