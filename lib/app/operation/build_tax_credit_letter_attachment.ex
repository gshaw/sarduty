defmodule App.Operation.BuildTaxCreditLetterAttachment do
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Operation.LoadImage
  alias Service.PDFLetter

  def call(tax_credit_letter) do
    team = tax_credit_letter.member.team
    title = "#{tax_credit_letter.year} SRVTC #{team.name}"

    content =
      %{
        title: title,
        author: team.name,
        creator: "SARDuty.com",
        logo: logo(team),
        content: tax_credit_letter.letter_content,
        qr_url: qr_url(tax_credit_letter)
      }
      |> Map.merge(signature_parts(tax_credit_letter))
      |> PDFLetter.build()

    %{
      content: content,
      title: title,
      filename: Service.StringHelpers.to_filename("#{title}.pdf"),
      content_type: "application/pdf"
    }
  end

  # The letter's own copy of the signature, never the team's current one. A letter
  # whose text has no gap to sign in is drawn as one block, unsigned.
  defp signature_parts(%TaxCreditLetter{signature: signature} = letter)
       when is_binary(signature) do
    case TaxCreditLetter.split_at_signature(letter.letter_content) do
      {body, signer} -> %{signature: signature, body: body, signer: signer}
      :error -> %{}
    end
  end

  defp signature_parts(_letter), do: %{}

  @doc """
  What the letter's QR code opens: its page on the verify site. Nil for a letter from
  before #207, which has no verify line and a reference number that can't verify alone.
  """
  def qr_url(letter) do
    if TaxCreditLetter.current_ref_id?(letter),
      do: TaxCreditLetter.verify_url(letter, Web.VerifyHost.url())
  end

  # A team without a logo gets none on its letters, not SAR Duty's.
  defp logo(team) do
    if Team.logo_file(team.subdomain), do: LoadImage.logo(team, :square)
  end
end
