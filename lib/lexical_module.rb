# frozen_string_literal: true

require "binding_of_caller"
require_relative "lexical_module/forwardable"

# Many languages have module systems where a "module" defines a number of functions or other
# symbols and exports a subset of these symbols. Other modules can access the exported symbols
# by qualifying them with the module name. Alternatively, they can use these symbols without
# qualifying them by "importing" the symbols.
#
# Ruby has no such construct; the closest approximation to importing symbols is including a module.
# This has unwanted consequences:
# - If BankAccount imports methods from Calculator, BankAccount _becomes_ a calculator. (modifies OO hierarchy)
# - Calculator's methods may appear as public methods on BankAccount, depending on the implementation of Calculator
#     (modifies the importing module; public methods leak)
# - Calculator cannot hide internal methods, even if they are private; BankAccount sees everything
#     (private methods leak; unwanted API surface area increase)
# - Leaks are transitive. If A uses B and B uses C, A unwittingly now has all of C's methods and is itself a C!
# - The importing module must determine whether it needs to "include" or "extend" (or sometimes both!),
#     depending on the context.
# - Symbols can only be imported at the module scope, no larger (file) and no smaller (method). Additionally,
#     imported symbols are not available to nested modules; nested modules may need to import the same modules
#     their parent did just a few lines earlier (no lexical scoping)
#
# The code in this file permits a new way of using modules that avoids all of the pitfalls listed above (except the
# lack of method-scoped import). It is implemented using "refinements", one of the few lexical constructs ruby
# has to offer.
#
# Debugging: calls to imported methods don't add garbage to the stack.
#
# Performance: a call to an imported method incurs a 100-200 nanosecond penalty due to forwarding.
# This is probably acceptable except in the hottest code.
#
# Synopsis follows or see specs for example usage.
#
# Export:
#
# module Utils
#   module Methods
#     def add(a, b); ...; end
#     def mult(a, b); ...; end
#     def div(a, b); ...; end
#     private def secret; ...; end
#   end
#
#   export Methods                    # alternatively: export Methods, :add, :mult, :div
# end
#
# Qualified usage:
#
# Utils.add(1, 2)
# Utils.mult(3, 4)
#
# Import:
#
# class Consumer
#   using import Utils                        # alternatively: using import Utils, :add, :mult
#                                                              using import Utils, except: [:div]
#   def calculate(m, x, b)
#     add(mult(m, x), b)
#   end
# end

class Module
  def export(methods_mod, *method_names, except: [])
    method_names = method_names.map(&:to_sym)
    except = except.map(&:to_sym)

    if method_names.any? && except.any?
      raise "method_names and except are mutually exclusive"
    end

    # figure out which methods to export
    all_method_names = methods_mod.instance_methods(false)
    if method_names.empty?
      method_names = all_method_names - except
      if method_names.empty?
        warn("warning: exported zero methods from #{self}")
      end
    end

    # remember stuff for #import
    unless self.name.nil?
      @methods_mod = methods_mod
      @exported_methods = method_names
      @hidden_methods = all_method_names - method_names
    end

    # allow methods to be callable as module methods
    methods_mod.instance_exec { extend self }

    # generate optimized forwarding code
    forward_definers = method_names.map { |name| LexicalModule::Forwardable.forwarder(methods_mod.inspect, name) }

    # create a refinement that delegates to the hosted methods
    refine Object do
      forward_definers.each { |p| module_exec(&p) }
      private *method_names
    end

    # create delegators for qualified references
    forward_definers.each { |p| instance_exec(&p) } if self.name
  end
end

class Object
  private def import(public_mod, *method_names, except: [])
    is_passthrough = method_names.none? && except.none?
    method_names = method_names.map(&:to_sym)
    methods_mod, exported_methods, hidden_methods =
      public_mod.instance_exec { [@methods_mod, @exported_methods, @hidden_methods] }

    hidden_attempts = method_names & hidden_methods
    if hidden_attempts.any?
      raise ArgumentError, "The following hidden methods cannot be imported: #{hidden_attempts.map(&:to_s).join(", ")}"
    end

    bad_names = method_names - exported_methods
    if bad_names.any?
      raise ArgumentError, "The following methods do not exist: #{bad_names.map(&:to_s).join(", ")}"
    end

    if method_names.empty?
      except += hidden_methods
    end

    in_scope = method_names.any? ? method_names : exported_methods - except
    b = binding.of_caller(1)
    if (conflict = in_scope.find { |name| b.eval("respond_to?(#{name.inspect}, true)") })
      raise "Cannot import method \"#{conflict}\". #{b.eval("self")} already has a method by that name."
    end

    if is_passthrough
      public_mod
    else
      Module.new { export methods_mod, *method_names, except: except }
    end
  end

  private def define_module(name, &block)
    methods_mod = Module.new(&block)
    public_mod = Module.new
    Object.const_set(name, public_mod)
    public_mod.const_set(:Methods, methods_mod)
    public_mod.instance_exec { export methods_mod }
    public_mod
  end
end
