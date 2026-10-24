defmodule App.Operation.AcceptCertificateTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Model.ChangeSetRow
  alias App.Model.MemberQualificationAward
  alias App.Operation.AcceptCertificate
  alias App.Operation.SaveCertificate

  @now ~U[2026-10-24 17:00:00.000000Z]

  setup do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})

    team =
      team
      |> Ecto.Changeset.change(member_logins: true, certificates_enabled: true)
      |> Repo.update!()

    member = member_fixture(team, %{name: "Sam Rivera"})
    qualification = qualification_fixture(team, %{title: "Standard First Aid"})
    certificate = certificate_fixture(member, qualification)

    %{
      user: user,
      team: team,
      member: member,
      qualification: qualification,
      certificate: certificate
    }
  end

  # D4H with no awards for the member yet: a new award is 300, and an upload answers
  # `upload_status`.
  defp stub_d4h(upload_status) do
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")
      if conn.method == "POST", do: send(test_pid, {:post, path})

      case {conn.method, path} do
        {"GET", "/member-qualification-awards"} ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        {"POST", "/member-qualification-awards"} ->
          Req.Test.json(conn, %{
            "id" => 300,
            "member" => %{"resourceType" => "Member", "id" => 1},
            "qualification" => %{"id" => 1}
          })

        {"POST", "/documents"} ->
          conn
          |> Plug.Conn.put_status(upload_status)
          |> Req.Test.json(%{"id" => 900, "title" => "Unsupported file"})
      end
    end)
  end

  defp accept(ctx, params \\ %{}),
    do: AcceptCertificate.call(ctx.team, ctx.certificate, params, ctx.user, @now)

  defp posts do
    receive do
      {:post, path} -> [path | posts()]
    after
      0 -> []
    end
  end

  test "accepting adds the award to D4H with the file, then to the copy", ctx do
    stub_d4h(200)

    assert {:ok, %Certificate{status: :accepted, d4h_award_id: 300, d4h_document_id: 900}} =
             accept(ctx, %{"starts_on" => "2026-10-17"})

    assert posts() == ["/member-qualification-awards", "/documents"]
    assert CertificateFile.bytes(ctx.certificate) == nil

    award = MemberQualificationAward.get_by(member_id: ctx.member.id, d4h_award_id: 300)
    assert award.d4h_document_id == 900
    assert award.starts_at == ~U[2026-10-17 07:00:00Z]
    assert award.ends_at == ~U[2029-10-18 07:00:00Z]
  end

  # A D4H award id is unique only for one member.
  test "the award goes in for the certificate's member, never another's with its id", ctx do
    other = member_fixture(ctx.team)
    theirs = qualification_award_fixture(ctx.qualification, other, %{d4h_award_id: 300})
    stub_d4h(200)

    assert {:ok, _accepted} = accept(ctx)
    assert Repo.reload!(theirs).d4h_document_id == nil

    assert %{d4h_document_id: 900} =
             MemberQualificationAward.get_by(member_id: ctx.member.id, d4h_award_id: 300)
  end

  test "a failed upload keeps the file, and Send again uploads it alone", ctx do
    stub_d4h(422)

    assert {:error, "The award is in D4H, but the certificate did not upload. Unsupported file"} =
             accept(ctx)

    waiting = Repo.reload!(ctx.certificate)
    assert %{status: :waiting, d4h_award_id: 300} = waiting
    assert CertificateFile.bytes(waiting)
    assert posts() == ["/member-qualification-awards", "/documents"]

    # The dates are D4H's now, so the form's are not read.
    stub_d4h(200)
    assert {:ok, %{status: :accepted}} = accept(ctx, %{"starts_on" => "2020-01-01"})
    assert posts() == ["/documents"]

    assert MemberQualificationAward.get_by(d4h_award_id: 300).starts_at ==
             ~U[2026-10-18 07:00:00Z]
  end

  test "a decline while the accept waits on D4H goes after it, and finds it decided", ctx do
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      case {conn.method, String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")} do
        {"GET", _path} ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        {"POST", "/member-qualification-awards"} ->
          decline = fn ->
            SaveCertificate.decline(ctx.team, ctx.certificate, "No", ctx.user, @now)
          end

          send(test_pid, {:decline, Task.async(decline)})
          # Time for a decline that did not wait to go through.
          Process.sleep(50)
          Req.Test.json(conn, %{"id" => 300, "member" => %{"id" => 1}, "qualification" => %{}})

        {"POST", "/documents"} ->
          Req.Test.json(conn, %{"id" => 900})
      end
    end)

    assert {:ok, %{status: :accepted}} = accept(ctx)
    assert_received {:decline, task}
    assert Task.await(task) == {:error, :decided}
    assert %{status: :accepted} = Repo.reload!(ctx.certificate)
  end

  test "the team admin's dates are checked before anything is sent", ctx do
    assert {:error, %Ecto.Changeset{}} = accept(ctx, %{"ends_on" => "2026-01-01"})
    assert posts() == []
  end

  test "a declined certificate cannot be accepted", ctx do
    ctx.certificate |> Ecto.Changeset.change(status: :declined) |> Repo.update!()
    assert accept(ctx) == {:error, :decided}
  end

  test "the outcome reads the award and the upload" do
    award = %ChangeSetRow{action: :award_qualification, status: :applied, d4h_record_id: 3}
    file = %ChangeSetRow{action: :attach_award_document, status: :applied, d4h_record_id: 9}

    assert AcceptCertificate.outcome([award, file]) == {:accepted, 3, 9}

    assert AcceptCertificate.outcome([award, %{file | status: :failed, error: "No"}]) ==
             {:award_only, 3, "No"}

    assert AcceptCertificate.outcome([
             %{award | status: :skipped, error: "D4H has this award already."},
             %{file | status: :failed}
           ]) == {:not_sent, "D4H has this award already."}
  end
end
