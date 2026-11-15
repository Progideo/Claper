defmodule ClaperWeb.CourseControllerTest do
  use ClaperWeb.ConnCase

  import Claper.EventsFixtures

  setup [:register_and_log_in_user]

  test "redirects to the owner's matching event and preserves the query string", %{
    conn: conn,
    user: user
  } do
    event = event_fixture(%{user: user, name: "ISTQB Testeur Ágile v2.0 (Copy)"})
    event_fixture(%{name: "ISTQB Testeur Agile v2.0"})
    query = "?iframe=1&goto=0&tag=x%20y&tag=z"
    course = "istqb-testeur-agile-v2-0"

    assert redirected_to(get(conn, ~p"/c/#{course}/presenter" <> query)) ==
             ~p"/e/#{event.code}/presenter" <> query

    assert redirected_to(get(conn, ~p"/c/#{course}/manage" <> query)) ==
             ~p"/e/#{event.code}/manage" <> query
  end

  test "takes the newest match among non-expired events", %{conn: conn, user: user} do
    event_fixture(%{user: user, name: "Formation Agile"})
    newest = event_fixture(%{user: user, name: "Formation Agile (Copy)"})

    event_fixture(%{
      user: user,
      name: "Formation Agile (Copy)",
      expired_at: ~N[2025-01-01 00:00:00]
    })

    assert redirected_to(get(conn, ~p"/c/formation-agile/presenter")) ==
             ~p"/e/#{newest.code}/presenter"
  end

  test "identifies the course and explains how to create a matching event", %{conn: conn} do
    html = conn |> get(~p"/c/formation-agile/presenter") |> html_response(404)

    assert html =~ "formation-agile"
    assert html =~ "Duplicate the event template"
  end

  test "saves the requested path and query before redirecting to login" do
    path = ~p"/c/formation-agile/presenter?iframe=1&goto=2"
    conn = get(build_conn(), path)

    assert redirected_to(conn) == ~p"/users/log_in"
    assert get_session(conn, :user_return_to) == path
  end
end
