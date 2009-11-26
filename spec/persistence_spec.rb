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

describe ODB::Persistent do
  it "should save a post" do
    db = ODB.new(ODB::JSONStore.new("Hello"))
    post = Post.new.tap {|p| p.title = "x"; p.author = "Joe"; p.comment = Comment.new }
    db.transaction do
      db.store[:post] = post
      db.store[:comment] = post.comment
    end

    db = ODB.new(ODB::JSONStore.new("Hello"))
    db.store[:post].should == post
    db.store[:post].comment.object_id.should == db.store[:comment].object_id
  end
  
  it "should save a complex object" do
    YARD.parse(File.dirname(__FILE__) + '/../lib/**/*.rb')
    db = ODB.new(ODB::JSONStore.new("yard"))
    db.transaction do
      db.store[:registry] = YARD::Registry.instance
    end
  end
end

