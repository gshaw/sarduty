defmodule App.Operation.BuildTaxCreditLetterAttachment do
  alias Service.PDFLetter

  def call(tax_credit_letter) do
    team = tax_credit_letter.member.team
    title = "#{tax_credit_letter.year} SRVTC #{team.name}"

    content =
      PDFLetter.build(%{
        title: title,
        author: team.name,
        creator: "SARDuty.com",
        logo_path: Application.app_dir(:sarduty, "/priv/static/images/logo-sfsar.png"),
        content: tax_credit_letter.letter_content
      })

    %{
      content: content,
      title: title,
      filename: "#{title}.pdf",
      content_type: "application/pdf"
    }
  end
end
