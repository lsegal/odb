require 'set'
require 'fileutils'

module ODB
  def self.new(store = nil)
    Database.new(store || HashStore.new)
  end
  
  module Persistent
  end
  
  class Database
    attr_accessor :store
    
    class << self
      attr_accessor :current
    end
    
    def initialize(store)
      self.store = store
      self.store.db = self
      self.class.current = self unless self.class.current
    end
    
    def transaction(&block)
      Transaction.new(self, &block)
    end
  end
  
  class DataStore
    attr_reader :name, :key_cache
    attr_accessor :db
    
    def initialize(name)
      @name = name
      @key_cache = {}
      @object_map = {}
    end
    
    def read(key)
      key = key_cache[key] if Symbol === key
      if oid = @object_map[key]
        ObjectSpace._id2ref(oid)
      else
        obj = read_object(key)
        @object_map[key] = obj.object_id
        obj
      end
    end
    
    def write(key, value)
      if Symbol === key
        key = (key_cache[key] = value.object_id) 
        @object_map[key] = value.object_id
        return
      end
      @object_map[key] = value.object_id
      write_object(key, value)
    end
    
    def [](key) read(key) end
    def []=(key, value) write(key, value) end

    def after_commit; end
      
    protected
    
    def read_object(key) raise NotImplementedError end
    def write_object(key, value) raise NotImplementedError end
  end
  
  class Transaction
    attr_accessor :objects

    def self.transactions
      Thread.current['__odb_transactions'] ||= []
    end
    
    def self.current
      transactions.last
    end
    
    def initialize(db = ODB.current, &block)
      @objects = Set.new
      @db = db
      transaction(&block) if block_given?
    end
    
    def transaction(&block)
      objects_before = persistent_objects
      self.class.transactions << self
      yield
      self.objects << (persistent_objects - objects_before)
      commit
      self.class.transactions.pop
    end
    
    def commit
      self.objects = objects.to_a
      while objects.size > 0
        object = objects.pop
        @db.store[object.object_id] = object
      end
      @db.store.after_commit
    end
    
    def persistent_objects
      ObjectSpace.each_object(Persistent).to_a
    end
  end
  
  class FileStore < DataStore
    def initialize(name)
      super(name)
      FileUtils.mkdir_p(name)
      if File.file?(resource("__key_cache"))
        @key_cache = Marshal.load(IO.read(resource("__key_cache")))
      end
    end
    
    def after_commit
      File.open(resource("__key_cache"), "wb") do |file|
        file.write(Marshal.dump(key_cache))
      end
    end

    protected
    
    def resource(key)
      File.join(name, key.to_s)
    end

    def read_object(key)
      Marshal.load(IO.read(resource(key))).__deserialize__
    end
    
    def write_object(key, value)
      resource = resource(key)
      FileUtils.mkdir_p(File.dirname(resource))
      File.open(resource, "wb") do |file|
        file.write(Marshal.dump(value.__serialize__))
      end
    end
  end
  
  class HashStore < DataStore
    def initialize
      super(nil)
      @store = {}
    end
    
    def read_object(key)
      @store[key].__deserialize__(db)
    end
    
    def write_object(key, value)
      @store[key] = value.__serialize__
    end
  end
end

class Object
  def __serialize__(transaction = ODB::Transaction.current)
    obj = {:class => self.class, :ivars => {}}
    instance_variables.each do |ivar|
      subobj = instance_variable_get(ivar)
      transaction.objects << subobj unless Fixnum === subobj
      obj[:ivars][ivar[1..-1]] = Fixnum === subobj ? subobj.__serialize__ : subobj.object_id
    end
    obj
  end
end

class String
  def __serialize__(transaction = nil)
    super().update(:value => self)
  end
end

class Array
  def __serialize__(transaction = ODB::Transaction.current)
    obj = super
    obj[:type] = :array
    obj[:items] = map do |item|
      transaction.objects << item 
      item.object_id
    end
    obj
  end
end

class Fixnum
  def __serialize__(transaction = nil)
    {:class => Fixnum, :value => self}
  end
end

class Float
  def __serialize__(transaction = nil)
    super().update(:value => self)
  end
end

class Hash
  def __serialize__(transaction = ODB::Transaction.current)
    obj = super
    obj[:type] = :hash
    obj[:items] = map do |k, v|
      transaction.objects.push(k.object_id, v.object_id)
      [k.object_id, v.object_id]
    end
    obj
  end
  
  def __deserialize__(db = ODB::Database.current)
    object = self[:value] ? self[:value] : self[:class].allocate
    self[:ivars].each do |ivar, value|
      object.instance_variable_set("@#{ivar}", Hash === value ? value[:value] : db.store[value])
    end
    case self[:type]
    when :array
      object.replace(self[:list].map {|item| db.store[item] })
    when :hash
      self[:list].each do |values|
        object[db.store[values[0]]] = object[db.store[values[1]]]
      end
    end
    object
  end
end

class NilClass
  def __deserialize__(db = nil)
    nil
  end
end
