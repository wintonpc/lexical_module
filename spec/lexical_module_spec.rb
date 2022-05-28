# frozen_string_literal: true

require "rspec"
require "forwardable"
require "memory_profiler"

module LexicalModuleSpecs
  module Geometry
    module Methods
      def hyp(a, b)
        Math.sqrt(square(a) + square(b))
      end

      def area(b, h)
        b * h / 2.0
      end

      def square(x)
        x * x
      end
    end

    export Methods, :hyp, :area
  end

  class GeometryUser
    using import Geometry
    def calculate(a, b)
      hyp(a, b)
    end
  end

  class GeometryUserChild < GeometryUser
  end

  RSpec.describe "a lexical module" do
    context "before using the module" do
      it "methods must be qualified" do
        expect(Geometry.hyp(3, 4)).to eq 5
        expect { hyp(3, 4) }.to raise_error NoMethodError
      end
    end
    context "when using the module" do
      using import Geometry
      it "exported methods are available" do
        MemoryProfiler.report do
          hyp(3, 4)
        end.pretty_print
        expect(hyp(3, 4)).to eq 5
        expect(area(3, 4)).to eq 6
      end
      it "unexported public methods are unavailable" do
        expect { square(3) }.to raise_error NoMethodError
        expect { Geometry.square(3) }.to raise_error NoMethodError
      end
      it "private methods are unavailable" do
        expect { square(3) }.to raise_error NoMethodError
        expect { Geometry.square(3) }.to raise_error NoMethodError
      end
      it "disallows exported methods from being called with an arbitrary receiver" do
        # ... a possible side effect of refining Object
        expect { Object.new.hyp(3, 4) }.to raise_error NoMethodError
      end
      it "works with #send" do
        expect(send(:hyp, 3, 4)).to eq 5
      end
      it "does not leak" do
        gu = GeometryUser.new
        expect(gu.calculate(3, 4)).to eq 5
        expect { gu.hyp(3, 4) }.to raise_error NoMethodError
      end
      it "does not leak through inheritance" do
        gu = GeometryUserChild.new
        expect(gu.calculate(3, 4)).to eq 5
        expect { gu.hyp(3, 4) }.to raise_error NoMethodError
      end
      class Nested
        def nested_area
          area(3, 4)
        end
      end
      it "exported methods are visible to nested modules" do
        expect(Nested.new.nested_area).to eq 6
      end
    end
    context "when the using is out of scope" do
      it "methods must be qualified" do
        expect(Geometry.hyp(3, 4)).to eq 5
        expect { hyp(3, 4) }.to raise_error NoMethodError
      end
      it "does not infect Object" do
        expect(Object.instance_methods).to_not include :hyp
        expect(Object.methods).to_not include :hyp
      end
    end

    module Spy
      module Methods
        def where_am_i
          # When debugging to a breakpoint in this method, the previous stack
          # frame should be the rspec "it" body, just like a normal method call.
          caller
        end
      end

      export Methods
    end

    context "when debugging" do
      using import Spy
      it "does not litter the stack" do
        expect(where_am_i).to eql proc { caller }.call
      end
    end

    module GeometryUsingBlacklist
      export Geometry::Methods, except: %i[square]
    end

    module BlacklistWithPrivateMethods
      module Methods
        private def foo
          42
        end
      end
      export Methods
    end

    context "blacklisting" do
      using import GeometryUsingBlacklist
      it "is supported" do
        expect(hyp(3, 4)).to eq 5
        expect(area(3, 4)).to eq 6
        expect { square(3) }.to raise_error NoMethodError
      end
      using import BlacklistWithPrivateMethods
      it "private methods are always excluded" do
        expect { foo() }.to raise_error NoMethodError
      end
    end

    context "selective importing" do
      using import Geometry, :hyp
      it "imports only those methods specified" do
        expect(hyp(3, 4)).to eq 5
        expect { area(3, 4) }.to raise_error NoMethodError
        expect { square(3) }.to raise_error NoMethodError
      end
      it "cannot import private methods" do
        expect { import Geometry, :square }.to raise_error ArgumentError
        expect { import Geometry, "square" }.to raise_error ArgumentError, /hidden methods cannot be imported/
      end
      it "cannot import non-existent methods" do
        expect { import Geometry, :foo }.to raise_error ArgumentError
      end
    end

    context "selective importing with blacklisting" do
      using import Geometry, except: %i[area]
      it "imports only those methods specified" do
        expect(hyp(3, 4)).to eq 5
        expect { area(3, 4) }.to raise_error NoMethodError
        expect { square(3) }.to raise_error NoMethodError
      end
    end

    context "aliased methods" do
      module ISay
        module Methods
          def say
            "potayto"
          end
        end
        export Methods
      end

      module YouSay
        module Methods
          def say
            "potahto"
          end
        end
        export Methods
      end

      describe "using ISay" do
        using import ISay
        it "says potayto" do
          expect(say).to eql "potayto"
        end
      end

      describe "using YouSay" do
        using import YouSay
        it "says potahto" do
          expect(YouSay.say).to eql "potahto"
          expect(say).to eql "potahto"
        end
      end

      describe "method name conflicts" do
        using import ISay
        it "conflict with previous import is rejected" do
          expect { using import YouSay }.to raise_exception(/Cannot import method "say"/)
        end
        it "conflict with normal method is rejected" do
          expect { using import Geometry }.to raise_exception(/Cannot import method "hyp"/)
        end

        def hyp = true
      end
    end

    context "complex signatures" do
      module AllParamKinds
        module Methods
          def everything(a, b=1, *args, c:, d: 1.to_s, # intentional line break and parens in default value expression should not break anything
            **kws, &block)
            [a, b, args, c, d, kws, block]
          end
        end
        export Methods
      end
      describe "using AllParamKinds" do
        using import AllParamKinds
        it "supports them" do
          block = proc {}
          expect(everything(1, 2, 3, c: 4, d: 5, e: 6, &block)).to eql [1, 2, [3], 4, 5, {e: 6}, block]
          expect(everything(11, c: 44)).to eql [11, 1, [], 44, "1", {}, nil]
        end
      end
    end

    define_module(:Greetings) do
      def hello(name) = "hello, #{name}"
      private def goodbye(name) = "goodbye, #{name}"
    end

    context "define_module" do
      using import Greetings
      it "defines a module" do
        expect(hello("world")).to eql "hello, world"
        expect { goodbye("world") }.to raise_exception NoMethodError
      end
    end
  end
end

