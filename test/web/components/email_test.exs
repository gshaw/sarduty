defmodule Web.Components.EmailTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.Email

  test "shows the address as a mailto: link with a copy button" do
    assigns = %{}

    document =
      ~H"""
      <.email id="sam-email" email="sam@example.com" />
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query(~s(a[href="mailto:sam@example.com"])) |> Enum.count() == 1

    assert document |> LazyHTML.query(~s(#sam-email[value="sam@example.com"])) |> Enum.count() ==
             1
  end

  test "shows the missing hint, or nothing, without an address" do
    assigns = %{}

    assert rendered_to_string(~H|<.email id="e" email={nil} missing="No email" />|) =~ "No email"
    none = rendered_to_string(~H|<.email id="e" email={nil} />|)
    assert String.trim(none) == ""
  end
end
