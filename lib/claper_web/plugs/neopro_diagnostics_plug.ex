defmodule ClaperWeb.NeoProDiagnosticsPlug do
  @moduledoc "Serves the opt-in slideshow probe before the endpoint's body parsers."
  @behaviour Plug

  import Plug.Conn
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.{NeoProDiagnostics, RateLimit}

  @max_body 2_048
  @max_query 1_024
  @max_events 180
  @interval 10_000
  @signals ~w(start visibilitychange focus blur pageshow pagehide freeze resume resize
              resize-observer intersection animation-resumed interval-lag message)

  embed_templates "neopro_diag/*"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: ["neopro", "diag" | route]} = conn, _opts) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> put_resp_header("x-content-type-options", "nosniff")

    case NeoProDiagnostics.token() do
      nil -> reply(conn, 404, "Not found")
      token -> authorize(conn, route, token)
    end
  end

  def call(conn, _opts), do: conn

  defp authorize(%{method: "POST"} = conn, ["events"], token) do
    with ["Bearer " <> given] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(given, token) do
      receive_event(conn, token)
    else
      _ -> reply(conn, 404, "Not found")
    end
  end

  defp authorize(%{method: "GET", query_string: query} = conn, route, token)
       when byte_size(query) <= @max_query do
    conn = fetch_query_params(conn, length: @max_query, validate_utf8: false)

    case conn.query_params["token"] do
      given when is_binary(given) ->
        if Plug.Crypto.secure_compare(given, token),
          do: page(conn, route),
          else: reply(conn, 404, "Not found")

      _ ->
        reply(conn, 404, "Not found")
    end
  end

  defp authorize(conn, _route, _token), do: reply(conn, 404, "Not found")

  defp page(conn, []) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    label = conn.query_params["label"]

    render_page(conn, :probe, %{
      nonce: nonce,
      label: if(valid_label?(label), do: label, else: "Frame")
    })
  end

  defp page(conn, ["log"]), do: render_page(conn, :journal, %{events: NeoProDiagnostics.latest()})
  defp page(conn, _route), do: reply(conn, 404, "Not found")

  defp render_page(conn, template, assigns) do
    locale =
      conn
      |> ClaperWeb.Plugs.Locale.extract_accept_language()
      |> Enum.find(&(&1 in Gettext.known_locales(ClaperWeb.Gettext)))

    if locale, do: Gettext.put_locale(ClaperWeb.Gettext, locale)
    assigns = Map.put(assigns, :locale, Gettext.get_locale(ClaperWeb.Gettext))
    script_src = if assigns[:nonce], do: "'nonce-#{assigns.nonce}'", else: "'none'"
    rendered = if template == :probe, do: probe(assigns), else: journal(assigns)

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header(
      "content-security-policy",
      "default-src 'none'; script-src #{script_src}; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'"
    )
    |> send_resp(200, Phoenix.HTML.Safe.to_iodata(rendered))
    |> halt()
  end

  defp receive_event(conn, token) do
    key = "neopro_diag:" <> :crypto.hash(:sha256, token)

    case RateLimit.hit(key, @interval, @max_events) do
      {:allow, _count} -> read_event(conn)
      {:deny, _retry_after} -> reply(conn, 429, "Too many observations")
    end
  end

  defp read_event(conn) do
    case read_body(conn, length: @max_body, read_length: @max_body, read_timeout: 2_000) do
      {:ok, body, conn} when byte_size(body) <= @max_body -> parse_event(conn, body)
      {:ok, _body, conn} -> reply(conn, 413, "Observation too large")
      {:more, _body, conn} -> reply(conn, 413, "Observation too large")
      {:error, _reason} -> reply(conn, 400, "Invalid observation")
    end
  end

  defp parse_event(conn, body) do
    with {:ok, %{"label" => label, "signal" => signal, "detail" => detail}} <- Jason.decode(body),
         true <- valid_label?(label) and signal in @signals,
         true <- is_binary(detail) and byte_size(detail) <= 256 and String.valid?(detail) do
      :ok = NeoProDiagnostics.record(label, signal, detail)
      reply(conn, 204, "")
    else
      _ -> reply(conn, 400, "Invalid observation")
    end
  end

  defp valid_label?(label) when is_binary(label) and byte_size(label) in 1..32 do
    Regex.match?(~r/\A[A-Za-z0-9 _-]+\z/, label)
  end

  defp valid_label?(_), do: false

  defp reply(conn, status, body) do
    conn |> put_resp_content_type("text/plain") |> send_resp(status, body) |> halt()
  end
end
