defmodule App.Operation.BuildPDF do
  def call do
    call(%{
      team_logo: "assets/img/logo-sfsar.png",
      team_name: "South Fraser SAR",
      team_address: """
      South Fraser Search and Rescue Society
      c/o Surrey Fire Service Hall #1
      8767 132 Street
      Surrey, BC V3W 4P1

      info@sfsar.ca
      """,
      member_name: "John Smith",
      member_address: "10058 128  St, Surrey, BC V2V 7X3",
      tax_year: 2023,
      primary_hours: 237,
      secondary_hours: 42,
      certified_by: "Andrew Wallwork, President",
      ref_id: "SRVTC-000001"
    })
  end

  def call(letter_info) do
    file_path = "letter.pdf"

    {:ok, pdf} = Pdf.new(size: :letter)

    pdf
    |> write_page_content(letter_info)
    |> Pdf.write_to(file_path)
    |> Pdf.cleanup()

    # credo:disable-for-next-line Credo.Check.Warning.LeakyEnvironment
    System.cmd("open", ["-g", file_path])
  end

  defp write_page_content(pdf, info) do
    sarvac_logo = "assets/img/logo-sarvac.png"

    margin = 72
    image_width = 72
    image_height = 72
    %{width: width, height: height} = Pdf.size(pdf)

    pdf
    |> Pdf.set_info(
      title: "SAR Volunteer Tax Credit #{info.tax_year}",
      creator: "SARDuty.com",
      created: Date.utc_today(),
      modified: Date.utc_today(),
      author: info.team_name,
      subject: "SAR Volunteer Tax Credit"
    )
    |> Pdf.set_font("Helvetica", 12)
    |> Pdf.set_text_leading(14.4)
    |> Pdf.add_image(
      {width - margin - image_width, height - margin - image_height},
      sarvac_logo,
      width: image_width,
      height: image_height
    )
    |> Pdf.add_image(
      {width - margin - image_width - image_width, height - margin - image_height},
      info.team_logo,
      width: image_width,
      height: image_height
    )
    |> Pdf.move_down(margin)
    |> Pdf.text_wrap!({margin, :cursor}, {width - margin - margin, height}, [
      info.team_address,
      "\n\n\nTo whom it may concern:",
      {"\n\nName: ", bold: false},
      {info.member_name, bold: true},
      {"\nAddress: ", bold: false},
      {info.member_address, bold: true},
      "\n\nThis letter serves to confirm that the above noted individual has ",
      "completed eligible volunteer search and rescue hours for ",
      {info.team_name, bold: true},
      ", an ‘Eligible Search and Rescue Organization recognized by the RCMP’ in the ",
      {"#{info.tax_year}", bold: true},
      " calendar year.",
      "\n",
      {"\nPrimary Hours: ", bold: false},
      {"#{info.primary_hours}", bold: true},
      {"\nSecondary Hours: ", bold: false},
      {"#{info.secondary_hours}", bold: true},
      {"\nTotal Hours: ", bold: true},
      {"#{info.primary_hours + info.secondary_hours}", bold: true},
      "\n\nPlease contact the writer if you have any questions.",
      "\n\nCertified on #{Calendar.strftime(Date.utc_today(), "%B %d, %Y")}.",
      "\n\n\n\n#{info.certified_by}\n",
      info.team_name,
      "\n\nReference: #{info.ref_id}"
    ])
  end
end
