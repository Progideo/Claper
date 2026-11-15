defmodule ClaperWeb.EventLive.PresenterGotoTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{AccountsFixtures, EventsFixtures, PollsFixtures, PresentationsFixtures}

  alias Claper.Presentations

  setup [:register_and_log_in_user]

  setup %{user: user} do
    presentation_file = presentation_file_fixture(%{user: user, length: 2}, [:event])
    state = presentation_state_fixture(%{presentation_file: presentation_file, position: 0})

    poll_fixture(%{
      presentation_file_id: presentation_file.id,
      position: 1,
      title: "Second question"
    })

    %{event: presentation_file.event, presentation_file: presentation_file, state: state}
  end

  test "changes the page once and updates connected attendees", context do
    %{conn: conn, event: event, presentation_file: presentation_file, state: state} = context
    Phoenix.PubSub.subscribe(Claper.PubSub, "event:#{event.uuid}")
    Presentations.subscribe(presentation_file.id)
    {:ok, attendee, _html} = live(build_conn(), ~p"/e/#{event.code}")
    {:ok, presenter, _html} = live(conn, ~p"/e/#{event.code}/presenter?iframe=1&goto=1")

    assert position(presentation_file) == 0
    render_hook(presenter, "goto", %{})
    assert position(presentation_file) == 1
    assert_receive {:page_changed, 1}
    assert_receive {:state_updated, %{position: 1}}
    assert render(attendee) =~ "Second question"
    assert has_element?(presenter, "#poll.opacity-100", "Second question")

    {:ok, _state} = Presentations.change_page(event, state, 0)
    assert_receive {:page_changed, 0}
    assert_receive {:state_updated, %{position: 0}}
    render_hook(presenter, "goto", %{})
    assert position(presentation_file) == 0
    refute_received {:page_changed, 1}
  end

  test "a facilitator can open the manager and use goto to update connected attendees", %{
    event: event,
    presentation_file: presentation_file
  } do
    facilitator = user_fixture()
    activity_leader_fixture(%{event: event, user: facilitator})
    conn = log_in_user(build_conn(), facilitator)

    Phoenix.PubSub.subscribe(Claper.PubSub, "event:#{event.uuid}")
    Presentations.subscribe(presentation_file.id)
    {:ok, _manager, _html} = live(conn, ~p"/e/#{event.code}/manage")
    {:ok, attendee, _html} = live(build_conn(), ~p"/e/#{event.code}")
    {:ok, presenter, _html} = live(conn, ~p"/e/#{event.code}/presenter?iframe=1&goto=1")

    assert position(presentation_file) == 0
    render_hook(presenter, "goto", %{})
    assert position(presentation_file) == 1
    assert_receive {:page_changed, 1}
    assert_receive {:state_updated, %{position: 1}}
    assert render(attendee) =~ "Second question"
    assert has_element?(presenter, "#poll.opacity-100", "Second question")
  end

  test "does not broadcast for the current position, missing values, or invalid values",
       context do
    %{conn: conn, event: event, presentation_file: presentation_file} = context
    Phoenix.PubSub.subscribe(Claper.PubSub, "event:#{event.uuid}")
    Presentations.subscribe(presentation_file.id)
    path = ~p"/e/#{event.code}/presenter"

    for query <- ["", "?goto=0", "?goto=-1", "?goto=1.5", "?goto=abc", "?goto=2147483648"] do
      {:ok, presenter, _html} = live(conn, path <> query)
      render_hook(presenter, "goto", %{})
      assert position(presentation_file) == 0
    end

    refute_received {:page_changed, _}
    refute_received {:state_updated, _}
  end

  test "does not change the page for a user outside the event", %{
    event: event,
    presentation_file: presentation_file
  } do
    conn = log_in_user(build_conn(), user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/e/#{event.code}/presenter?goto=1")
    assert position(presentation_file) == 0
  end

  defp position(presentation_file) do
    Presentations.get_presentation_file!(presentation_file.id, [:presentation_state]).presentation_state.position
  end
end
