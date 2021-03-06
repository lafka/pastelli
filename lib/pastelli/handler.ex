defmodule Pastelli.Handler do
  @moduledoc false
  require Logger
  alias :elli_request, as: Request
  @behaviour :elli_handler

  def init(req, {_plug, _opts}) do
    Request.get_header("Upgrade", req) |> maybe_upgrade
  end

  defp maybe_upgrade("websocket"), do: {:ok, :handover}
  defp maybe_upgrade(_), do: {:ok, :standard}

  def handle(req, {plug, opts}) do
    try do
      Pastelli.Connection.build_from(req)
      |> plug.call(opts)
      |> process_connection(plug)
    catch
      :error, value ->
        stack = System.stacktrace()
        exception = Exception.normalize(:error, value, stack)
        Logger.error "[PLUG:CALL] #{inspect exception} \n #{inspect stack}"
    end
  end

  ### connection processors ###

  defp process_connection(%Plug.Conn{
    private: %{upgrade: {:websocket, ws_handler}},
    adapter: {_, req}}=conn, _plug) do
    :elli_websocket.upgrade req, handler: ws_handler, handler_opts: [conn: conn]
    {:close, ''}
  end

  # NOTE: [1]
  defp process_connection(%Plug.Conn{
    resp_body: {:file, filename, _offset, _length}}=conn, _plug) do
    resp_headers = [{"Connection", "close"} | conn.resp_headers]
    {conn.status, resp_headers, {:file, filename}}
  end

  defp process_connection(%Plug.Conn{state: :sent}=conn, _plug) do
    {conn.status, conn.resp_headers, conn.resp_body}
  end

  defp process_connection(%Plug.Conn{state: :chunked}=conn, _plug) do
    {:chunk, conn.resp_headers, conn.private[:init_chunk] || ""}
  end

  defp process_connection(%Plug.Conn{halted: :true}, _plug) do
    exit(:normal)
  end

  ### Elli Event handlers ###

  def handle_event :chunk_complete, [req, 200, _headers, _end, _timings], _args do
    Process.exit Request.chunk_ref(req), :chunk_complete
    :ok
  end

  def handle_event(other, one, two) do
    Logger.info "[EVENT]: #{inspect other} -- #{inspect one} -- #{inspect two}"
    :ok
  end

  # NOTES:
  # [1] -  elli seems to not close the connection on file
  #       request of HTTP version 1.1. Browser hangs unless we
  #       put the connection close header
  #       Also, translate _offset and _length into elli 'range' {a, b}
end
