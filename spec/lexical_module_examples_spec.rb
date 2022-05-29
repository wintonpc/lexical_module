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
  def linear_zero(m, b) = negate(divide(b, m))
end

define_module(:Trig) do
  using import Arithmetic
  using import Algebra

  def sin(x) = Math.sin(x)
  def cos(x) = Math.cos(x)
  def sin2(a, b) = add(multiply(sin(a), cos(b)), multiply(cos(a), sin(b)))
end

RSpec.describe "define_module" do
  context "without import" do
    it "only qualified names are available" do
      expect(Arithmetic.add(1, 2)).to eql 3
      expect { add(1, 2) }.to raise_exception NoMethodError
    end
  end
  context "with import" do
    using import Arithmetic
    using import Algebra
    it "unqualified names are available" do
      expect(Arithmetic.add(1, 2)).to eql 3
      expect(add(1, 2)).to eql 3
      expect(linear_zero(0.5, -1)).to eql 2.0
    end
  end
  context "just Trig" do
    using import Trig
    it "transitive imports do not leak" do
      expect(cos(Math::PI)).to eql -1.0
      expect { add(1, 2) }.to raise_exception NoMethodError
      expect(sin2(Math::PI / 4, Math::PI / 4)).to eql 1.0
    end
  end
end
