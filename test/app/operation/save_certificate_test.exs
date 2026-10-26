defmodule App.Operation.SaveCertificateTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Operation.SaveCertificate

  setup do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    qualification = qualification_fixture(team, %{title: "Standard First Aid"})
    %{team: team, member: member, user: user, qualification: qualification}
  end

  defp params(ctx), do: %{"qualification_id" => ctx.qualification.id, "starts_on" => "2026-10-18"}

  test "a member sends a certificate with a photo, kept as a JPEG", ctx do
    file = %{bytes: png_fixture(40, 30), file_name: "scan.png"}

    assert {:ok, certificate} = SaveCertificate.send(ctx.member, params(ctx), file)
    assert %{status: :waiting, file_name: "scan.jpg", content_type: "image/jpeg"} = certificate
    assert <<0xFF, 0xD8, _rest::binary>> = CertificateFile.bytes(certificate)
  end

  test "a certificate needs a photo or a PDF", ctx do
    assert {:error, changeset} = SaveCertificate.send(ctx.member, params(ctx), nil)
    assert {"Select a photo or a PDF of the certificate.", _opts} = changeset.errors[:file_name]

    assert {:error, changeset} =
             SaveCertificate.send(ctx.member, params(ctx), %{bytes: "<html>", file_name: "a.pdf"})

    assert {"Select a photo or a PDF.", _opts} = changeset.errors[:file_name]
    assert Repo.aggregate(Certificate, :count) == 0
  end

  test "a member changes a waiting certificate, keeping its file", ctx do
    certificate = certificate_fixture(ctx.member, ctx.qualification)

    assert {:ok, saved} =
             SaveCertificate.change_own(ctx.member, certificate, %{"ends_on" => ""}, nil)

    assert saved.ends_on == nil
    assert CertificateFile.bytes(saved) == "%PDF-1.7\n"
  end

  test "once its award is in D4H, the member cannot change or delete it", ctx do
    certificate = certificate_fixture(ctx.member, ctx.qualification, %{d4h_award_id: 300})

    assert SaveCertificate.change_own(ctx.member, certificate, %{}, nil) == {:error, :decided}
    assert SaveCertificate.delete_own(ctx.member, certificate) == {:error, :decided}
  end

  test "declining needs a reason, and deletes the file", ctx do
    certificate = certificate_fixture(ctx.member, ctx.qualification)
    now = DateTime.utc_now()

    assert {:error, %Ecto.Changeset{}} =
             SaveCertificate.decline(ctx.team, certificate, " ", ctx.user, now)

    assert {:ok, %{status: :declined, decline_reason: "This is for AST 2."}} =
             SaveCertificate.decline(ctx.team, certificate, "This is for AST 2.", ctx.user, now)

    assert CertificateFile.bytes(certificate) == nil

    assert SaveCertificate.decline(ctx.team, certificate, "Again", ctx.user, now) ==
             {:error, :decided}

    assert SaveCertificate.delete_own(ctx.member, certificate) == :ok
    assert Repo.aggregate(Certificate, :count) == 0
  end

  test "a team admin turns a waiting photo, never a PDF or a decided one", ctx do
    photo =
      certificate_fixture(ctx.member, ctx.qualification, %{
        file_name: "scan.jpg",
        content_type: "image/jpeg"
      })

    CertificateFile.put!(photo, 40 |> Image.new!(30) |> Image.write!(:memory, suffix: ".jpg"))

    assert {:ok, turned} = SaveCertificate.rotate(ctx.team, photo, :right)
    assert turned.file_size == byte_size(CertificateFile.bytes(photo))
    image = photo |> CertificateFile.bytes() |> Image.from_binary!()
    assert {Image.width(image), Image.height(image)} == {30, 40}

    pdf = certificate_fixture(ctx.member, ctx.qualification)
    assert SaveCertificate.rotate(ctx.team, pdf, :left) == {:error, :not_a_photo}

    {:ok, _declined} =
      SaveCertificate.decline(ctx.team, photo, "Wrong one", ctx.user, DateTime.utc_now())

    assert SaveCertificate.rotate(ctx.team, photo, :left) == {:error, :decided}
  end
end
