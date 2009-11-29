require 'redis'
require_relative '../lib/odb'

describe ODB::RedisStore do
  it "should save simple items" do
    db = ODB::RedisStore.new
    db[:item] = {:a => 1, :b => ["a", :b, 3]}
    db.clear_cache
    db[:item].should.should == {a: 1, b: ["a", :b, 3]}
  end
end