module Funicular
  class Store
    # Singleton store: one value per scope. Suitable for things like a
    # per-channel draft text or per-user preferences blob.
    #
    #   class DraftStore < Funicular::Store::Singleton
    #     database  "funicular_drafts"
    #     scope     :channel_id
    #     cleared_on :logout
    #   end
    #
    #   draft = DraftStore.where(channel_id: 1)
    #   draft.value = "hello"
    #   draft.value           # => "hello"
    #   draft.delete
    class Singleton < Store
      def self.scope_class
        Funicular::Store::Singleton::Scope
      end

      class Scope < Funicular::Store::Scope
        def value
          rec = read
          return nil unless rec.is_a?(Hash)
          if expired_record?(rec)
            erase
            return nil
          end
          rec["v"]
        end

        # Setting "" on a String-typed value deletes the entry, matching
        # the semantics of the original DraftStore.
        def value=(v)
          if v.is_a?(String) && v.empty?
            delete
            return v
          end
          write(v)
          fire_change(v)
          v
        end

        def delete
          erase
          fire_change(nil)
          nil
        end

        def present?
          !value.nil?
        end

        def expired?
          rec = read
          expired_record?(rec)
        end

        private

        def read
          kvs[storage_key]
        end

        def write(v)
          kvs[storage_key] = {
            "v" => v,
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
