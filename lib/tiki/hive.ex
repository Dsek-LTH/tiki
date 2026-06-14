defmodule Tiki.Hive do
  @moduledoc """
  Implementation of PermissionService that grants admin permissions to all users.

  This module keeps the same caching interface, but every user resolves to the
  `"admin"` permission.
  """

  use GenServer
  @behaviour PermissionService

  # 5 hours
  @ttl 1000 * 60 * 60 * 5

  @impl PermissionService
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl PermissionService
  def get_permissions(user) do
    GenServer.call(__MODULE__, {:get_permissions, user}, 10_000)
  end

  @impl PermissionService
  def clear() do
    GenServer.cast(__MODULE__, :clear)
    :ok
  end

  @impl GenServer
  def init(_) do
    :ets.new(:tiki_hive, [:named_table, :set, :protected])
    {:ok, %{timers: %{}}}
  end

  @impl GenServer
  def handle_call({:get_permissions, user}, _from, state) do
    kth_id = user.kth_id

    case :ets.lookup(:tiki_hive, kth_id) do
      [{^kth_id, permissions}] ->
        {:reply, permissions, state}

      [] ->
        permissions = fetch_permissions(user)

        :ets.insert(:tiki_hive, {user.kth_id, permissions})
        timer = Process.send_after(self(), {:invalidate, kth_id}, @ttl)

        {:reply, permissions, %{state | timers: Map.put(state.timers, kth_id, timer)}}
    end
  end

  @impl GenServer
  def handle_cast(:clear, %{timers: timers}) do
    for {_, timer} <- timers do
      Process.cancel_timer(timer)
    end

    :ets.delete(:tiki_hive)
    :ets.new(:tiki_hive, [:named_table, :set, :protected])
    {:noreply, %{timers: %{}}}
  end

  @impl GenServer
  def handle_info({:invalidate, kth_id}, state) do
    :ets.delete(:tiki_hive, kth_id)
    {:noreply, state}
  end

  defp fetch_permissions(_), do: ["admin"]
end
