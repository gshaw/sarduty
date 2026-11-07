defmodule Web.ActivityOrgFormLiveTest do
  # An organization's form on Coast Range SAR's activities (#950). Not async: the cast is
  # about 1,100 rows, and their insert holds SQLite's write lock (Web.MockupSeedTest).
  use Web.ConnCase, async: false

  import App.DataFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias App.Model.FormAnswer
  alias App.Model.SavedPDF
  alias App.Repo
  alias Web.MockupSeed

  # The test form, reading BCSARA's Agency File # too, which Missing hiker leaves empty.
  @text "test/support/fixtures/forms/task_report.txt"
        |> File.read!()
        |> String.replace(
          "`People helped`\n  from activities",
          "`People helped`, `Agency File #`\n  from activities"
        )
  @page_source File.read!("test/support/fixtures/forms/task_report_page.typ")

  setup_all do
    {:ok, page} = Service.Typst.compile(@page_source)
    %{page: page}
  end

  setup %{page: page} do
    cast = MockupSeed.team()

    organization =
      organization_fixture([cast.team], %{
        name: "Pacific Ranges SAR Association",
        short_name: "PRSARA"
      })

    form = form_fixture(organization, %{text: @text, page: page, enabled: true})

    %{
      cast: cast,
      form: form,
      hiker: MockupSeed.activity(cast, "Missing hiker"),
      training: MockupSeed.activity(cast, "Rope rescue training")
    }
  end

  defp form_path(activity, form),
    do: ~p"/teams/coastrange/activities/#{activity.id}/forms/#{form.id}"

  describe "Forms above Actions" do
    test "lists each form that's on and shows on the activity, for team admins", ctx do
      %{cast: cast, form: form, hiker: hiker, training: training} = ctx
      conn = log_in_user(build_conn(), cast.alex)

      {:ok, lv, _html} = live(conn, ~p"/teams/coastrange/activities/#{hiker.id}")
      assert has_element?(lv, "#activity-form-#{form.id}", "Task report")

      # An exercise isn't an incident, so the form's where leaves it out.
      {:ok, lv, _html} = live(conn, ~p"/teams/coastrange/activities/#{training.id}")
      refute has_element?(lv, "#activity-forms")
    end

    test "members never see them", %{cast: cast, hiker: hiker, form: form} do
      conn = log_in_user(build_conn(), cast.cameron)

      {:ok, lv, _html} = live(conn, ~p"/teams/coastrange/activities/#{hiker.id}")
      refute has_element?(lv, "#activity-forms")

      assert_raise Web.Status.NotFound, fn -> live(conn, form_path(hiker, form)) end
    end

    test "a form turned off shows nowhere", %{cast: cast, hiker: hiker, form: form} do
      Repo.update_all(App.Model.Form, set: [enabled: false])
      conn = log_in_user(build_conn(), cast.alex)

      {:ok, lv, _html} = live(conn, ~p"/teams/coastrange/activities/#{hiker.id}")
      refute has_element?(lv, "#activity-forms")

      assert_raise Web.Status.NotFound, fn -> live(conn, form_path(hiker, form)) end
    end
  end

  describe "the form's page" do
    test "shows what SAR Duty filled in, and links each empty field to Change fields", ctx do
      %{cast: cast, hiker: hiker, form: form} = ctx
      {:ok, lv, _html} = live(log_in_user(build_conn(), cast.alex), form_path(hiker, form))

      assert has_element?(lv, "h1", "Task report for Missing hiker")
      assert has_element?(lv, "#org-form-filled-table-task-title", "Missing hiker")
      assert has_element?(lv, "#org-form-filled-table-task-ref-id", hiker.ref_id)

      assert has_element?(lv, "#org-form-missing", "1 value this form reads is empty.")

      assert has_element?(
               lv,
               ~s(#org-form-missing-table-task-Agency-File a[href="/teams/coastrange/activities/#{hiker.id}/fields/edit"]),
               "Change fields"
             )
    end

    test "keeps each answer that reads as it changes, and shows what's wrong", ctx do
      %{cast: cast, hiker: hiker, form: form} = ctx
      {:ok, lv, _html} = live(log_in_user(build_conn(), cast.alex), form_path(hiker, form))

      # Injured starts at its default, and ERR attached at its choice.
      assert has_element?(lv, ~s(#org-form-answer-injured[value="0"]))

      lv
      |> form("#org-form-answers",
        answers: %{"leader" => "Alex Chen", "injured" => "a few", "err" => "Yes"}
      )
      |> render_change()

      assert has_element?(lv, "#org-form-questions", "Enter a number, such as 3.")
      assert FormAnswer.for_activity(hiker) == %{"leader" => "Alex Chen", "err" => "Yes"}

      lv |> form("#org-form-answers", answers: %{"injured" => "2"}) |> render_change()
      refute has_element?(lv, "#org-form-questions", "Enter a number")
      assert FormAnswer.for_activity(hiker)["injured"] == "2"
    end

    test "the task leader starts from the team's last answer", ctx do
      %{cast: cast, hiker: hiker, form: form} = ctx
      kayakers = MockupSeed.activity(cast, "Overdue kayakers")

      Repo.insert!(%FormAnswer{
        team_id: cast.team.id,
        activity_id: kayakers.id,
        name: "leader",
        value: "Harper Nguyen"
      })

      {:ok, lv, _html} = live(log_in_user(build_conn(), cast.alex), form_path(hiker, form))
      assert has_element?(lv, ~s(#org-form-answer-leader[value="Harper Nguyen"]))
    end
  end

  describe "Download PDF and Open PDF" do
    test "keep the answers and save the PDF as it was made", ctx do
      %{cast: cast, hiker: hiker, form: form} = ctx
      conn = log_in_user(build_conn(), cast.alex)
      path = form_path(hiker, form) <> "/pdf"
      answers = %{"leader" => "Alex Chen", "injured" => "1", "err" => "No"}

      conn = post(conn, path, %{"answers" => answers})
      assert ["attachment" <> _] = get_resp_header(conn, "content-disposition")
      assert "%PDF" <> _ = conn.resp_body

      pdf = SavedPDF |> where(activity_id: ^hiker.id) |> Repo.one!()
      assert pdf.form_id == form.id and pdf.form_version == form.version
      assert pdf.user_id == cast.alex.id
      assert pdf.title == "Task report #{hiker.ref_id}"
      assert pdf.keep == %{":leader" => "Alex Chen", ":injured" => 1, ":err" => "No"}
      assert FormAnswer.for_activity(hiker)["leader"] == "Alex Chen"

      conn = post(log_in_user(build_conn(), cast.alex), path, %{"open" => "true"})
      assert ["inline" <> _] = get_resp_header(conn, "content-disposition")
      assert SavedPDF |> where(activity_id: ^hiker.id) |> Repo.aggregate(:count) == 2
    end

    test "make nothing when an answer doesn't read", %{cast: cast, hiker: hiker, form: form} do
      conn = log_in_user(build_conn(), cast.alex)
      path = form_path(hiker, form)

      conn = post(conn, path <> "/pdf", %{"answers" => %{"injured" => "a few"}})
      assert redirected_to(conn) == path

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Injured: Enter a number, such as 3."

      refute SavedPDF |> where(activity_id: ^hiker.id) |> Repo.exists?()
    end

    test "only for team admins", %{cast: cast, hiker: hiker, form: form} do
      conn = log_in_user(build_conn(), cast.cameron)

      assert_raise Web.Status.NotFound, fn ->
        post(conn, form_path(hiker, form) <> "/pdf", %{})
      end
    end
  end
end
