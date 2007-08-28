# benchmark.rb
require "gcls"
require "benchmark"
require "getoptlong"
include Benchmark

class Symbol
  def <=>(rhs)
    self.to_s <=> rhs.to_s
  end
end

opts = GetoptLong.new(*[
    [ '--test', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--jit', GetoptLong::NO_ARGUMENT ],
])

tests = {
  :ack => [
    "Ackermann function",
    proc { 300000.times { ack } }
  ],
  :array => [
    "Array access",
    proc { 1000.times { array_access } }
  ],
  :fib => [
    "Fibonacci numbers",
    proc { 30.times { fib } }
  ],
  :hash1 => [
    "Hash access I",
    proc { 10000.times { hash_access_I } }
  ],
  :hash2 => [
    "Hash access II",
    proc { 5.times { hash_access_II } }
  ],
  :lists => [
    "Lists",
    proc { 3.times { for iter in 1..10; result = lists; end } }
  ],
  :nested_loop => [
    "Nested loop",
    proc { 5.times { nested_loop } }
  ],
  :sieve => [
    "Sieve of Eratosthenes",
    proc { 10.times{ sieve_of_eratosthenes } }
  ],
  :word_freq => [
    "Word Frequency",
    proc { 1000.times { word_frequency } }
  ],
  :gcd_iter => [
    "GCD (iterative)",
    proc { 10000.times{ gcd_iter } }
  ],
  :gcd_recur => [
    "GCD (recursive)",
    proc { 2000.times{ gcd_recur } }
  ],
}

jit = false

opts.each do |opt, arg|
  case opt
  when '--test'
    test_names = arg.split(',').map { |name| name.intern }
    test_names.each do |test_name|
      if not tests.include?(test_name) then
        $stderr.puts "No such test #{test_name}"
        exit 1
      end
    end
    tests.delete_if { |name, test_info| !test_names.include?(name) }
  when '--jit'
    jit = true
  end
end

if jit then
  require "ruby2jit"
  [ :ack, :array_access, :fib, :hash_access_I, :hash_access_II, :lists, :nested_loop, :sieve_of_eratosthenes, :statistical_moments, :word_frequency, :gcd_iter, :gcd_recur ].each do |name|
    puts "Compiling #{name}"
    f = method(name).libjit_compile
    Object.instance_eval { remove_method(name) }
    Object.define_libjit_method(name.to_s, f, -1) # TODO: get correct arity
  end
end

if tests.size == 0 then
  $stderr.puts "No matching tests found"
  exit 1
end

widths = tests.map { |name, test_info| test_info[0].length }
max_width = widths.max

bm(max_width) do |x|
  tests.sort.each do |name, test_info|
    label = test_info[0]
    p = test_info[1]
    begin
      x.report(label, &p)
    rescue Exception
      puts $!
    end
  end
end

