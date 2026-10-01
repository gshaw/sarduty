defmodule App.Operation.BuildTaxCreditLetterAttachment do
  alias App.Model.Team
  alias App.Operation.LoadImage
  alias Service.PDFLetter

  def call(tax_credit_letter) do
    team = tax_credit_letter.member.team
    title = "#{tax_credit_letter.year} SRVTC #{team.name}"

    content =
      PDFLetter.build(%{
        title: title,
        author: team.name,
        creator: "SARDuty.com",
        logo: logo(team),
        content: tax_credit_letter.letter_content
      })

    %{
      content: content,
      title: title,
      filename: Service.StringHelpers.to_filename("#{title}.pdf"),
      content_type: "application/pdf"
    }
  end

  # A team without a logo gets none on its letters, not SAR Duty's.
  defp logo(team) do
    if Team.logo_file(team.subdomain), do: LoadImage.logo(team.subdomain, :square)
  end
end
