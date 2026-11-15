defmodule ClaperWeb.CourseControllerTest do
  use ClaperWeb.ConnCase

  import Claper.AccountsFixtures
  import Claper.EventsFixtures

  alias Claper.Repo

  setup [:register_and_log_in_user]

  test "redirects the owner to the matching copy and preserves the query string", %{
    conn: conn,
    user: user
  } do
    event = event_fixture(%{user: user, name: "ISTQB Testeur Ágile v2.0 (Copy)"})
    query = "?iframe=1&goto=0&screen=join&tag=x%20y&tag=z"
    course = "istqb-testeur-agile-v2-0"

    assert redirected_to(get(conn, ~p"/c/#{course}/presenter" <> query)) ==
             ~p"/e/#{event.code}/presenter" <> query

    assert redirected_to(get(conn, ~p"/c/#{course}/manage" <> query)) ==
             ~p"/e/#{event.code}/manage" <> query
  end

  test "two facilitators resolve to their own copies of the same course", %{
    conn: conn,
    user: user
  } do
    owner = user_fixture()
    other_facilitator = user_fixture()
    first = event_fixture(%{user: owner, name: "Formation Agile (Copy)"})
    second = event_fixture(%{user: owner, name: "Formation Agile – Lyon"})
    activity_leader_fixture(%{event: first, user: user})
    activity_leader_fixture(%{event: second, user: other_facilitator})
    other_conn = log_in_user(build_conn(), other_facilitator)

    assert redirected_to(get(conn, ~p"/c/formation-agile/presenter")) ==
             ~p"/e/#{first.code}/presenter"

    assert redirected_to(get(other_conn, ~p"/c/formation-agile/presenter")) ==
             ~p"/e/#{second.code}/presenter"

    assert redirected_to(get(conn, ~p"/c/formation-agile/manage")) == ~p"/e/#{first.code}/manage"
  end

  test "ranks owned and shared copies together by start date", %{conn: conn, user: user} do
    newest =
      event_fixture(%{name: "Formation Agile – Lyon", started_at: ~N[2025-01-03 00:00:00]})

    older =
      event_fixture(%{name: "Formation Agile – Paris", started_at: ~N[2025-01-02 00:00:00]})

    activity_leader_fixture(%{event: newest, user: user})
    activity_leader_fixture(%{event: older, user: user})

    event_fixture(%{
      user: user,
      name: "Formation Agile (Copy)",
      started_at: ~N[2025-01-01 00:00:00]
    })

    assert redirected_to(get(conn, ~p"/c/formation-agile/presenter")) ==
             ~p"/e/#{newest.code}/presenter"
  end

  test "uses the insertion date to break a tie between start dates", %{conn: conn, user: user} do
    start = ~N[2025-02-01 00:00:00]
    first = event_fixture(%{name: "Formation Agile – Lyon", started_at: start})
    second = event_fixture(%{name: "Formation Agile – Paris", started_at: start})
    activity_leader_fixture(%{event: first, user: user})
    activity_leader_fixture(%{event: second, user: user})

    first
    |> Ecto.Changeset.change(inserted_at: ~N[2025-01-02 00:00:00])
    |> Repo.update!()

    second
    |> Ecto.Changeset.change(inserted_at: ~N[2025-01-01 00:00:00])
    |> Repo.update!()

    assert redirected_to(get(conn, ~p"/c/formation-agile/manage")) == ~p"/e/#{first.code}/manage"
  end

  test "never resolves an exact template name, even for its owner", %{conn: conn, user: user} do
    event_fixture(%{user: user, name: "Formation Ágile"})

    assert conn |> get(~p"/c/formation-agile/presenter") |> html_response(404) =~
             "No active session is shared with this account for formation-agile"
  end

  test "ignores expired copies shared with the user", %{conn: conn, user: user} do
    active = event_fixture(%{name: "Formation Agile – Lyon", started_at: ~N[2025-01-01 00:00:00]})

    expired =
      event_fixture(%{
        name: "Formation Agile – Paris",
        started_at: ~N[2025-01-02 00:00:00],
        expired_at: ~N[2025-01-03 00:00:00]
      })

    activity_leader_fixture(%{event: active, user: user})
    activity_leader_fixture(%{event: expired, user: user})

    assert redirected_to(get(conn, ~p"/c/formation-agile/presenter")) ==
             ~p"/e/#{active.code}/presenter"
  end

  test "shows sharing instructions without redirecting a user outside the session", %{conn: conn} do
    event = event_fixture(%{name: "Formation Agile (Copy)"})
    activity_leader_fixture(%{event: event})

    response = get(conn, ~p"/c/formation-agile/presenter")
    html = html_response(response, 404)

    assert html =~ "formation-agile"
    assert html =~ "Ask for a copy of the course event template"
    assert html =~ "have this account added as a facilitator"
    assert get_resp_header(response, "location") == []
  end

  test "switches accounts and returns to the exact course URL after signing in", %{
    conn: conn,
    user: user
  } do
    second_user = confirmed_user_fixture()
    event = event_fixture(%{name: "Formation Agile (Copy)", user: second_user})
    path = ~p"/c/formation-agile/presenter" <> "?iframe=1&goto=2&tag=x%20y&tag=z"
    token = get_session(conn, :user_token)

    response = get(conn, path)
    html = html_response(response, 404)
    assert html =~ user.email
    assert html =~ "Switch account"
    assert Floki.attribute(Floki.parse_document!(html), "form[method=post]", "action") == [path]

    switched = post(recycle(response), path, %{"return_to" => "https://example.org/"})
    assert redirected_to(switched) == ~p"/users/log_in"
    assert get_session(switched, :user_return_to) == path
    refute get_session(switched, :user_token)
    refute Claper.Accounts.get_user_by_session_token(token)

    logged_in =
      post(recycle(switched), ~p"/users/log_in", %{
        "user" => %{"email" => second_user.email, "password" => valid_user_password()}
      })

    assert redirected_to(logged_in) == path

    assert redirected_to(get(recycle(logged_in), path)) ==
             ~p"/e/#{event.code}/presenter" <> "?iframe=1&goto=2&tag=x%20y&tag=z"
  end

  test "returns to the requested course path and query after login", %{user: user} do
    event = event_fixture(%{name: "Formation Agile (Copy)"})
    activity_leader_fixture(%{event: event, user: user})
    path = ~p"/c/formation-agile/presenter?iframe=1&goto=2"
    conn = get(build_conn(), path)

    assert redirected_to(conn) == ~p"/users/log_in"
    assert get_session(conn, :user_return_to) == path

    logged_in =
      post(recycle(conn), ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    assert redirected_to(logged_in) == path

    assert redirected_to(get(recycle(logged_in), path)) ==
             ~p"/e/#{event.code}/presenter?iframe=1&goto=2"
  end
end
