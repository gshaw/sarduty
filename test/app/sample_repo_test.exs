defmodule App.SampleRepoTest do
  # Coast Range SAR's own database (#816), seeded at boot. No sandbox: these tests only
  # read it, so they share it with every other test that runs a sample.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias App.Model.Member
  alias App.Report
  alias App.Report.Catalog
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Plan
  alias App.Report.Runner

  defp run!(text) do
    case Report.run_sample(text) do
      {:ok, result} -> result
      {:error, error} -> flunk("#{text}\n#{Error.text(error)}")
    end
  end

  test "a sample run reads Coast Range SAR" do
    # A member cell is the member's id.
    assert [[id]] = run!("select name from members where ref_id = '132'").rows
    assert App.SampleRepo.get!(Member, id).name == "Cameron Ruiz"
  end

  # The agent catches a wrong answer before a team admin sees it, so every field it can
  # write has rows to catch it with: a value somewhere, each choice, and each of true and
  # false.
  test "every field a report reads has values on Coast Range SAR" do
    context = Context.new(App.SampleRepo.team(), DateTime.utc_now(), repo: App.SampleRepo)

    fields =
      for subject <- Catalog.subjects(),
          field <- Catalog.shown_fields(subject, context),
          do: {subject, field}

    missing =
      for {subject, field} <- fields,
          problem <- problems(subject, field, context),
          do: "#{subject.name}.#{field.name}: #{problem}"

    assert length(fields) > 60
    assert missing == []
  end

  defp problems(subject, field, context) do
    expr = call(field)

    case field.type do
      :bool ->
        for value <- [true, false],
            count(subject, "#{expr} = #{value}") == 0,
            do: "never #{value}"

      :choice ->
        for {_label, value} <- field.choices.(context),
            count(subject, "#{expr} = '#{String.replace(value, "'", "''")}'") == 0,
            do: "never #{value}"

      _other ->
        if count(subject, "#{expr} is not null") == 0, do: ["always null"], else: []
    end
  end

  defp count(subject, where),
    do: run!("select count(id) from #{subject.name} where #{where}").rows |> hd() |> hd()

  defp call(%{args: []} = field), do: field.name
  defp call(field), do: "#{field.name}(#{Enum.map_join(field.args, ", ", &arg/1)})"

  defp arg(:days), do: "30"
  defp arg(:period), do: "'30d'"
  defp arg(:tag), do: "'all'"
  defp arg(:group), do: "'Callout'"

  test "last 30 days has activities, and the coming week has sign-ups" do
    assert count(Catalog.subject("activities"), "recent = true") > 3
    assert count(Catalog.subject("attendance"), "status = 'signed_up'") > 3
  end

  # Each repo's queries come with its own telemetry event, in the process that ran them.
  test "a sample run never reads the main database" do
    attach([[:app, :repo, :query], [:app, :sample_repo, :query]])

    assert {:ok, _result} = Report.run_sample("select title, attended_count from activities")

    assert_received {:query, [:app, :sample_repo, :query]}
    refute_received {:query, [:app, :repo, :query]}
  end

  # A run past 2 seconds disconnects its connection. An in-memory database would close
  # with it; the file keeps every row.
  test "a run past the time limit leaves Coast Range SAR as it was" do
    before = run!("select count(id) from attendance").rows

    slow =
      "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 1000000000) SELECT count(*) FROM c"

    capture_log(fn ->
      assert {:error, %Error{message: "Narrow the report with where" <> _}} =
               Runner.run(%Plan{sql: slow, params: []}, "Etc/UTC", App.SampleRepo)
    end)

    assert run!("select count(id) from attendance").rows == before
  end

  defp attach(events) do
    id = "sample-repo-test-#{inspect(self())}"
    :telemetry.attach_many(id, events, &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
  end

  @doc false
  def forward(event, _measurements, _metadata, test),
    do: if(self() == test, do: send(test, {:query, event}))
end
