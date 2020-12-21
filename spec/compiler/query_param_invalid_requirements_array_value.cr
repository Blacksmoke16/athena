require "../spec_helper"

class CompileController < ART::Controller
  @[ARTA::Get(path: "/")]
  @[ARTA::QueryParam("all", requirements: [@[Assert::NotBlank], 1])]
  def action(all : Bool) : Int32
    123
  end
end

ART.run
