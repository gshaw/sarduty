defmodule App.Operation.LoadCertificateTest do
  use ExUnit.Case, async: true

  alias App.Operation.LoadCertificate

  test "names the file after the qualification, with the type's extension" do
    assert LoadCertificate.filename("Standard First Aid", "application/pdf") ==
             "Standard First Aid.pdf"

    assert LoadCertificate.filename("ICS-100 / 200", "image/png") == "ICS-100 200.png"
    assert LoadCertificate.filename("/?!", "application/x-unknown") == "Certificate"
  end
end
