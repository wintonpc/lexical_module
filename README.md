# Lexically scoped modules for Ruby

Many languages have module systems where a "module" defines a number of
functions or other symbols and exports a subset of these symbols. Other modules
can access the exported symbols by qualifying them with the module name.
Alternatively, they can use these symbols without qualifying them by "importing"
the symbols.

Ruby has no such construct; the closest approximation to importing symbols is
including a module. This has unwanted consequences. Consider the following
example.

```rb
module Calculator
  def add(a, b) = a + b
  def mult(a, b) = a * b
  def div(a, b) = a / b
  private def secret = 42
end

class BankAccount
  include Calculator
  
  def deposit(amount)
    @balance = add(@balance, amount)
    secret # allowed!
  end
end
```

- **Importing affects identity**: In order to use `Calculator`, `BankAccount`
  must _become_ a `Calculator`
  - `BankAccount.new.is_a?(Calculator) ⇨ true`
- **Public methods leak**: `Calculator`'s methods appear as public methods on
  `BankAccount`
  - `BankAccount.instance_methods.include?(:add) ⇨ true`
- **Private methods leak**: `Calculator` cannot hide internal methods, even if
    they are private; `BankAccount` sees everything
- **Leaks are transitive**: If `A` includes `B` and `B` includes `C`, `A`
  unwittingly now has all of `C`'s methods and is itself a `C`!
- **include vs. extend (or both!)**: yet another thing to keep in mind
- **Limited scope control**: symbols can be imported only at the module scope,
  no larger (file) and no smaller (method). Additionally, imported symbols are
  not available to nested modules; nested modules may need to import the same
  modules their parent did just a few lines earlier.
- **Qualified usage is not free**: `Calculator.add` doesn't work without `extend
  self` or other tricks.

This gem permits a new way of using modules that avoids all of the pitfalls
listed above except the lack of method-scoped import. It is implemented using
refinements, one of the few lexical constructs ruby has to offer.

#### Debugging
Calls to imported methods don't add garbage to the stack.

#### Performance
A call to an imported method incurs a 100-200 nanosecond penalty due to
forwarding.

## Synopsis

### Export

```rb
define_module(:Arithmetic) do
  def add(a, b); ...; end
  def mult(a, b); ...; end
  def div(a, b); ...; end
  private def secret; ...; end
end
```

### Qualified usage

```rb
Arithmetic.add(1, 2)
Arithmetic.mult(3, 4)
Arithmetic.secret # error
```

### Import

```rb
class Consumer
  using import Arithmetic
  
  def calculate(m, x, b)
    add(mult(m, x), b)
  end
end
```

### Selective import
```rb
using import Arithmetic :add, :mult
```

```rb
using import Arithmetic except: [:mult, :div]
```
