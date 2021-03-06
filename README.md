# Pastelli ![travis](https://travis-ci.org/zampino/pastelli.svg)

![alt](logo.png)

Pastelli is a colorful Plug adapter for [Elli](//github.com/knutin/elli)
with a focus on streaming over chunked
connections (read `EventSource`).

For the moment, this is quite alpha and
it implements almost all (see below) of the `Plug.Conn.Adapter` behaviour.

## Usage
As you would do with your beloved `Plug.Adapters.Cowboy`,
you'll type:

```elixir
Pastelli.http MyPlug.Router, [], [port: 4001]
```
Now setup your router (or simpler plug) as usual.
Pastelli changes the semantics of EventSource chunked responses,
in which it doesn't block your router dispatch:

```elixir
defmodule MyPlug.Router do
  use Plug.Router
  plug :match
  plug :dispatch

  get "/connections/:id" do
    put_resp_content_type(conn, "text/event-stream")
    |> send_chunked(200)
    |> register_stream(id)
    # dispatch doesn't need to block execution,
    # it enters a chunk loop just after pipeline resolution,
    # waiting for chunk messages
  end

  defp register_stream(conn, id) do
    {:ok, pid} = MyPlug.Connections.register id, conn
    # usually a :simple_one_for_one supervised
    # event manager

    Process.link pid
    # we link the process to the streaming manager!
    # once the chunk is complete (client closes socket or crashes)
    # pastelli handler will send a `chunk_complete` exit signal
    # to the connection process.
    # It is your responsibility to monitor the event manager and
    # react on such exits
    conn
  end
end
```

## A Streaming DSL
`Pastelli.Router` wraps an extra [`stream`](//github.com/zampino/pastelli/blob/master/lib/pastelli/router.ex) macro around `Plug.Router` and
imports `Pastelli.Conn`, a module with a few extra functions to manipulate
`Plug.Conn` chunked-state structs.

```elixir
defmodule MyPlug.Router do
  use Pastelli.Router
  plug :match
  plug :dispatch

  stream "/connections" do
    init_chunk(conn, %{text: "hallo!"}, event: :handshake, retry: 6000, id: 1234)
    # sends an initial chunk to event source as early as plug pipeline ends
    |> register_stream()
  end
end
```

from wherever you can access the connection struct,
`Pastelli.Conn.event/2,3` serializes non-binary message body and
meta data.

```elixir
Pastelli.Conn.event(conn, %{some: "map"}, event: "message", id: "x4x3", retry: 6000)
```

## Examples
Event Source based [remote control](https://github.com/zampino/plug_rc) backend
for remote controlling presentation slides.

## Web Sockets
Pastelli upgrades to Web Sockets thanks to mmzeeman's [elli_websockets](https://github.com/mmzeeman/elli_websocket).

Pass an elli_websocket
[handler](https://github.com/mmzeeman/elli_websocket#callback-module) in the private
map of your connection. This will receive the current connection as option argument.

```elixir
  get "/ws" do
    put_private(conn, :upgrade, {:websocket, WebSocketHandler})
  end

  defmodule WebSocketHandler do
    def websocket_init(request, conn: %Plug.Conn{} = conn) do
      # ...
    end
    def websocket_handle() # handle callback
    def websocket_info() # info callback
  end
```

## Pastelli and Phoenix

With version `1.1.0` or newer of
[Phoenix](htts://phoenixframework.org)
we can allow different servers other than Cowboy at the heart of the framework.
It's enough to provide a suitable
[endpoint handler behaviour](https://github.com/phoenixframework/phoenix/blob/v1.1.0/lib/phoenix/endpoint/handler.ex).

With [`Pastelli.Phoenix`](https://github.com/zampino/pastelli_phoenix) you
can have Elli serve Phoenix. Check also this [example](https://github.com/zampino/phoenix-on-pastelli) out.

## Pastelli tries to help!

The current built-in Plug cowboy adapter does not notify the
connection owner process of the EventSource client
closing the socket (or just crashing).
More precisely, Pastelli tries to address this [issue](https://github.com/elixir-lang/plug/issues/228).

## `Plug.Conn.Adapter` behaviour currently covered by pastelli

- [x] send_resp
- [x] send_file
- [x] send_chunked
- [x] chunk
- [x] read_req_body
- [ ] parse_req_multipart

## `Plug.Conn` extensions (`Pastelli.Conn`)

- init_chunk/2, init_chunk/3
- event/2, event/3
- close_chunk/0

## Agenda

- [x] run http
- [ ] run https
- [x] websocket upgrade via mmzeeman/elli_websocket
- [x] Plug.Conn extensions
- [x] Pastelli.Router streaming DSL
- [ ] ExDoc
- [ ] hex package
