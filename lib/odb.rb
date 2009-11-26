require 'set'
require 'fileutils'
require 'json'

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
        @object_map[key] = object_key(obj)
        obj
      end
    end
    
    def write(key, value)
      if Transaction.current
        write_in_transaction(key, value)
      else
        db.transaction { write_in_transaction(key, value) }
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
      key = (key_cache[key] = object_key(value)) if Symbol === key

      if Transaction.current.in_commit?
        p "Committing #{key}"
        @object_map[key] = object_key(value)
        write_object(key, value)
      elsif !Transaction.current.objects.include?(value)
        p "Queuing #{key}"
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
    
    def initialize(db = ODB.current, &block)
      @objects = Set.new
      @db = db
      @committing = false
      transaction(&block) if block_given?
    end
    
    def transaction(&block)
      objects_before = persistent_objects
      self.class.transactions.push(self)
      yield
      self.objects += (persistent_objects - objects_before)
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
        @db.store.add(object)
      end
      @db.store.after_commit
      self.objects = Set.new
      @committing = false
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
      unmarshal(IO.read(resource(key))).__deserialize__
    end
    
    def write_object(key, value)
      resource = resource(key)
      FileUtils.mkdir_p(File.dirname(resource))
      File.open(resource, "wb") do |file|
        file.write(marshal(value.__serialize__))
      end
    end
    
    def marshal(data) Marshal.dump(data) end
    def unmarshal(data) Marshal.load(data) end
  end
  
  class JSONStore < FileStore
    def marshal(data) data.to_json end
    def unmarshal(data) JSON.parse(data) end
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
  def __serialize_key__; object_id end
  
  def __immediate__; false end
  
  def __serialize__(transaction = ODB::Transaction.current)
    obj = {:class => self.class, :ivars => {}}
    instance_variables.each do |ivar|
      subobj = instance_variable_get(ivar)
      obj[:ivars][ivar[1..-1]] = subobj.__immediate__ ? subobj.__serialize__ : subobj.__serialize_key__
    end
    obj
  end
  
  def __queue__(transaction = ODB::Transaction.current)
    return if transaction.objects.include?(self)
    transaction.objects << self
    instance_variables.each do |ivar|
      instance_variable_get(ivar).__queue__(transaction)
    end
  end
  
  def __deserialize__(db = nil)
    self
  end
end

class String
  def __immediate__; instance_variables.empty? end
  
  def __serialize__
    __immediate__ ? self : super().update(:value => self)
  end
  
  def __queue__(transaction = ODB::Transaction.current)
    super unless __immediate__
  end
end

class Array
  def __serialize__
    obj = super
    obj[:type] = 'array'
    obj[:items] = map do |item|
      item.__immediate__ ? item.__serialize__ : item.__serialize_key__
    end
    obj
  end
  
  def __queue__(transaction = ODB::Transaction.current)
    super
    each {|item| item.__queue__(transaction) }
  end
end

module Immediate
  def __immediate__; true end
  def __serialize__; self end
  def __queue__(transaction = nil) end
end

class Fixnum
  include Immediate
  
  def __serialize__; {:class => Fixnum, :value => self} end
end

class Symbol
  include Immediate
  
  def __serialize__; {:class => Symbol, :value => self} end
end

class TrueClass
  include Immediate
end

class FalseClass
  include Immediate
end

class NilClass
  include Immediate

  def __deserialize__(db = nil)
    nil
  end
end

class Float
  def __serialize__
    super().update(:value => self)
  end
end

class Hash
  def __queue__(transaction = ODB::Transaction.current)
    super
    each {|k, v| k.__queue__(transaction); v.__queue__(transaction) }
  end
  
  def __serialize__
    obj = super
    obj[:type] = 'hash'
    obj[:items] = map do |k, v|
      items = []
      [k, v].each do |item|
        items << (item.__immediate__ ? item.__serialize__ : item.__serialize_key__)
      end
      items
    end
    obj
  end
  
  def __deserialize__(db = ODB::Database.current)
    object = self[:value] ? self[:value] : self[:class].allocate
    self[:ivars].each do |ivar, value|
      object.instance_variable_set("@#{ivar}", Hash === value ? value[:value] : db.store[value])
    end
    case self[:type]
    when 'array'
      object.replace(self[:list].map {|item| db.store[item] })
    when 'hash'
      self[:list].each do |values|
        object[db.store[values[0]]] = object[db.store[values[1]]]
      end
    end
    object
  end
end

