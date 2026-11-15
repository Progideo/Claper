defmodule Claper.NeoProDiagnostics do
  @moduledoc "Keeps the last slideshow observations in memory for this instance."
  use GenServer

  @capacity 1_000

  def token do
    case Application.get_env(:claper, :neopro_diag_token) do
      value when is_binary(value) and byte_size(value) > 0 -> value
      _ -> nil
    end
  end

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def record(label, signal, detail) do
    GenServer.call(__MODULE__, {:record, label, signal, detail})
  end

  def latest, do: GenServer.call(__MODULE__, :latest)

  @impl true
  def init(nil), do: {:ok, {:queue.new(), 0}}

  @impl true
  def handle_call({:record, label, signal, detail}, _from, {queue, size}) do
    event = %{at: DateTime.utc_now(), label: label, signal: signal, detail: detail}
    queue = :queue.in(event, queue)

    if size == @capacity do
      {:reply, :ok, {:queue.drop(queue), size}}
    else
      {:reply, :ok, {queue, size + 1}}
    end
  end

  def handle_call(:latest, _from, {queue, _size} = state) do
    events =
      queue |> :queue.to_list() |> Enum.reverse() |> Enum.sort_by(& &1.at, {:desc, DateTime})

    {:reply, events, state}
  end
end
