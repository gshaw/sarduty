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
end
