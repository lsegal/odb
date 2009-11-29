require_relative '../lib/odb'

class MyObject
  def initialize; @blah = "hello" end
  include ODB::Persistent
end

describe ODB::HashStore do
  it "should update in an all-or-nothing fashion" do
    db = ODB.new
    lambda do
      db.transaction do
        db[:foo] = "FOO"
        raise 
        db[:bar] = "BAR"
      end
    end.should raise_error(RuntimeError)
    db[:foo].should be_nil
    db[:bar].should be_nil
  end
  
  it "should not allow referencing unsaved elements inside transaction" do
    db = ODB.new
    db.transaction do
      db[:foo] = "FOO"
      db[:foo].should be_nil
    end
    db[:foo].should_not be_nil
  end
end