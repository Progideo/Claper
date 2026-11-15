defmodule ClaperWeb.NeoProDiagnosticsTest do
  use ClaperWeb.ConnCase

  alias Claper.NeoProDiagnostics

  setup do
    original = Application.fetch_env(:claper, :neopro_diag_token)
    token = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
    Application.put_env(:claper, :neopro_diag_token, token)
    start_supervised!(NeoProDiagnostics)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:claper, :neopro_diag_token, value)
        :error -> Application.delete_env(:claper, :neopro_diag_token)
      end
    end)

    %{token: token}
  end

  test "requires the token and disables all routes when it is unset", %{conn: conn, token: token} do
    for path <- ["/neopro/diag", "/neopro/diag/log?token=wrong"] do
      assert response(get(conn, path), 404) == "Not found"
    end

    unauthorized =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/neopro/diag/events", "{")

    assert response(unauthorized, 404) == "Not found"
    Application.delete_env(:claper, :neopro_diag_token)

    assert response(get(conn, "/neopro/diag?token=" <> token), 404) == "Not found"
    assert response(post_event(conn, token, observation("A")), 404) == "Not found"
  end

  test "renders a standalone probe and protects its responses from caching", %{
    conn: conn,
    token: token
  } do
    probe = get(conn, "/neopro/diag?label=A&token=" <> token)
    html = html_response(probe, 200)
    assert html =~ ~s(<h1>A</h1>)
    assert html =~ "requestAnimationFrame"
    refute html =~ token
    refute html =~ "/assets/app"
    assert get_resp_header(probe, "cache-control") == ["no-store"]
    assert get_resp_header(probe, "referrer-policy") == ["no-referrer"]
    assert [policy] = get_resp_header(probe, "content-security-policy")
    assert policy =~ "script-src 'nonce-"
    assert policy =~ "connect-src 'self'"
  end

  test "records only valid observations and renders newest entries first", %{
    conn: conn,
    token: token
  } do
    assert response(post_event(conn, token, observation("A")), 204) == ""
    assert response(post_event(conn, token, observation("B", "<script>")), 204) == ""

    assert response(post_event(conn, token, observation("invalid!")), 400) ==
             "Invalid observation"

    assert response(post_event(conn, token, observation("C", String.duplicate("x", 300))), 400) ==
             "Invalid observation"

    oversized = post_event(conn, token, String.duplicate("x", 2_049))
    assert response(oversized, 413) == "Observation too large"

    page = html_response(get(conn, "/neopro/diag/log?token=" <> token), 200)

    assert Floki.find(Floki.parse_document!(page), "tbody tr")
           |> Enum.map(fn row ->
             row |> Floki.find("td") |> Enum.drop(1) |> Enum.map(&Floki.text/1)
           end) == [["B", "visibilitychange", "<script>"], ["A", "visibilitychange", "visible"]]

    refute page =~ "<script>"
    refute page =~ token
  end

  test "caps stored observations at one thousand", _context do
    for index <- 1..1_002 do
      :ok = NeoProDiagnostics.record("A", "resize", Integer.to_string(index))
    end

    events = NeoProDiagnostics.latest()
    assert length(events) == 1_000
    assert hd(events).detail == "1002"
    assert List.last(events).detail == "3"
  end

  test "limits bursts of submissions", %{conn: conn, token: token} do
    assert Enum.any?(1..361, fn _ ->
             post_event(conn, token, observation("A")).status == 429
           end)
  end

  defp observation(label, detail \\ "visible") do
    Jason.encode!(%{label: label, signal: "visibilitychange", detail: detail})
  end

  defp post_event(conn, token, body) do
    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "text/plain")
    |> post("/neopro/diag/events", body)
  end
end
