defmodule Web.Components.PhoneTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.Phone

  alias Web.Components.Phone

  test "format/1 reads a North American number with dashes, and keeps anything else" do
    assert Phone.format("(604) 555 1234") == "604-555-1234"
    assert Phone.format("+44 20 7946 0958") == "+442079460958"
    assert Phone.format(" ask the office ") == "ask the office"
    assert Phone.format("  ") == nil
    assert Phone.format(nil) == nil
  end

  test "call_and_text/1 dials E.164 and shows only on touch screens" do
    assigns = %{}

    document =
      ~H"""
      <.call_and_text id="kim" phone="604 555 1234" />
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query(~s(#kim-call[href="tel:+16045551234"])) |> Enum.count() == 1
    assert document |> LazyHTML.query(~s(#kim-text[href="sms:+16045551234"])) |> Enum.count() == 1
    assert document |> LazyHTML.query("span.hidden.pointer-coarse\\:flex") |> Enum.count() == 1
  end

  test "call_and_text/1 shows nothing without a number" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.call_and_text id="kim" phone={nil} />
      """)

    assert String.trim(html) == ""
  end
end
