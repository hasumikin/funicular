module Funicular
  class Store
    # Collection store: an ordered Array per scope, with bounded size and a
    # key proc that supports remove(id) / same_tail? semantics.
    #
    #   class MessageCache < Funicular::Store::Collection
    #     database "funicular_message_cache"
    #     scope    :channel_id
    #     limit    100
    #     key      ->(m) { m["id"] }
    #     cleared_on :logout
    #
    #     subscribes_to "ChatChannel",
    #                   params: ->(s) { { channel: "ChatChannel", channel_id: s.channel_id } } do |data, _scope|
    #       case data["type"]
    #       when "initial_messages" then replace(data["messages"] || [])
    #       when "new_message"      then append(data["message"])
    #       when "delete_message"   then remove(data["message_id"])
    #       end
    #     end
    #   end
    class Collection < Store
      DEFAULT_KEY_PROC = ->(item) {
        item.is_a?(Hash) ? item["id"] : nil
      }

      class << self
        attr_reader :__limit, :__order, :__key_proc

        def limit(n)
          @__limit = n
        end

        # :append (default) keeps the most recent items at the tail and caps
        # by truncating the head; :prepend caps by truncating the tail.
        def order(direction)
          @__order = direction.to_sym
        end

        def key(proc)
          @__key_proc = proc
        end

        def scope_class
          Funicular::Store::Collection::Scope
        end
      end

      class Scope < Funicular::Store::Scope
        def all
          rec = read
          return [] unless rec.is_a?(Hash)
          if expired_record?(rec)
            erase
            return []
          end
          items = rec["items"]
          items.is_a?(Array) ? items : []
        end

        def replace(arr)
          new_arr = cap(arr.is_a?(Array) ? arr : [])
          # Skip IndexedDB write if the cached snapshot already matches by
          # tail. Always fire callback so subscribers know replace completed
          # (e.g. to clear loading state).
          unless same_tail?(new_arr)
            write(new_arr)
          end
          fire_change(new_arr)
          new_arr
        end

        def append(item)
          new_arr = cap(append_to(all, item))
          write(new_arr)
          fire_change(new_arr)
          new_arr
        end

        def remove(id)
          cur = all
          kp = key_proc
          new_arr = cur.reject { |m| kp.call(m) == id }
          return cur if new_arr.size == cur.size
          write(new_arr)
          fire_change(new_arr)
          new_arr
        end

        def last
          arr = all
          arr.empty? ? nil : arr[arr.size - 1]
        end

        def last_id
          l = last
          return nil unless l
          key_proc.call(l)
        end

        def size
          all.size
        end

        def clear
          erase
          fire_change([])
          nil
        end

        def expired?
          rec = read
          expired_record?(rec)
        end

        # True iff `other` matches the current cached snapshot by size and
        # last-item key. Cheap staleness probe used by callers that already
        # have a fresh server response and want to skip a redundant
        # state-replace re-render.
        def same_tail?(other)
          return false unless other.is_a?(Array)
          cur = all
          return false if cur.size != other.size
          return true if cur.empty? && other.empty?
          kp = key_proc
          kp.call(cur[cur.size - 1]) == kp.call(other[other.size - 1])
        end

        private

        def key_proc
          @store_class.__key_proc || Funicular::Store::Collection::DEFAULT_KEY_PROC
        end

        def cap(arr)
          lim = @store_class.__limit
          return arr unless lim.is_a?(Integer) && lim < arr.size
          if @store_class.__order == :prepend
            arr[0, lim] || arr
          else
            arr[arr.size - lim, lim] || arr
          end
        end

        def append_to(arr, item)
          if @store_class.__order == :prepend
            [item] + arr
          else
            arr + [item]
          end
        end

        def read
          kvs[storage_key]
        end

        def write(items)
          kvs[storage_key] = {
            "items" => items,
            "wrote_at" => now_seconds,
            "expires_in" => @store_class.__expires_in
          }
        end

        def erase
          kvs.delete(storage_key)
        end
      end
    end
  end
end
