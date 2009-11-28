require 'set'
require 'fileutils'
require 'json'

module ODB
  # Shorthand for creating a new {Database}
  def self.new(store = nil)
    Database.current = store || HashStore.new
  end
  
  module Persistent
    def initialize(*args, &block)
      super
      __queue__ if Transaction.current
    end
  end
  
  class Database
    attr_reader :name, :key_cache

    class << self
      attr_accessor :current
    end
    
    def initialize(name)
      self.class.current = self unless self.class.current
      @name = name
      @key_cache = {}
      @object_map = {}
    end

    def transaction(*names, &block)
      Transaction.new(self, *names, &block)
    end
    
    def read(key)
      key = key_cache[key] if Symbol === key && key_cache[key]
      
      begin
        if oid = @object_map[key]
          return ObjectSpace._id2ref(oid)
        end
      rescue RangeError
      end

      obj = read_object(key)
      @object_map[key] = obj.object_id
      obj.__deserialize__(self)
    end
    
    def write(key, value)
      if Transaction.current
        write_in_transaction(key, value)
      else
        transaction { write_in_transaction(key, value) }
      end
    end
    
    def [](key) read(key) end
    def []=(key, value) write(key, value) end
      
    def add(object) self[object_key(object)] = object end

    def after_commit; end
      
    protected
    
    def object_key(object) object.__serialize_key__ end
    def read_object(key) raise NotImplementedError end
    def write_object(key, value) raise NotImplementedError end
      
    private
    
    def write_in_transaction(key, value)
      key = (key_cache[key] = object_key(value)) if Symbol === key && object_key(value) != key

      if Transaction.current.in_commit?
        puts "Committing #{key} => #{value.inspect}" if $ODB_DEBUG
        @object_map[key] = value.object_id
        write_object(key, value.__serialize__)
      else
        value.__queue__
      end
    end
  end
  
  class Transaction
    attr_accessor :objects

    def self.transactions
      Thread.current['__odb_transactions'] ||= []
    end
    
    def self.current
      transactions.last
    end
    
    def initialize(db = ODB.current, *keys, &block)
      @objects = Set.new
      @db = db
      @committing = false
      transaction(*keys, &block) if block_given?
    end
    
    def transaction(*keys, &block)
      objects_before = persistent_objects
      self.class.transactions.push(self)
      yield
      (persistent_objects - objects_before).each {|obj| obj.__queue__(self) }
      keys.each {|key| @db[key].__queue__(self) }
      commit
      self.class.transactions.pop
    end
    
    def in_commit?
      @committing
    end
    
    def commit
      @committing = true
      objs = objects.to_a
      self.objects.freeze
      while objs.size > 0
        object = objs.pop
        @db.add(object)
      end
      @db.after_commit
    ensure
      self.objects = Set.new
      @committing = false
    end
    
    def persistent_objects
      ObjectSpace.each_object(Persistent).to_a
    end
  end
  
  class FileStore < Database
    def initialize(name)
      super(name)
      FileUtils.mkdir_p(name)
      if File.file?(resource("__key_cache"))
        @key_cache = unmarshal(IO.read(resource("__key_cache")))
      end
    end
    
    def after_commit
      File.open(resource("__key_cache"), "wb") do |file|
        file.write(marshal(key_cache))
      end
    end

    protected
    
    def resource(key)
      File.join(name, key.to_s)
    end

    def read_object(key)
      unmarshal(IO.read(resource(key)))
    rescue Errno::ENOENT
      nil
    end
    
    def write_object(key, value)
      resource = resource(key)
      FileUtils.mkdir_p(File.dirname(resource))
      File.open(resource, "wb") do |file|
        file.write(marshal(value))
      end
    end
    
    def marshal(data) Marshal.dump(data) end
    def unmarshal(data) Marshal.load(data) end
  end
  
  class JSONStore < FileStore
    def marshal(data) data.to_json end
    def unmarshal(data) JSON.parse(data) end
  end
  
  class HashStore < Database
    def initialize
      super(nil)
      @store = {}
    end
    
    def read_object(key)
      @store[key]
    end
    
    def write_object(key, value)
      @store[key] = value
    end
  end
  
  module Types
    class ImmediateType
      attr_accessor :value
      def initialize(value) @value = value end
      def __deserialize__(db = nil) value end
    end
    
    class Fixnum < ImmediateType; end 
    class Symbol < ImmediateType; end
  end
end

class Object
  def __serialize_key__; object_id end
  
  def __immediate__; false end
  
  def __serialize__(reference = false)
    return self if __immediate__
    return __serialize_key__ if reference
    obj = dup
    instance_variables.each do |ivar|
      subobj = instance_variable_get(ivar)
      obj.instance_variable_set(ivar, subobj.__serialize__(true))
    end
    obj
  end
  
  def __queue__(transaction = ODB::Transaction.current)
    return if transaction.objects.include?(self) || __immediate__
    puts "Queuing #{__serialize_key__}" if $ODB_DEBUG
    transaction.objects << self
    instance_variables.each do |ivar|
      instance_variable_get(ivar).__queue__(transaction)
    end
  end
  
  def __deserialize__(db = nil)
    puts "Deserializing #{self.class}" if $ODB_DEBUG
    instance_variables.each do |ivar|
      obj = instance_variable_get(ivar)
      instance_variable_set(ivar, obj.__deserialize__(db))
    end
    self
  end
end

class String
  def __immediate__; instance_variables.empty? end
  
  def __queue__(transaction = ODB::Transaction.current)
    super unless __immediate__
  end
end

class Array
  def __serialize__(reference = false)
    obj = super
    obj.replace map {|item| item.__serialize__(true) } unless reference
    obj
  end
  
  def __queue__(transaction = ODB::Transaction.current)
    super
    each {|item| item.__queue__(transaction) }
  end
  
  def __deserialize__(db = ODB::Database.current)
    super
    replace map {|item| item.__deserialize__(db) }
  end
end

module Immediate
  def __immediate__; true end
  def __serialize__(reference = false) self end
  def __deserialize__(db = nil) self end
  def __queue__(transaction = nil) end
end

class Fixnum
  include Immediate
  
  def __serialize__(reference = false) ODB::Types::Fixnum.new(self) end

  def __deserialize__(db = ODB::Database.current)
    db[self]
  end
end

class Symbol
  include Immediate
  
  def __serialize__(reference = false) ODB::Types::Symbol.new(self) end
  
  def __deserialize__(db = ODB::Database.current)
    db[to_s]
  end
end

class TrueClass
  include Immediate
end

class FalseClass
  include Immediate
end

class NilClass
  include Immediate
end

class Float
  include Immediate
end

class Hash
  def __queue__(transaction = ODB::Transaction.current)
    super
    each {|k, v| k.__queue__(transaction); v.__queue__(transaction) }
  end
  
  def __serialize__(reference = false)
    obj = super
    unless reference
      obj.replace Hash[*map {|k, v| [k.__serialize__(true), v.__serialize__(true)] }.flatten]
    end
    obj
  end
  
  def __deserialize__(db = ODB::Database.current)
    replace Hash[*map {|k, v| [k.__deserialize__(db), v.__deserialize__(db)] }.flatten]
  end
end

