module Funicular
  # Declarative client-side store backed by IndexedDB::KVS.
  #
  # Subclass either Funicular::Store::Singleton (one value per scope) or
  # Funicular::Store::Collection (ordered list per scope) and use the
  # class-level DSL to wire everything up. See store_singleton.rb /
  # store_collection.rb for the user-facing API.
  class Store
    # event_name => Array of store classes that subscribed via cleared_on
    EVENT_REGISTRY = {} #: Hash[Symbol, Array[singleton(Funicular::Store)]]

    # [database, kvs_store] => IndexedDB::KVS instance, shared across store classes
    KVS_POOL = {} #: Hash[Array[String], IndexedDB::KVS]

    # Snapshot of a `subscribes_to` declaration captured on the store class.
    SubscribesTo = Data.define(:channel_name, :params_proc, :handler_block)

    # Thin wrapper around a Funicular::Cable::Subscription. Exists so the
    # store layer can hold lifecycle ownership without leaking the cable
    # type into user code.
    class Subscription
      attr_reader :cable_sub

      def initialize(cable_sub)
        @cable_sub = cable_sub
      end

      def unsubscribe
        @cable_sub.unsubscribe
        nil
      end
    end

    # Per-scope accessor returned by Funicular::Store.where(...). Singleton
    # and Collection define their own subclasses with the data-shape API.
    class Scope
      attr_reader :store_class, :scope_kwargs

      def initialize(store_class, scope_kwargs)
        @store_class = store_class
        @scope_kwargs = scope_kwargs
        @on_change = {}
        @next_cb_id = 0
        @subscription = nil
      end

      # Expose scope kwargs as method calls (e.g. scope.channel_id) so that
      # `params: ->(s) { { channel_id: s.channel_id } }` reads naturally in
      # the subscribes_to DSL.
      def method_missing(name, *args)
        if @scope_kwargs.key?(name)
          @scope_kwargs[name]
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        @scope_kwargs.key?(name) || super
      end

      def on_change(&blk)
        @next_cb_id += 1
        id = @next_cb_id
        @on_change[id] = blk
        id
      end

      def off_change(id)
        @on_change.delete(id)
        nil
      end

      def subscribed?
        !@subscription.nil?
      end

      def subscription
        @subscription
      end

      # Lazily create a Cable subscription for this scope using the store
      # class's `subscribes_to` declaration. The handler block runs with
      # `self == this Scope`, so bareword calls like `replace`, `append`,
      # and `remove` resolve to the scope's mutators.
      def subscribe!
        existing = @subscription
        return existing if existing
        cable_binding = @store_class.__cable_binding
        raise "no subscribes_to declared on #{@store_class}" unless cable_binding
        consumer = @store_class.__consumer
        params = cable_binding.params_proc.call(self)
        handler = cable_binding.handler_block
        scope = self
        cable_sub = consumer.subscriptions.create(params) do |data|
          scope.instance_exec(data, scope, &handler) # steep:ignore
        end
        sub = Funicular::Store::Subscription.new(cable_sub)
        @subscription = sub
        sub
      end

      def unsubscribe!
        sub = @subscription
        return nil unless sub
        sub.unsubscribe
        @subscription = nil
      end

      private

      def storage_key
        parts = [] #: Array[String]
        @scope_kwargs.each do |k, v|
          parts << "#{k}=#{v}"
        end
        parts.join(":")
      end

      def kvs
        @store_class.__kvs
      end

      def now_seconds
        Time.now.to_i
      end

      def expired_record?(rec)
        return false unless rec.is_a?(Hash)
        ttl = rec["expires_in"]
        return false unless ttl.is_a?(Integer) && 0 < ttl
        wrote = rec["wrote_at"]
        return false unless wrote.is_a?(Integer)
        ttl < (now_seconds - wrote)
      end

      def fire_change(snapshot)
        @on_change.each_value do |cb|
          begin
            cb.call(snapshot)
          rescue => e
            puts "[Funicular::Store] on_change error in #{@store_class}: #{e.class}: #{e.message}"
          end
        end
      end
    end

    # ------------------------------------------------------------------
    # Class-level DSL & runtime
    # ------------------------------------------------------------------

    class << self
      attr_reader :__database, :__kvs_store_name, :__scope_keys,
                  :__expires_in, :__source, :__belongs_to,
                  :__cable_url, :__cable_binding,
                  :__cleared_handlers

      # IndexedDB database name. Required (no implicit default; users
      # should pin database names so refactors stay data-compatible).
      def database(name)
        @__database = name.to_s
      end

      # Object-store name within the database. Default: "kv".
      def kvs_store(name)
        @__kvs_store_name = name.to_s
      end

      # Declare scope keys. Single Symbol or splat of Symbols.
      #
      #   scope :channel_id
      #   scope :channel_id, :user_id
      def scope(*keys)
        @__scope_keys = keys.map { |k| k.to_sym }
      end

      def expires_in(seconds)
        @__expires_in = seconds
      end

      # Declarative-only annotation pointing at a Funicular::Model class.
      # Has no behaviour; intended for documentation / tooling.
      def source(model_class)
        @__source = model_class
      end

      # Declarative-only association marker (e.g. `belongs_to :channel`).
      # No behaviour.
      def belongs_to(name)
        @__belongs_to = name.to_sym
      end

      def cable_url(url)
        @__cable_url = url.to_s
      end

      # Capture a Cable subscription binding. The block is invoked via
      # instance_exec on the Scope when the cable subscription receives a
      # message, so bareword `replace` / `append` / `remove` resolve to the
      # scope's own mutators.
      def subscribes_to(channel_name, params:, &block)
        raise "subscribes_to requires a block" unless block
        @__cable_binding = SubscribesTo.new(channel_name.to_s, params, block)
      end

      # Register this store class for one or more global event names. When
      # Funicular::Store.dispatch(:event) is called, every registered class
      # has its data wiped (default) or runs the user-supplied block.
      def cleared_on(*event_names, &block)
        pool = (@__cleared_handlers ||= {}) #: Hash[Symbol, Proc?]
        registry = Funicular::Store::EVENT_REGISTRY
        event_names.each do |ev|
          sym = ev.to_sym
          pool[sym] = block
          arr = (registry[sym] ||= []) #: Array[singleton(Funicular::Store)]
          arr << self unless arr.include?(self)
        end
      end

      # Return (and memoize) the Scope for the given scope kwargs. Same
      # kwargs always return the same Scope instance, which is required so
      # `on_change` callbacks attach to a single identity.
      def where(**scope_kwargs)
        validate_scope_kwargs!(scope_kwargs)
        pool = (@__scope_pool ||= {}) #: Hash[Hash[Symbol, untyped], Funicular::Store::Scope]
        existing = pool[scope_kwargs]
        return existing if existing
        scope = scope_class.new(self, scope_kwargs)
        pool[scope_kwargs] = scope
        scope
      end

      # Subclasses (Singleton / Collection) override to return the
      # appropriate Scope class.
      def scope_class
        raise NotImplementedError, "#{self} must subclass Funicular::Store::Singleton or Funicular::Store::Collection"
      end

      def __kvs
        db = @__database || raise("#{self}: missing `database \"...\"` declaration")
        store_name = @__kvs_store_name || "kv"
        key = [db, store_name]
        existing = Funicular::Store::KVS_POOL[key]
        return existing if existing
        kvs = IndexedDB::KVS.open(db, store: store_name)
        Funicular::Store::KVS_POOL[key] = kvs
        kvs
      end

      def __consumer
        @__consumer ||= Funicular::Cable.create_consumer(@__cable_url || "/cable")
      end

      def __handle_dispatch(event, payload)
        pool = @__cleared_handlers
        block = pool ? pool[event] : nil
        if block
          instance_exec(payload) { |p| block.call(p) }
        else
          __clear_all!
        end
        nil
      end

      def __clear_all!
        return nil unless @__database
        __kvs.clear
        @__scope_pool = {} if @__scope_pool
        nil
      end

      private

      def validate_scope_kwargs!(scope_kwargs)
        declared = @__scope_keys || []
        given = scope_kwargs.keys
        unknown = given - declared
        unless unknown.empty?
          raise ArgumentError, "#{self}: unknown scope keys #{unknown.inspect}; declared #{declared.inspect}"
        end
        missing = declared - given
        unless missing.empty?
          raise ArgumentError, "#{self}: missing scope keys #{missing.inspect}"
        end
      end
    end

    # Dispatch an event to every store class that registered via
    # `cleared_on`. Default per-class action is `__clear_all!` (wipe the
    # KVS + drop memoized scopes); override per class with a block.
    def self.dispatch(event, payload = nil)
      sym = event.to_sym
      classes = Funicular::Store::EVENT_REGISTRY[sym] || []
      classes.each do |klass|
        begin
          klass.__handle_dispatch(sym, payload)
        rescue => e
          puts "[Funicular::Store] dispatch(#{sym.inspect}) error in #{klass}: #{e.class}: #{e.message}"
        end
      end
      nil
    end
  end
end
