defmodule Memoize.Tags do
  @moduledoc """
  Tracks which cache keys are tagged with which application-defined tags, so a
  whole set of related cache entries can be invalidated by tag instead of by
  exact `{module, function, arguments}` match.

  Both `Memoize.CacheStrategy.Default` and `Memoize.CacheStrategy.Eviction`
  call `delete_key/1` for every concrete key they remove — whether that
  removal comes from an explicit `invalidate`, a lazily-detected expiry on
  read, or a `garbage_collect/0` sweep — so the tag index does not
  accumulate stale entries on its own.
  """

  @tag_to_keys __MODULE__.TagToKeys
  @key_to_tags __MODULE__.KeyToTags

  def init() do
    :ets.new(@tag_to_keys, [:public, :bag, :named_table, {:read_concurrency, true}])
    :ets.new(@key_to_tags, [:public, :bag, :named_table, {:read_concurrency, true}])
    :ok
  end

  @doc "Associates `key` with `tags`, replacing any tags previously stored for `key`."
  def put(_key, []), do: :ok

  def put(key, tags) do
    delete_key(key)

    for tag <- tags do
      :ets.insert(@tag_to_keys, {tag, key})
      :ets.insert(@key_to_tags, {key, tag})
    end

    :ok
  end

  @doc "All cache keys currently associated with `tag`."
  def keys_for_tag(tag) do
    :ets.lookup(@tag_to_keys, tag) |> Enum.map(fn {_tag, key} -> key end)
  end

  @doc "Removes `key` and its tag associations from the index."
  def delete_key(key) do
    for {_key, tag} <- :ets.lookup(@key_to_tags, key) do
      :ets.delete_object(@tag_to_keys, {tag, key})
    end

    :ets.delete(@key_to_tags, key)
    :ok
  end

  @doc "Drops the whole index."
  def delete_all() do
    :ets.delete_all_objects(@tag_to_keys)
    :ets.delete_all_objects(@key_to_tags)
    :ok
  end
end
