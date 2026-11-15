defmodule ClaperWeb.EventLive.PresenterNeoProTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.PresentationsFixtures

  alias Claper.Presentations

  setup [:register_and_log_in_user]

  setup %{user: user} do
    presentation_file = presentation_file_fixture(%{user: user, length: 30}, [:event])
    presentation_state_fixture(%{presentation_file: presentation_file, position: 0})
    %{event: presentation_file.event, presentation_file: presentation_file}
  end

  test "opens the embedded QR screen without changing the shared state", context do
    %{conn: conn, event: event, presentation_file: presentation_file} = context
    state = presentation_state(presentation_file)
    Phoenix.PubSub.subscribe(Claper.PubSub, "event:#{event.uuid}")
    Presentations.subscribe(presentation_file.id)

    {:ok, presenter, _html} =
      live(conn, ~p"/e/#{event.code}/presenter?iframe=1&screen=join&goto=1")

    assert has_element?(presenter, "#joinScreen.opacity-100 #qr[data-code=\"#{event.code}\"]")
    refute has_element?(presenter, "#presenter[data-goto-position]")
    assert has_element?(presenter, "#presenter[data-join-only]")
    refute has_element?(presenter, "#presenter[phx-hook]")
    refute has_element?(presenter, "#slides img")
    render_hook(presenter, "goto", %{})

    assert presentation_state(presentation_file) == state

    refute_received {:page_changed, _}
    refute_received {:state_updated, _}
  end

  test "renders only the requested iframe slide and replaces it when the position changes", %{
    conn: conn,
    event: event,
    presentation_file: presentation_file
  } do
    path = ~p"/e/#{event.code}/presenter?iframe=1&goto=17"
    assert slide_sources(html_response(get(conn, path), 200)) == ["/uploads/123456/18.jpg"]

    {:ok, presenter, html} = live(conn, path)
    assert slide_sources(html) == ["/uploads/123456/18.jpg"]
    render_hook(presenter, "goto", %{})

    {:ok, _state} =
      Presentations.change_page(event, presentation_state(presentation_file), 20)

    assert slide_sources(render(presenter)) == ["/uploads/123456/21.jpg"]
  end

  test "the regular presenter keeps the upstream view without iframe", %{conn: conn, event: event} do
    {:ok, presenter, html} = live(conn, ~p"/e/#{event.code}/presenter?screen=join")

    assert has_element?(presenter, "#presenter[phx-hook=Presenter] #slider")
    assert has_element?(presenter, "#joinScreen.opacity-0")
    assert slide_sources(html) == for(index <- 1..30, do: "/uploads/123456/#{index}.jpg")
    refute html =~ "Manrope"
  end

  defp slide_sources(html) do
    html |> Floki.parse_document!() |> Floki.attribute("#slides img", "src")
  end

  defp presentation_state(presentation_file) do
    Presentations.get_presentation_file!(presentation_file.id, [:presentation_state]).presentation_state
  end
end
