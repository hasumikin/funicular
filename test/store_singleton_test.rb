class StoreSingletonTest < Picotest::Test
  def setup
    IndexedDB::InMemoryDatabase.stores = {}
    IndexedDB::InMemoryDatabase.meta = {}
    Funicular::Store::KVS_POOL.clear

    # Define test store classes dynamically
    unless Object.const_defined?(:DraftStore)
      Object.const_set(:DraftStore, Class.new(Funicular::Store::Singleton) do
        database 'test_drafts'
        scope :channel_id
      end)
    end
  end

  def test_where_returns_scope
    scope = DraftStore.where(channel_id: 1)
    assert_equal(DraftStore, scope.store_class)
  end

  def test_scope_kwargs_accessible
    scope = DraftStore.where(channel_id: 42)
    assert_equal({ channel_id: 42 }, scope.scope_kwargs)
  end

  def test_value_initially_nil
    scope = DraftStore.where(channel_id: 1)
    assert_nil(scope.value)
  end

  def test_set_and_get_value
    scope = DraftStore.where(channel_id: 1)
    scope.value = 'Hello, world!'
    assert_equal('Hello, world!', scope.value)
  end

  def test_delete_value
    scope = DraftStore.where(channel_id: 1)
    scope.value = 'draft text'
    scope.delete
    assert_nil(scope.value)
  end

  def test_empty_string_deletes_value
    scope = DraftStore.where(channel_id: 1)
    scope.value = 'some text'
    scope.value = ''
    assert_nil(scope.value)
  end

  def test_present
    scope = DraftStore.where(channel_id: 1)
    assert_equal(false, scope.present?)
    scope.value = 'text'
    assert_equal(true, scope.present?)
  end

  def test_different_scopes_are_independent
    scope1 = DraftStore.where(channel_id: 1)
    scope2 = DraftStore.where(channel_id: 2)
    scope1.value = 'draft for channel 1'
    scope2.value = 'draft for channel 2'
    assert_equal('draft for channel 1', scope1.value)
    assert_equal('draft for channel 2', scope2.value)
  end

  def test_same_scope_returns_same_instance
    scope1 = DraftStore.where(channel_id: 1)
    scope2 = DraftStore.where(channel_id: 1)
    scope1.value = 'test'
    assert_equal('test', scope2.value)
  end

  def test_on_change_callback
    scope = DraftStore.where(channel_id: 1)
    received = nil
    scope.on_change { |val| received = val }
    scope.value = 'new value'
    assert_equal('new value', received)
  end

  def test_off_change_removes_callback
    scope = DraftStore.where(channel_id: 1)
    received = nil
    cb_id = scope.on_change { |val| received = val }
    scope.off_change(cb_id)
    scope.value = 'test'
    assert_nil(received)
  end

  def test_delete_fires_change_with_nil
    scope = DraftStore.where(channel_id: 1)
    scope.value = 'text'
    received = 'not_nil'
    scope.on_change { |val| received = val }
    scope.delete
    assert_nil(received)
  end

  def test_store_hash_value
    scope = DraftStore.where(channel_id: 1)
    scope.value = { 'text' => 'hello', 'cursor' => 5 }
    result = scope.value
    assert_equal('hello', result['text'])
    assert_equal(5, result['cursor'])
  end

  def test_scope_responds_to_scope_keys
    scope = DraftStore.where(channel_id: 123)
    assert_equal(123, scope.channel_id)
  end

  def test_invalid_scope_key_raises
    assert_raise(ArgumentError) do
      DraftStore.where(invalid_key: 1)
    end
  end

  def test_missing_scope_key_raises
    assert_raise(ArgumentError) do
      DraftStore.where({})
    end
  end
end
