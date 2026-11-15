defmodule ClaperWeb.CourseController do
  use ClaperWeb, :controller

  alias Claper.Events

  def presenter(conn, %{"course" => course}), do: resolve(conn, course, :presenter)
  def manage(conn, %{"course" => course}), do: resolve(conn, course, :manage)

  defp resolve(conn, course, destination) do
    case Events.find_course_event(conn.assigns.current_user, course) do
      nil ->
        conn
        |> put_layout(false)
        |> put_status(:not_found)
        |> render("not_found.html", course: course)

      event ->
        path =
          case destination do
            :presenter -> ~p"/e/#{event.code}/presenter"
            :manage -> ~p"/e/#{event.code}/manage"
          end

        query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
        redirect(conn, to: path <> query)
    end
  end
end
