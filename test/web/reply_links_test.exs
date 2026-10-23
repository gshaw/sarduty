defmodule Web.ReplyLinksTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.Member
  alias Web.ReplyLinks

  defp token("/" <> path), do: path |> String.split("/") |> List.last()

  test "a reply link names one member and one activity" do
    path = ReplyLinks.reply_path(%Member{id: 3}, %Activity{id: 7})

    assert "/replies/" <> _ = path
    assert path |> token() |> ReplyLinks.verify_reply() == {:ok, {3, 7}}
  end

  test "a reminders link names one member" do
    path = ReplyLinks.reminders_path(%Member{id: 3})

    assert "/reminders/" <> _ = path
    assert path |> token() |> ReplyLinks.verify_reminders() == {:ok, 3}
  end

  # Each link does one thing: a reply link can't turn reminders off, and the reverse.
  test "a token is good only for its own link, and not once changed" do
    reply = token(ReplyLinks.reply_path(%Member{id: 3}, %Activity{id: 7}))
    reminders = token(ReplyLinks.reminders_path(%Member{id: 3}))

    assert ReplyLinks.verify_reminders(reply) == :error
    assert ReplyLinks.verify_reply(reminders) == :error
    assert ReplyLinks.verify_reply(reply <> "x") == :error
    assert ReplyLinks.verify_reply("made-up") == :error
  end
end
