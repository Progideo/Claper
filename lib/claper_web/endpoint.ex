defmodule ClaperWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :claper

  @immutable_cache "public, max-age=31536000, immutable"

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_claper_key",
    signing_salt: "Tg18Y2zU",
    # 30 days
    max_age: 24 * 60 * 60 * 30
  ]

  socket "/audio", ClaperWeb.AudioSocket,
    websocket: [timeout: 120_000],
    longpoll: false

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [
        :peer_data,
        session: {__MODULE__, :runtime_opts, []}
      ]
    ]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :claper,
    gzip: true,
    brotli: true,
    cache_control_for_vsn_requests: @immutable_cache,
    only: ClaperWeb.static_paths()

  plug :cache_slide_images

  plug Plug.Static,
    at: "/uploads",
    from: Path.join([Application.compile_env(:claper, :storage_dir), "uploads"]),
    gzip: false

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :claper
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug ClaperWeb.NeoProDiagnosticsPlug

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  plug(:runtime_session)

  plug RemoteIp,
    proxies: {Application, :get_env, [:claper, :remote_ip_proxies, []]},
    headers: {Application, :get_env, [:claper, :remote_ip_headers, []]}

  plug ClaperWeb.Router

  defp cache_slide_images(
         %Plug.Conn{method: method, path_info: ["uploads", _hash, name]} = conn,
         _opts
       )
       when method in ["GET", "HEAD"] do
    if Regex.match?(~r/\A[0-9]+\.jpg\z/, name) do
      Plug.Conn.register_before_send(conn, fn
        %Plug.Conn{status: status} = conn when status in [200, 206, 304] ->
          Plug.Conn.put_resp_header(conn, "cache-control", @immutable_cache)

        conn ->
          conn
      end)
    else
      conn
    end
  end

  defp cache_slide_images(conn, _opts), do: conn

  def runtime_session(conn, _opts) do
    Plug.run(conn, [{Plug.Session, runtime_opts()}])
  end

  def runtime_opts() do
    @session_options
    |> Keyword.put(:same_site, Application.get_env(:claper, __MODULE__)[:same_site_cookie])
    |> Keyword.put(:secure, Application.get_env(:claper, __MODULE__)[:secure_cookie])
  end
end
