require "option_parser"

require "./common/types"

require "./cli/command"
require "./cli/registry"

# Athena module containing elements for:
# * Creating CLI commands.
module Athena::Cli
  # :nodoc:
  private abstract struct Arg; end

  # :nodoc:
  private record Argument(T) < Arg, name : String, optional : Bool, type : T.class = T

  # Defines an option parser interface for Athena CLI commands.
  macro register_commands
    OptionParser.parse! do |parser|
      parser.banner = "Usage: YOUR_BINARY [arguments]"
      parser.on("-h", "--help", "Show this help") { puts parser; exit }
      parser.on("-l", "--list", "List available commands") { puts Athena::Cli::Registry.to_s; exit }
      parser.on("-c NAME", "--command=NAME", "Run a command with the given name") do |name|
        Athena::Cli::Registry.find(name).command.call ARGV
        exit
      end
    end
  end
end