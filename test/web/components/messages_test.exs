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
end
