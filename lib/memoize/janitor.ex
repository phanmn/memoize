defmodule Memoize.Janitor do
  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_) do
    send_after = Application.get_env(:memoize, :interval, 5_000)
    Process.send_after(self(), :garbage_collect, send_after)

    {:ok,
     %{
       send_after: send_after
     }}
  end

  @impl true
  def handle_info(:garbage_collect, state) do
    Memoize.garbage_collect()

    Process.send_after(self(), :garbage_collect, state.send_after)
    {:noreply, state}
  end
end
