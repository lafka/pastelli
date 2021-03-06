defmodule Pastelli.Connection do
  @moduledoc false
  require Record
  @behaviour Plug.Conn.Adapter

  alias Pastelli.Connection.NotImplementedError
  alias :elli_request, as: Request
  Record.defrecordp :elli_req, Record.extract(:req, from_lib: "elli/include/elli.hrl")

  def build_from(req) do
    headers = Request.headers(req)
    host_port = Enum.find_value headers, fn({name, value})->
      (name == "Host") && value
    end
    [host | and_port] = String.split(host_port, ":")
    port = List.first and_port

    req_headers = downcase_keys(headers)
    |> ensure_origin(host_port)

    %Plug.Conn{
      adapter: {__MODULE__, req},
      host: host,
      port: port,
      method: Request.method(req) |> to_string(),
      owner: self,
      peer: get_peer(req),
      path_info: Request.path(req),
      query_string: Request.query_str(req),
      req_headers: req_headers,
      scheme: :http
    }
  end

  ## Plug.Conn.Adapter callbacks ##

  def read_req_body(req, _options) do
    {:ok, Request.body(req), req}
  end

  def send_resp(req, _status, _headers, body) do
    {:ok, body, req}
  end

  def send_chunked(req, _status, _headers) do
    {:ok, nil, req}
  end

  def chunk(req, body) do
    case Request.chunk_ref(req) |> Request.send_chunk(body) do
      {:ok, _pid} ->
        :ok
      {:error, reason} ->
        {:error, reason}
      :ok ->
        :ok
    end
  end

  def send_file(req, _status, _resp_headers, file, offset, length) do
    {:ok, {:file, file, offset, length}, req}
  end

  def parse_req_multipart(_, _, _), do: raise(NotImplementedError, 'parse_req_multipart')

  ## pastelli extra callback ##

  def close_chunk(req) do
    Request.chunk_ref(req) |> Request.close_chunk()
    :ok
  end

  defp downcase_keys(headers) do
    downcase_key = fn({key, value})->
      {String.downcase(key), value}
    end
    Enum.map headers, downcase_key
  end

  defp ensure_origin(headers, origin) do
    get_origin = fn({name, value})->
      (name == "origin") && value
    end
    case Enum.find_value(headers, get_origin) do
      nil -> [{"origin", origin} | headers]
      _ -> headers
    end
  end

  defp get_peer(req) do
    case elli_req(req, :socket) do
      :undefined ->
        {:undefined, :undefined}
      socket ->
        {:ok, {address, port}} = :elli_tcp.peername(socket)
        {address, port}
    end
  end

  defmodule NotImplementedError do
    defexception [:message]

    def exception(method) do
      message = "#{inspect(method)} is not supported by Pastelli.Connection yet"
      %__MODULE__{message: message}
    end
  end
end
