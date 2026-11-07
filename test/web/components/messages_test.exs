defmodule Web.Components.MessagesTest do
  use ExUnit.Case, async: true

  alias Web.Components.Messages

  describe "send_confirm/3" do
    test "under 10 members asks a simple question" do
      attrs = Messages.send_confirm(9, "Email 9 members about MIT?", ["Each gets a reminder."])

      assert attrs == %{"data-confirm" => "Email 9 members about MIT? Each gets a reminder."}
    end

    test "from 10 members the send waits on a check box naming the count" do
      attrs = Messages.send_confirm(73, "Email 73 members about MIT?", ["Each gets a reminder."])

      assert attrs["data-confirm"] == "Email 73 members about MIT?"
      assert attrs["data-confirm-list"] == ~s(["Each gets a reminder."])
      assert attrs["data-confirm-warning"] == "Emails cannot be taken back."
      assert attrs["data-confirm-check"] == "I understand 73 members get this email."
    end
  end

  describe "many at once (/styles/confirm-dialog#many)" do
    test "the check box waits from 10" do
      assert Messages.confirm_check(9, "I understand 9 members leave Trainees.") == %{}

      assert Messages.confirm_check(10, "I understand 10 members leave Trainees.") == %{
               "data-confirm-check" => "I understand 10 members leave Trainees."
             }
    end

    test "names up to 3, then the count" do
      names = ["Avery Chen", "Jordan Lee", "Robin Tse", "Quinn Laval"]
      two = Enum.take(names, 2)
      three = Enum.take(names, 3)

      assert Messages.names_or_count(two, "2 members") == "Avery Chen and Jordan Lee"

      assert Messages.names_or_count(three, "3 members") ==
               "Avery Chen, Jordan Lee, and Robin Tse"

      assert Messages.names_or_count(names, "4 members") == "4 members"
    end
  end
end
