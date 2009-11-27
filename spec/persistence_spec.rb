require File.dirname(__FILE__) + "/../lib/odb"
require 'yard'

class Post
  include ODB::Persistent
  attr_accessor :title, :author, :comment
end

class Comment
  def initialize
    @name = 1
    @value = 2.5
  end
end

class YARD::CodeObjects::Base
  def __serialize_key__
    path.to_sym
  end
end

class YARD::CodeObjects::RootObject
  def __serialize_key__
    :root
  end
end

describe ODB::Persistent do
  it "should save a post" do
    db = ODB.new(ODB::FileStore.new("Hello"))
    post = Post.new.tap {|p| p.title = "x"; p.author = "Joe"; p.comment = Comment.new }
    db.transaction do
      db.store[:post] = post
      db.store[:comment] = post.comment
    end

    db = ODB.new(ODB::FileStore.new("Hello"))
    db.store[:post].title.should == "x"
    db.store[:post].author.should == "Joe"
    db.store[:post].comment.object_id.should == db.store[:comment].object_id
  end
  
  it "should save a complex object" do
    YARD.parse(File.dirname(__FILE__) + '/../lib/**/*.rb')
    db = ODB.new(ODB::FileStore.new("yard"))
    db.store[:namespace] = YARD::Registry.instance.send(:namespace)
    
    db = ODB.new(ODB::FileStore.new("yard"))
    db.store[:namespace].should == YARD::Registry.instance.send(:namespace)
  end
end

