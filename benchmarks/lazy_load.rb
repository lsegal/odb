require 'benchmark'
require_relative '../lib/odb'

TIMES = 1000
OBJECTS = 1000
$db = ODB.new
#$ODB_DEBUG = true

class MyList1
  include ODB::Persistent
  attr_accessor :list
  def initialize; super; @list = [] end
end

class MyList2 < MyList1
  def list(value = false) @list end
end

$db.transaction do
  list1 = MyList1.new
  list2 = MyList2.new
  OBJECTS.times do |i| 
    obj = Object.new
    list1.list << obj 
    list2.list << obj
  end 
  $db[:list1] = list1
  $db[:list2] = list2
end

puts "Lazy loaded object:"
$db.clear_cache
p $db[:list1]
puts

Benchmark.bmbm do |x|
  x.report("lazy") { TIMES.times { $db.clear_cache; $db[:list1] } }
  x.report("load") { TIMES.times { $db.clear_cache; $db[:list2] } }
end

