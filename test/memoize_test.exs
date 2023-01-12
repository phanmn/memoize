defmodule MemoizeTest do
  use Memoize.Case

  use Memoize

  defmemo foo(x, y) when x == 0 do
    y
  end

  defmemo foo(1, y) do
    y * 2
  end

  defmemo foo(x, y, z \\ 0) when x == 2 do
    y * z
  end

  defmemo barz(x, y, pid) do
    message =
      :ets.lookup(Memoize.CacheStrategy.Default, {MemoizeTest, :barz, [x, y, pid]})
      |> case do
        [{{MemoizeTest, :barz, [^x, ^y, ^pid]}, {:running, _, _}}] ->
          :running

        _ ->
          :completed
      end

    send(pid, message)

    foos(x, y)

    x + y
  end

  defmemo foos(x, y), back_end: :persistent_term do
    Process.sleep(5000)
    x - y
  end

  test "defmemo persistent term foos" do
    assert 27 == foos(30, 3)
    assert 27 == foos(30, 3)
  end

  test "10 processes calling persistent term foos" do
    for _ <- 1..10 do
      spawn(fn ->
        foos(30, 3)
      end)
    end

    assert 27 == foos(30, 3)
  end

  test "persistent_term cache when ets cache is running" do
    pid = self()

    spawn(fn ->
      barz(10, 5, pid)
    end)

    assert_receive(:running, 5000)
    Process.sleep(6000)

    assert [{{MemoizeTest, :barz, [10, 5, ^pid]}, {:completed, 15, :infinity}}] =
             :ets.lookup(Memoize.CacheStrategy.Default, {MemoizeTest, :barz, [10, 5, pid]})
  end

  test "defmemo defines foo" do
    assert 2 == foo(0, 2)
    assert 8 == foo(1, 4)
    assert 0 == foo(2, 4)
    assert 40 == foo(2, 4, 10)
  end

  defmemo bar(x, y) do
    x + y
  end

  defmemo bar(x, y, z) do
    x + y + z
  end

  test "defmemo defines bar" do
    assert 3 == bar(1, 2)
    assert 7 == bar(1, 2, 4)
  end

  defmemop pri() do
    10
  end

  test "defmemop defines pri" do
    assert 10 == pri()
  end

  test "invalidates cached values when call invalidate/{0-3}" do
    f = fn -> 10 end

    Memoize.Cache.invalidate()
    Memoize.Cache.get_or_run({:mod1, :fun1, [1]}, f)
    Memoize.Cache.get_or_run({:mod1, :fun1, [2]}, f)
    Memoize.Cache.get_or_run({:mod1, :fun2, [1]}, f)
    Memoize.Cache.get_or_run({:mod2, :fun1, [1]}, f)

    assert 1 == Memoize.invalidate(:mod1, :fun1, [1])
    assert 0 == Memoize.invalidate(:mod1, :fun1, [1])
    assert 1 == Memoize.invalidate(:mod1, :fun1)
    assert 1 == Memoize.invalidate(:mod1)

    Memoize.Cache.get_or_run({:mod1, :fun1, [%{a: 1}]}, f)
    assert 1 == Memoize.invalidate(:mod1, :fun1, [%{a: 1}])

    assert 1 == Memoize.invalidate()
  end

  defmemo(nothing_do(x))
  defmemo(nothing_do(x) when x == 0, do: 0)
  defmemo(nothing_do(x) when x == 1, do: x * 2)

  test "even if the `def` function has not `do`, defmemo is passed" do
    assert 0 == nothing_do(0)
    assert 2 == nothing_do(1)
  end

  defmemo has_expire(pid), expires_in: 100 do
    send(pid, :ok)
  end

  @tag cache: "default"
  test "defmemo with expire" do
    assert :ok == has_expire(self())
    assert_received :ok

    # cached
    assert :ok == has_expire(self())
    refute_received _

    # wait to expire
    Process.sleep(120)
    assert :ok == has_expire(self())
    assert_received :ok

    # cached
    assert :ok == has_expire(self())
    refute_received _
  end

  defmodule Tarai do
    use Memoize
    defmemo(tarai(x, y, _z) when x <= y, do: y)

    defmemo tarai(x, y, z) do
      tarai(tarai(x - 1, y, z), tarai(y - 1, z, x), tarai(z - 1, x, y))
    end
  end

  test "tarai" do
    assert 12 == Tarai.tarai(12, 6, 0)
  end

  defmemo accepts_map_type(value) do
    value
  end

  test "accepts map type" do
    value = DateTime.from_iso8601("2000-02-29T06:20:00Z")
    assert value == accepts_map_type(value)
    map = %{a: 10, b: 20}
    nested_map = %{c: 30, d: map}
    keyword = [a: 10, b: 20]
    tuple = {{:a, 10}, {:b, 20}}
    fun = fn -> :ok end
    gocha = {map, nested_map, keyword, tuple, fun}
    assert map == accepts_map_type(map)
    assert nested_map == accepts_map_type(nested_map)
    assert keyword == accepts_map_type(keyword)
    assert tuple == accepts_map_type(tuple)
    assert fun == accepts_map_type(fun)
    assert gocha == accepts_map_type(gocha)
  end

  # test defmemo with unquote
  name = :foobar
  defmemo(unquote(name)())

  defmemo unquote(name)() do
    123
  end

  defmemo unquote(name)(1, y) when y == 2 do
    456
  end

  defmemo unquote(name)(_x, _y, _z \\ 3) do
    789
  end

  test "defmemo with unquote" do
    assert 123 == foobar()
    assert 456 == foobar(1, 2)
    assert 789 == foobar(2, 2)
    assert 789 == foobar(1, 2, 3)
  end

  defmemo waiter_config(), max_waiters: 1, waiter_sleep_ms: 10 do
    Process.sleep(100)
    1234
  end

  test "defmemo with waiter config" do
    ps =
      for _ <- 1..100, into: %{} do
        {pid, ref} =
          Process.spawn(
            fn ->
              assert 1234 == waiter_config()
            end,
            [:monitor]
          )

        {pid, ref}
      end

    for _ <- 1..100 do
      receive do
        {:DOWN, ref, :process, pid, reason} ->
          assert ps[pid] == ref
          assert reason == :normal
      end
    end
  end
end
