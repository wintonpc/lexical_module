# frozen_string_literal: true

require "forwardable"
require "stringio"
$stderr = StringIO.new # silence parser version warning
require "parser/current"
$stderr = STDERR
require "unparser"

require "forwardable"

# Ruby's forwardable implementation takes splat parameters for every method, which has the effect of allocating an
# array to hold them for every method call. Ruby 2.7's "..." argument forwarding does the same thing. In hot code, this
# can add multiple gigs to peak memory usage. Instead, tailor the parameter list for each target method. Additionally,
# compile the forwarding method with TCO to hide
module LexicalModule
  module Forwardable
    @cache = {}
    class << self
      # returns a proc that defines a method that forwards to target
      def forwarder(target_expr, method_name)
        method = eval(target_expr).method(method_name)
        sig, fwd = signature_and_forwarding_arguments(method)

        # File and linenum don't matter since tailcall optimization evaporates the stack frame that would reveal them.
        RubyVM::InstructionSequence.compile("-> { #{sig} = #{target_expr}.#{method_name}(#{fwd}) }",
          "", "", 0, tailcall_optimization: true, trace_instruction: false).eval
      end

      private

      def get_ast(method)
        path = method.source_location[0]
        file_ast = @cache.fetch(path) { @cache[path] = Parser::CurrentRuby.parse(File.read(path)) }
        find_method_ast(method.source_location[1], file_ast)
      end

      def signature_and_forwarding_arguments(method)
        get_ast(method) in [type, name, args, body]
        s = Unparser.unparse(Parser::AST::Node.new(type, [name, args, Parser::AST::Node.new(:nil)]))
        sig = s[0, s.index("\n")]
        fwd = args.children.map do |a|
          case a
          in [:arg | :optarg, name, *_]
            name.to_s
          in [:restarg, name]
            "*#{name}"
          in [:kwarg | :kwoptarg, name, *_]
            "#{name}: #{name}"
          in [:kwrestarg, name]
            "**#{name}"
          in [:blockarg, name]
            "&#{name}"
          in [:forward_arg]
            "..."
          end
        end.join(", ")
        [sig, fwd]
      end

      def find_method_ast(line, x)
        if !x.is_a?(Parser::AST::Node)
          nil
        elsif x.type == :def && x.location.line == line
          x
        else
          x.children.each do |c|
            r = find_method_ast(line, c)
            return r if r
          end
          nil
        end
      end
    end
  end
end
