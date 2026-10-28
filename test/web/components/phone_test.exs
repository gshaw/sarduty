defmodule Web.Components.PhoneTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.Phone

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

  test "phone/1 shows the number formatted, with a copy button, and Call and Text when asked" do
    assigns = %{}

    document =
      ~H"""
      <.phone id="kim" phone="6045551234" call_and_text />
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query(~s(#kim-copy[value="604-555-1234"])) |> Enum.count() == 1
    assert document |> LazyHTML.text() =~ "604-555-1234"
    assert document |> LazyHTML.query("#kim-call") |> Enum.count() == 1

    plain =
      ~H"""
      <.phone id="kim" phone="6045551234" />
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()

    assert plain |> LazyHTML.query("#kim-call") |> Enum.count() == 0
  end

  test "phone/1 shows the missing hint, or nothing, without a number" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.phone id="kim" phone={nil} missing="No mobile number" />
      """)

    assert html =~ "No mobile number"
    refute html =~ "copy"

    blank = rendered_to_string(~H|<.phone id="kim" phone=" " />|)
    assert String.trim(blank) == ""
  end
end
