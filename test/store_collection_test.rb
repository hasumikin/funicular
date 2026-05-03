class StoreCollectionTest < Picotest::Test
  def setup
    IndexedDB::InMemoryDatabase.stores = {}
    IndexedDB::InMemoryDatabase.meta = {}
    Funicular::Store::KVS_POOL.clear

    # Define test store classes dynamically
    unless Object.const_defined?(:MessageCache)
      Object.const_set(:MessageCache, Class.new(Funicular::Store::Collection) do
        database 'test_messages'
        scope :channel_id
        limit 5
        key ->(m) { m['id'] }
      end)
    end

    unless Object.const_defined?(:PrependCache)
      Object.const_set(:PrependCache, Class.new(Funicular::Store::Collection) do
        database 'test_prepend'
        scope :room_id
        limit 3
        order :prepend
        key ->(m) { m['id'] }
      end)
    end
  end

  def test_where_returns_scope
    scope = MessageCache.where(channel_id: 1)
    assert_equal(MessageCache, scope.store_class)
  end

  def test_all_initially_empty
    scope = MessageCache.where(channel_id: 1)
    assert_equal([], scope.all)
  end

  def test_replace_sets_items
    scope = MessageCache.where(channel_id: 1)
    messages = [
      { 'id' => 1, 'text' => 'Hello' },
      { 'id' => 2, 'text' => 'World' }
    ]
    scope.replace(messages)
    assert_equal(2, scope.all.size)
    assert_equal('Hello', scope.all[0]['text'])
  end

  def test_append_adds_item
    scope = MessageCache.where(channel_id: 1)
    scope.replace([{ 'id' => 1, 'text' => 'First' }])
    scope.append({ 'id' => 2, 'text' => 'Second' })
    assert_equal(2, scope.all.size)
    assert_equal('Second', scope.all[1]['text'])
  end

  def test_remove_by_id
    scope = MessageCache.where(channel_id: 1)
    scope.replace([
      { 'id' => 1, 'text' => 'A' },
      { 'id' => 2, 'text' => 'B' },
      { 'id' => 3, 'text' => 'C' }
    ])
    scope.remove(2)
    assert_equal(2, scope.all.size)
    ids = scope.all.map { |m| m['id'] }
    assert_equal(false, ids.include?(2))
  end

  def test_limit_caps_items
    scope = MessageCache.where(channel_id: 1)
    messages = (1..10).map { |i| { 'id' => i, 'text' => "msg#{i}" } }
    scope.replace(messages)
    # limit is 5, so only last 5 should remain (append order)
    assert_equal(5, scope.all.size)
    assert_equal(6, scope.all[0]['id'])
    assert_equal(10, scope.all[4]['id'])
  end

  def test_limit_with_prepend_order
    scope = PrependCache.where(room_id: 1)
    messages = (1..5).map { |i| { 'id' => i, 'text' => "msg#{i}" } }
    scope.replace(messages)
    # limit is 3, prepend order keeps first 3
    assert_equal(3, scope.all.size)
    assert_equal(1, scope.all[0]['id'])
    assert_equal(3, scope.all[2]['id'])
  end

  def test_append_with_prepend_order
    scope = PrependCache.where(room_id: 1)
    scope.replace([{ 'id' => 1, 'text' => 'First' }])
    scope.append({ 'id' => 2, 'text' => 'Second' })
    # prepend order puts new item at the beginning
    assert_equal(2, scope.all[0]['id'])
    assert_equal(1, scope.all[1]['id'])
  end

  def test_last
    scope = MessageCache.where(channel_id: 1)
    scope.replace([
      { 'id' => 1, 'text' => 'A' },
      { 'id' => 2, 'text' => 'B' }
    ])
    assert_equal('B', scope.last['text'])
  end

  def test_last_id
    scope = MessageCache.where(channel_id: 1)
    scope.replace([
      { 'id' => 10, 'text' => 'A' },
      { 'id' => 20, 'text' => 'B' }
    ])
    assert_equal(20, scope.last_id)
  end

  def test_last_on_empty_returns_nil
    scope = MessageCache.where(channel_id: 1)
    assert_nil(scope.last)
    assert_nil(scope.last_id)
  end

  def test_size
    scope = MessageCache.where(channel_id: 1)
    assert_equal(0, scope.size)
    scope.replace([{ 'id' => 1 }, { 'id' => 2 }])
    assert_equal(2, scope.size)
  end

  def test_clear
    scope = MessageCache.where(channel_id: 1)
    scope.replace([{ 'id' => 1 }])
    scope.clear
    assert_equal([], scope.all)
    assert_equal(0, scope.size)
  end

  def test_same_tail_true_when_matching
    scope = MessageCache.where(channel_id: 1)
    messages = [{ 'id' => 1 }, { 'id' => 2 }]
    scope.replace(messages)
    assert_equal(true, scope.same_tail?(messages))
  end

  def test_same_tail_false_when_different_size
    scope = MessageCache.where(channel_id: 1)
    scope.replace([{ 'id' => 1 }, { 'id' => 2 }])
    assert_equal(false, scope.same_tail?([{ 'id' => 1 }]))
  end

  def test_same_tail_false_when_different_last_id
    scope = MessageCache.where(channel_id: 1)
    scope.replace([{ 'id' => 1 }, { 'id' => 2 }])
    assert_equal(false, scope.same_tail?([{ 'id' => 1 }, { 'id' => 3 }]))
  end

  def test_same_tail_true_when_both_empty
    scope = MessageCache.where(channel_id: 1)
    assert_equal(true, scope.same_tail?([]))
  end

  def test_on_change_callback
    scope = MessageCache.where(channel_id: 1)
    received = nil
    scope.on_change { |val| received = val }
    scope.replace([{ 'id' => 1 }])
    assert_equal(1, received.size)
  end

  def test_different_scopes_are_independent
    scope1 = MessageCache.where(channel_id: 1)
    scope2 = MessageCache.where(channel_id: 2)
    scope1.replace([{ 'id' => 1, 'text' => 'channel1' }])
    scope2.replace([{ 'id' => 2, 'text' => 'channel2' }])
    assert_equal('channel1', scope1.all[0]['text'])
    assert_equal('channel2', scope2.all[0]['text'])
  end
end
