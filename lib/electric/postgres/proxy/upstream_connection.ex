defmodule Electric.Postgres.Proxy.UpstreamConnection do
  use GenServer, restart: :transient

  alias PgProtocol.Message, as: M
  alias Electric.Postgres.Proxy.SASL
  alias Electric.Replication.Connectors

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def send_msg(pid, msgs) do
    GenServer.cast(pid, {:upstream, msgs})
  end

  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  @spec name(pos_integer) :: Electric.reg_name()
  def name(session_id) when is_integer(session_id) and session_id > 0 do
    Electric.name(__MODULE__, session_id)
  end

  @impl GenServer
  def init(args) do
    parent = Keyword.fetch!(args, :parent)
    connector_config = Keyword.fetch!(args, :connector_config)
    session_id = Keyword.fetch!(args, :session_id)

    name = name(session_id)
    Electric.reg(name)

    Logger.metadata(proxy_session_id: session_id)

    decoder = PgProtocol.Decoder.backend()
    conn_opts = Connectors.get_connection_opts(connector_config)

    {:ok,
     %{
       authenticated: false,
       sasl: nil,
       parent: parent,
       conn: nil,
       pending: [],
       decoder: decoder,
       conn_opts: conn_opts
     }, {:continue, {:connect, conn_opts}}}
  end

  @impl GenServer
  def handle_continue({:connect, conn_opts}, state) do
    host = conn_opts[:ip_addr] || conn_opts[:host] || ~c"localhost"
    port = conn_opts[:port] || 5432
    tcp_opts = [active: true] ++ List.wrap(conn_opts[:tcp_opts])

    Logger.debug(
      "Connecting to upstream PG cluster #{inspect(host)}:#{port} with options #{inspect(tcp_opts)}"
    )

    {:ok, conn} = :gen_tcp.connect(host, port, tcp_opts, 1000)
    {:noreply, %{state | conn: conn}, {:continue, {:authenticate, conn_opts}}}
  end

  def handle_continue({:authenticate, conn_opts}, state) do
    %{username: user, database: database} = conn_opts

    Logger.debug(
      "Authenticating to upstream database #{inspect(database)} as role #{inspect(user)}"
    )

    msg = %M.StartupMessage{
      params: %{
        "user" => user,
        "database" => database,
        "client_encoding" => "UTF-8",
        "application_name" => "electric"
      }
    }

    {:noreply, upstream(msg, state)}
  end

  @impl GenServer
  def handle_info({:tcp, _conn, data}, state) do
    {:ok, decoder, msgs} = PgProtocol.decode(state.decoder, data)

    state = handle_backend_msgs(msgs, %{state | decoder: decoder})

    {pending, state} =
      Map.get_and_update!(state, :pending, fn pending -> {Enum.reverse(pending), []} end)

    state = downstream(pending, state)

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _conn}, state) do
    {:stop, :normal, %{state | conn: nil}}
  end

  @impl GenServer
  def handle_cast({:upstream, msgs}, state) do
    {:noreply, upstream(msgs, state)}
  end

  @impl GenServer
  def handle_call(:disconnect, _from, state) do
    state = upstream(%M.Terminate{}, state)
    :ok = :gen_tcp.close(state.conn)
    {:stop, :normal, :ok, %{state | conn: nil}}
  end

  defp handle_backend_msgs(msgs, state) do
    Enum.reduce(msgs, state, &handle_backend_msg/2)
  end

  defp handle_backend_msg(%M.AuthenticationOk{}, %{authenticated: false} = state) do
    notify_parent(%{state | authenticated: true}, :authenticated)
  end

  defp handle_backend_msg(%M.AuthenticationSASL{} = msg, %{authenticated: false} = state) do
    {sasl_mechanism, response} = SASL.initial_response(msg)

    upstream(response, %{state | sasl: sasl_mechanism})
  end

  defp handle_backend_msg(%M.AuthenticationSASLContinue{} = msg, %{authenticated: false} = state) do
    {sasl_mechanism, response} = SASL.client_final_response(state.sasl, msg, state.conn_opts)

    upstream(response, %{state | sasl: sasl_mechanism})
  end

  defp handle_backend_msg(%M.AuthenticationSASLFinal{} = msg, %{authenticated: false} = state) do
    :ok = SASL.verify_server(state.sasl, msg, state.conn_opts)

    # upstream(response, %{state | sasl: nil})
    %{state | sasl: nil}
  end

  defp handle_backend_msg(msg, state) do
    %{state | pending: [msg | state.pending]}
  end

  defp downstream(msgs, %{parent: parent} = state) do
    send(parent, {:downstream, :msgs, msgs})
    state
  end

  defp upstream(msg, state) do
    :ok = :gen_tcp.send(state.conn, PgProtocol.encode(msg))
    state
  end

  defp notify_parent(state, tag) do
    send(state.parent, {__MODULE__, tag})
    state
  end
end
