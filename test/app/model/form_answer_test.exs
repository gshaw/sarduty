defmodule App.Model.FormAnswerTest do
  use ExUnit.Case, async: true

  alias App.Model.FormAnswer

  @asks [
    %{name: "leader", remember: true},
    %{name: "injured", remember: false},
    %{name: "notes", remember: false}
  ]

  test "an ask starts from the activity's answer" do
    saved = %{"leader" => "Alex Chen", "injured" => "2"}
    last = %{"leader" => "Harper Nguyen", "notes" => "Walked out at dusk."}

    assert FormAnswer.start(saved, last, @asks) == %{"leader" => "Alex Chen", "injured" => "2"}
  end

  test "then, when it says remember, from the team's last answer" do
    last = %{"leader" => "Harper Nguyen", "injured" => "1"}
    assert FormAnswer.start(%{}, last, @asks) == %{"leader" => "Harper Nguyen"}
  end

  test "an answer on each row starts from the activity's, by row" do
    asks = [%{name: "on_task", remember: false, each: "people"} | @asks]
    saved = %{"on_task" => %{"member:7" => "No"}, "leader" => "Alex Chen"}

    assert FormAnswer.start(saved, %{}, asks) == %{
             "on_task" => %{"member:7" => "No"},
             "leader" => "Alex Chen"
           }

    # One answer kept under the name before the form asked it for each row.
    assert FormAnswer.start(%{"on_task" => "No"}, %{}, asks) == %{}
  end
end
