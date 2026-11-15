defmodule Claper.CourseSlugTest do
  use ExUnit.Case, async: true

  alias Claper.Events

  test "normalizes accents, case, punctuation and whitespace" do
    assert Events.course_slug(" -- ISTQB CTAL Testeur Ágile v2.0 !! ") ==
             "istqb-ctal-testeur-agile-v2-0"

    assert Events.course_slug("École d’été (Copy)") == "ecole-d-ete-copy"
    assert Events.course_slug(" !! ") == ""
  end
end
