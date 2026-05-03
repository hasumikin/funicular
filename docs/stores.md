# Client-Side Stores

Funicular provides a declarative DSL for client-side data persistence backed by IndexedDB. Stores handle caching, TTL expiration, event-based clearing, and optional ActionCable integration.

## Table of Contents

- [Overview](#overview)
- [Store Types](#store-types)
- [Class-Level DSL](#class-level-dsl)
- [Scope API](#scope-api)
- [ActionCable Integration](#actioncable-integration)
- [Event Dispatch](#event-dispatch)
- [TTL Expiration](#ttl-expiration)
- [Important Notes](#important-notes)

## Overview

Subclass either `Funicular::Store::Singleton` (one value per scope) or `Funicular::Store::Collection` (ordered list per scope):

```ruby
class Funicular::DraftStore < Funicular::Store::Singleton
  database   "funicular_drafts"
  scope      :channel_id
  cleared_on :logout
end

class Funicular::MessageCache < Funicular::Store::Collection
  database   "funicular_message_cache"
  scope      :channel_id
  limit      100
  key        ->(m) { m["id"] }
  cleared_on :logout
end
```

Access data via scoped accessors:

```ruby
# Singleton
draft = Funicular::DraftStore.where(channel_id: 1)
draft.value = "Hello"
draft.value  # => "Hello"
draft.delete

# Collection
cache = Funicular::MessageCache.where(channel_id: 1)
cache.all            # => [...]
cache.append(msg)
cache.remove(123)
cache.replace(messages)
```

## Store Types

### Singleton

One value per scope. Suitable for drafts, user preferences, or any single-value cache.

```ruby
class Funicular::DraftStore < Funicular::Store::Singleton
  database   "funicular_drafts"
  scope      :channel_id
  cleared_on :logout
  expires_in 60 * 60 * 24  # Optional: 24-hour TTL
end
```

**Scope API:**
- `value` — read the stored value (returns `nil` if missing or expired)
- `value=` — write a value (setting `""` on a String deletes the entry)
- `delete` — remove the entry
- `present?` — true if value exists and not expired
- `expired?` — true if TTL has passed

### Collection

Ordered array per scope. Suitable for message caches, activity feeds, or any list-based data.

```ruby
class Funicular::MessageCache < Funicular::Store::Collection
  database   "funicular_message_cache"
  scope      :channel_id
  limit      100                        # Cap at 100 items
  order      :append                    # :append (default) or :prepend
  key        ->(m) { m["id"] }          # Used for remove() and same_tail?
  cleared_on :logout
  expires_in 60 * 5                     # Optional: 5-minute TTL
end
```

**Scope API:**
- `all` — read all items (returns `[]` if missing or expired)
- `replace(arr)` — replace entire list (skips IndexedDB write if `same_tail?`)
- `append(item)` — add item to end (or beginning if `order :prepend`)
- `remove(id)` — remove item by key
- `last` — last item
- `last_id` — key of last item
- `size` — number of items
- `clear` — remove all items
- `same_tail?(other)` — true if current snapshot matches `other` by size and last-item key
- `expired?` — true if TTL has passed

## Class-Level DSL

| DSL Method | Description |
|------------|-------------|
| `database "name"` | IndexedDB database name (required) |
| `kvs_store "name"` | Object store name within database (default: `"kv"`) |
| `scope :key` or `scope :a, :b` | Scope keys for partitioning data |
| `limit n` | (Collection only) Maximum items to keep |
| `order :append` or `:prepend` | (Collection only) Insertion order |
| `key ->(item) { ... }` | (Collection only) Proc to extract item ID |
| `expires_in seconds` | TTL in seconds (lazy-deletes on read) |
| `cleared_on :event` | Register for `Store.dispatch(:event)` |
| `cable_url "/path"` | ActionCable endpoint (default: `"/cable"`) |
| `subscribes_to "Channel", params: ... { }` | Embed Cable message handling |
| `source ModelClass` | Declarative annotation (no behavior) |
| `belongs_to :name` | Declarative annotation (no behavior) |

## Scope API

Get a scope via `.where(...)`:

```ruby
cache = Funicular::MessageCache.where(channel_id: 42)
```

The same `scope_kwargs` always returns the same `Scope` instance (memoized), which is important for `on_change` callback identity.

### Common Methods (both Singleton and Collection)

```ruby
# Subscribe to changes
cb_id = scope.on_change { |snapshot| puts "Data changed: #{snapshot}" }
scope.off_change(cb_id)

# Cable subscription (requires subscribes_to declaration)
scope.subscribe!
scope.unsubscribe!
scope.subscribed?
scope.subscription  # => Funicular::Store::Subscription
```

### Scope kwargs as methods

Scope kwargs are accessible as methods for use in `subscribes_to` params:

```ruby
subscribes_to "ChatChannel",
              params: ->(s) { { channel: "ChatChannel", channel_id: s.channel_id } }
```

## ActionCable Integration

Embed Cable message handling directly in the store class:

```ruby
class Funicular::MessageCache < Funicular::Store::Collection
  database "funicular_message_cache"
  scope    :channel_id
  limit    100
  key      ->(m) { m["id"] }

  subscribes_to "ChatChannel",
                params: ->(s) { { channel: "ChatChannel", channel_id: s.channel_id } } do |data, _scope|
    case data["type"]
    when "initial_messages" then replace(data["messages"] || [])
    when "new_message"      then append(data["message"])
    when "delete_message"   then remove(data["message_id"])
    end
  end
end
```

The block runs with `self == Scope`, so bareword calls like `replace`, `append`, `remove` resolve to the scope's mutators.

### Component Usage

```ruby
class ChatComponent < Funicular::Component
  def select_channel(channel)
    @cache&.unsubscribe!
    @cache&.off_change(@cb_id) if @cb_id

    @cache = Funicular::MessageCache.where(channel_id: channel.id)
    cached = @cache.all

    if !cached.empty?
      patch(messages: cached, loading: false)
    else
      patch(messages: [], loading: true)
    end

    @cb_id = @cache.on_change { |snap| patch(messages: snap, loading: false) }
    @cache.subscribe!
  end

  def handle_send_message(content)
    return unless @cache&.subscribed?
    @cache.subscription.cable_sub.perform("send_message", { content: content })
  end

  def component_will_unmount
    @cache&.unsubscribe!
    @cache&.off_change(@cb_id) if @cb_id
  end
end
```

## Event Dispatch

Register stores for coordinated clearing:

```ruby
class Funicular::DraftStore < Funicular::Store::Singleton
  cleared_on :logout
end

class Funicular::MessageCache < Funicular::Store::Collection
  cleared_on :logout
end
```

Clear all registered stores with a single call:

```ruby
def handle_logout
  Funicular::Store.dispatch(:logout)  # Wipes both DraftStore and MessageCache
  Session.logout { Funicular.router.navigate("/login") }
end
```

### Custom Clear Handler

Override the default wipe behavior:

```ruby
class Funicular::SettingsCache < Funicular::Store::Singleton
  cleared_on :logout do |payload|
    # Custom logic instead of full wipe
    puts "Logout triggered with payload: #{payload}"
  end
end
```

## TTL Expiration

Set `expires_in` for automatic expiration:

```ruby
class Funicular::SessionCache < Funicular::Store::Singleton
  database   "funicular_sessions"
  scope      :user_id
  expires_in 60 * 60  # 1 hour
end
```

- Expiration is checked on read (lazy deletion)
- Expired records return `nil` (Singleton) or `[]` (Collection)
- Use `expired?` to check without triggering deletion

## Important Notes

### Scope Key Types

`.where` memoization uses strict equality:

```ruby
# These are DIFFERENT scopes (Integer vs String):
Funicular::DraftStore.where(channel_id: 1)
Funicular::DraftStore.where(channel_id: "1")
```

IndexedDB storage keys use `to_s` internally, so data is shared, but `on_change` callbacks are scope-instance specific.

### No Explicit init! Required

Stores lazily open IndexedDB on first access. Remove any `init!` calls from your initializer:

```ruby
# Before (manual)
Funicular::DraftStore.init!
Funicular::MessageCache.init!

# After (automatic)
# Just use the stores — they initialize on first .where() or .dispatch()
```

### belongs_to / source Are Decorative

These annotations have no runtime behavior:

```ruby
class Funicular::MessageCache < Funicular::Store::Collection
  source     Message    # Documentation only
  belongs_to :channel   # Documentation only
end
```

They exist for documentation and potential future tooling. `MessageCache.where(...).all` returns raw Hashes, not `Message` instances.

### Cleanup in component_will_unmount

Always clean up subscriptions:

```ruby
def component_will_unmount
  @cache&.unsubscribe!
  @cache&.off_change(@cb_id) if @cb_id
end
```

Dangling subscriptions continue receiving Cable messages in the background.
