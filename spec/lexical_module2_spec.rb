# frozen_string_literal: true

require "rspec"

module HelpersOrig
  def a(x)
    x + b(x)
  end

  private def b(x)
    2 * x
  end
end

module Helpers
  module Private
    refine Object do
      private(eval(<<~EOD, binding, __FILE__, 10))
        def b(x)
          2 * x
        end
      EOD
    end
  end
  module Public
    using Private
    private(eval(<<~EOD, binding, __FILE__, 6))
      def a(x)
        x + b(x)
      end
    EOD
  end
  extend Public
  Public.private_instance_methods.each { |name| singleton_class.send(:public, name) }
end

def import2(lexmod)
  Module.new do
    refine Object do
      include lexmod.const_get(:Public)
    end
  end
end

module LexicalModuleSpecs
  RSpec.describe "lexical modules 2" do
    context "without import" do
      it "cannot call unqualified exported methods" do
        expect { a(1) }.to raise_exception NameError
      end
      it "can call qualified exported methods" do
        expect(Helpers.a(1)).to eql 3
      end
      it "cannot call qualified exported methods" do
        expect { Helpers.b(1) }.to raise_exception NameError
      end
    end
    context "with import" do
      using import2 Helpers
      it "can see exported methods" do
        expect(a(1)).to eql 3
      end
      it "cannot see hidden methods" do
        expect { b(1) }.to raise_exception NameError
      end
    end
  end
end
