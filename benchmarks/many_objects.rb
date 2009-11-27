require 'benchmark'
require_relative '../lib/odb'

TIMES = 10000
$db = ODB.new #(ODB::FileStore.new("test"))

$db.store[:list] = [].extend(ODB::Persistent)

class MyObj
  attr_accessor :foo
end

def create_nonpersist_objs
  TIMES.times {|i| MyObj.new.tap {|o| o.foo = "obj#{i}" } } 
end

def create_objs
  TIMES.times {|i| $db.store[:list] << MyObj.new.tap {|o| o.foo = "obj#{i}" } }
end

Benchmark.bm do |x|
  x.report("nonpersisted") { create_nonpersist_objs }
  x.report("persisted   ") { $db.transaction { create_objs; $db.store[:list].__queue__ } }
end
