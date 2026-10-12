defmodule App.Mailer.TaxCreditLetterMailerTest do
  use ExUnit.Case, async: true

  alias App.Mailer.TaxCreditLetterMailer
  alias App.Model.Member
  alias App.Model.TaxCreditLetter
  alias App.Model.Team

  @team %Team{name: "South Fraser Search and Rescue", authorized_by_name: "Andrew Smith"}

  defp letter(team), do: %TaxCreditLetter{year: 2025, member: %Member{team: team}}

  test "says what the letter is for and who answers questions" do
    team = %{@team | authorized_by_email: "andrew@example.com", authorized_by_phone: "604"}

    assert team |> letter() |> TaxCreditLetterMailer.body() == """
           Attached is your 2025 tax credit letter from South Fraser Search and Rescue.

           Claim the Search and Rescue Volunteers Tax Credit (SRVTC) on line 31240 of your tax return. Keep this letter in case the CRA asks for it.

           Questions about your hours? Contact Andrew Smith at andrew@example.com.
           """
  end

  test "gives the signer's phone when they have no email" do
    team = %{@team | authorized_by_email: "", authorized_by_phone: "604-555-0123"}

    assert team |> letter() |> TaxCreditLetterMailer.body() =~
             "Contact Andrew Smith at 604-555-0123.\n"
  end

  test "leaves out the questions line when the signer has neither" do
    body = @team |> letter() |> TaxCreditLetterMailer.body()
    refute body =~ "Questions"
    assert body =~ ~r/Keep this letter in case the CRA asks for it\.\n$/
  end
end
