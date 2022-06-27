# frozen_string_literal: true

define_module(:Arithmetic) do
  def add(a, b) = a + b
  def subtract(a, b) = a - b
  def multiply(a, b) = a * b
  def divide(a, b) = a / b.to_f
  def negate(a) = -a
end

define_module(:Algebra) do
  using import Arithmetic

  def linear_zero(m, b)
    negate(divide(b, m))
  end
end

define_module(:Trig) do
  using import Arithmetic
  using import Algebra

  def sin(x) = Math.sin(x)
  def cos(x) = Math.cos(x)
  private def sin2(a, b) = add(multiply(sin(a), cos(b)), Arithmetic.multiply(cos(a), sin(b)))
end

define_module(:Calculus) do
  using import Algebra

  def attempt_transitive_import = add(1, 2)
end

define_module(:Nested) do
  using import Arithmetic

  def outer = add(1, 2)

  define_module(:Inner) do
    def inner = add(3, 4)
  end
end

RSpec.describe "define_module" do
  context "without import" do
    it "only qualified names are available" do
      expect(Arithmetic.add(1, 2)).to eql 3
      expect { add(1, 2) }.to raise_exception NoMethodError
      expect(Nested::Inner.inner).to eql 7
    end
    it "only public names are available" do
      expect(Trig.cos(0)).to eql 1.0
      expect { Trig.sin2(1, 2) }.to raise_exception NoMethodError
    end
  end
  context "with import" do
    using import Arithmetic
    using import Algebra
    it "unqualified names are available" do
      subtract(1, 2)
      expect(Arithmetic.add(1, 2)).to eql 3
      expect(add(1, 2)).to eql 3
      expect(linear_zero(0.5, -1)).to eql 2.0
    end
  end
  context "just Trig" do
    using import Trig
    it "transitive imports do not leak outside module" do
      expect(cos(Math::PI)).to eql -1.0
      expect { add(1, 2) }.to raise_exception NoMethodError
    end
  end
  context "Calculus" do
    using import Calculus
    it "transitive imports do not leak inside module" do
      expect { attempt_transitive_import }.to raise_exception NoMethodError
    end
  end
  context "with selected import" do
    using import Arithmetic, :add
    it "only selected methods are available" do
      expect(add(1, 2)).to eql 3
      expect { subtract(1, 2) }.to raise_exception NoMethodError
      expect { multiply(3, 4) }.to raise_exception NoMethodError
    end
  end
  context "with exclude list" do
    using import Arithmetic, except: [:subtract]
    it "only selected methods are available" do
      expect(add(1, 2)).to eql 3
      expect { subtract(1, 2) }.to raise_exception NoMethodError
      expect(multiply(3, 4)).to eql 12
    end
  end
  it "attempts to import unexported methods are rejected" do
    expect { using import Trig, :sin2 }.to raise_exception /sin2/
  end
  it "attempts to import undefined methods are rejected" do
    expect { using import Trig, :nonexist }.to raise_exception /nonexist/
  end
end
