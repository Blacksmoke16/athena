require "../spec_helper"

describe ART::Exceptions::ServiceUnavailable do
  describe "#initialize" do
    it "sets the message, and status" do
      exception = ART::Exceptions::ServiceUnavailable.new "MESSAGE"
      exception.headers.should be_empty
      exception.status.should eq HTTP::Status::SERVICE_UNAVAILABLE
      exception.message.should eq "MESSAGE"
    end

    it "sets the retry-after if given as a string" do
      exception = ART::Exceptions::ServiceUnavailable.new "MESSAGE", "17"
      exception.headers.should eq HTTP::Headers{"retry-after" => "17"}
    end

    it "sets the retry-after if given" do
      exception = ART::Exceptions::ServiceUnavailable.new "MESSAGE", 123
      exception.headers.should eq HTTP::Headers{"retry-after" => "123"}
    end
  end
end
