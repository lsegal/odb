require File.dirname(__FILE__) + "/../lib/odb"
require 'yard'

class Post
  include ODB::Persistent
  attr_accessor :title, :author, :comment
  
  def __serialize_key__; title.to_sym end
end

class Comment
  def initialize
    @name = 1
    @value = 2.5
  end
end

class YARD::CodeObjects::Base
  def __serialize_key__; path.to_sym end
end

class YARD::CodeObjects::Proxy
  def __serialize__(reference = false)
    path
    super
  end
end

class YARD::CodeObjects::RootObject
  def __serialize_key__; :root end
end

describe ODB::Database do
  it "should save a complex object" do
    YARD.parse(File.dirname(__FILE__) + '/../lib/**/*.rb')
    db = ODB.new(ODB::FileStore.new("yard"))
    db[:namespace] = YARD::Registry.at('ODB::Types')
    
    db = ODB.new(ODB::FileStore.new("yard"))
    db[:namespace].should == YARD::Registry.instance.send(:namespace)
  end
end

describe ODB::Persistent do
  it "should save a post" do
    db = ODB.new
    post = Post.new.tap {|p| p.title = "x"; p.author = "Joe"; p.comment = Comment.new }
    db.transaction do
      db[:post] = post
      db[:comment] = post.comment
    end
    
    db[:post].title.should == "x"
    db[:post].author.should == "Joe"
    db[:post].comment.object_id.should == db[:comment].object_id
  end
  
  it "should perform implicit saves on Persistent objects" do
    db = ODB.new
    post = nil
    db.transaction do
      post = Post.new.tap {|p| p.title = "x"; p.author = "Joe"; p.comment = Comment.new }
    end
    
    db[:x].should == post
  end
  
  it "should save any new object creation through #initialize" do
    db = ODB.new
    db.transaction do
      Post.new.tap {|p| p.title = "x" }
    end
    
    db[:x].should be_a(Post)
  end
end

