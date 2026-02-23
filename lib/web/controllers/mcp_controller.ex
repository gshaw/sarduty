defmodule Web.MCPController do
  use Web, :controller

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Repo

  def handle(conn, %{"subdomain" => subdomain}) do
    with :ok <- authenticate(conn),
         team when not is_nil(team) <- Team.get_by(subdomain: subdomain) do
      dispatch_request(conn, team)
    else
      :error ->
        conn
        |> put_status(401)
        |> json(%{"error" => "Unauthorized: missing or invalid access key"})

      nil ->
        conn
        |> put_status(404)
        |> json(%{"error" => "Team not found"})
    end
  end

  defp authenticate(conn) do
    access_key = System.get_env("MCP_ACCESS_KEY")
    if access_key && conn.query_params["access"] == access_key, do: :ok, else: :error
  end

  defp dispatch_request(%{method: "GET"} = conn, team) do
    json(conn, %{
      "name" => "SAR Duty MCP Server",
      "version" => "1.0.0",
      "team" => team.name,
      "subdomain" => team.subdomain,
      "description" => "Model Context Protocol endpoint for #{team.name}",
      "protocol" => "MCP 2024-11-05",
      "usage" => "POST to this URL with a JSON-RPC 2.0 body"
    })
  end

  defp dispatch_request(%{method: "POST"} = conn, team) do
    handle_jsonrpc(conn, team, conn.body_params)
  end

  defp handle_jsonrpc(conn, team, %{"jsonrpc" => "2.0", "method" => method} = request) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", %{})

    case dispatch_method(team, method, params) do
      {:ok, result} ->
        json(conn, %{"jsonrpc" => "2.0", "id" => id, "result" => result})

      {:error, code, message} ->
        json(conn, %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{"code" => code, "message" => message}
        })

      :notification ->
        send_resp(conn, 204, "")
    end
  end

  defp handle_jsonrpc(conn, _team, _body) do
    conn
    |> put_status(400)
    |> json(%{"error" => "Invalid JSON-RPC 2.0 request"})
  end

  # MCP protocol methods

  defp dispatch_method(_team, "initialize", _params) do
    {:ok,
     %{
       "protocolVersion" => "2024-11-05",
       "capabilities" => %{"tools" => %{}},
       "serverInfo" => %{"name" => "SAR Duty", "version" => "1.0.0"}
     }}
  end

  defp dispatch_method(_team, "initialized", _params), do: :notification

  defp dispatch_method(_team, "ping", _params), do: {:ok, %{}}

  defp dispatch_method(_team, "tools/list", _params) do
    {:ok, %{"tools" => tool_definitions()}}
  end

  defp dispatch_method(team, "tools/call", %{"name" => name} = params) do
    args = Map.get(params, "arguments", %{})
    call_tool(team, name, args)
  end

  defp dispatch_method(_team, method, _params) do
    {:error, -32_601, "Method not found: #{method}"}
  end

  # Tools

  defp call_tool(team, "get_team_info", _args) do
    data = %{
      id: team.id,
      name: team.name,
      subdomain: team.subdomain,
      timezone: team.timezone,
      mailing_address: team.mailing_address,
      authorized_by_name: team.authorized_by_name,
      lat: team.lat,
      lng: team.lng,
      d4h_refreshed_at: format_datetime(team.d4h_refreshed_at),
      d4h_refresh_result: team.d4h_refresh_result
    }

    {:ok, text_result(data)}
  end

  defp call_tool(team, "list_members", args) do
    active_only = Map.get(args, "active_only", false)

    members =
      Member
      |> where([m], m.team_id == ^team.id)
      |> then(fn q ->
        if active_only, do: where(q, [m], is_nil(m.left_at)), else: q
      end)
      |> order_by([m], asc: m.name)
      |> Repo.all()

    {:ok, text_result(Enum.map(members, &format_member/1))}
  end

  defp call_tool(team, "get_member", %{"id" => id}) do
    member =
      Member
      |> where([m], m.team_id == ^team.id and m.id == ^id)
      |> Repo.one()

    case member do
      nil -> {:error, -32_602, "Member not found or does not belong to this team"}
      m -> {:ok, text_result(format_member(m))}
    end
  end

  defp call_tool(team, "list_activities", args) do
    limit = Map.get(args, "limit", 100) |> min(1000)
    offset = Map.get(args, "offset", 0)
    kind = Map.get(args, "kind")
    year = Map.get(args, "year")

    activities =
      Activity
      |> where([a], a.team_id == ^team.id)
      |> then(fn q ->
        if kind, do: where(q, [a], a.activity_kind == ^kind), else: q
      end)
      |> then(fn q ->
        if year do
          where(
            q,
            [a],
            fragment("strftime('%Y', ?) = ?", a.started_at, ^to_string(year))
          )
        else
          q
        end
      end)
      |> order_by([a], desc: a.started_at)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {:ok, text_result(Enum.map(activities, &format_activity/1))}
  end

  defp call_tool(team, "get_activity", %{"id" => id}) do
    activity =
      Activity
      |> where([a], a.team_id == ^team.id and a.id == ^id)
      |> Repo.one()

    case activity do
      nil -> {:error, -32_602, "Activity not found or does not belong to this team"}
      a -> {:ok, text_result(format_activity(a))}
    end
  end

  defp call_tool(team, "list_attendances_for_activity", %{"activity_id" => activity_id}) do
    case Repo.get_by(Activity, id: activity_id, team_id: team.id) do
      nil ->
        {:error, -32_602, "Activity not found or does not belong to this team"}

      _activity ->
        attendances =
          Attendance
          |> where([at], at.activity_id == ^activity_id)
          |> join(:inner, [at], m in assoc(at, :member))
          |> preload([at, m], member: m)
          |> Repo.all()

        {:ok, text_result(Enum.map(attendances, &format_attendance/1))}
    end
  end

  defp call_tool(team, "list_attendances_for_member", %{"member_id" => member_id} = args) do
    limit = Map.get(args, "limit", 100) |> min(1000)
    offset = Map.get(args, "offset", 0)

    case Repo.get_by(Member, id: member_id, team_id: team.id) do
      nil ->
        {:error, -32_602, "Member not found or does not belong to this team"}

      _member ->
        attendances =
          Attendance
          |> where([at], at.member_id == ^member_id)
          |> join(:inner, [at], a in assoc(at, :activity))
          |> where([at, a], a.team_id == ^team.id)
          |> preload([at, a], activity: a)
          |> order_by([at], desc: at.started_at)
          |> limit(^limit)
          |> offset(^offset)
          |> Repo.all()

        {:ok, text_result(Enum.map(attendances, &format_attendance/1))}
    end
  end

  defp call_tool(team, "list_qualifications", _args) do
    qualifications =
      Qualification
      |> where([q], q.team_id == ^team.id)
      |> order_by([q], asc: q.title)
      |> Repo.all()

    {:ok, text_result(Enum.map(qualifications, &format_qualification/1))}
  end

  defp call_tool(team, "get_member_qualifications", %{"member_id" => member_id}) do
    case Repo.get_by(Member, id: member_id, team_id: team.id) do
      nil ->
        {:error, -32_602, "Member not found or does not belong to this team"}

      _member ->
        awards =
          MemberQualificationAward
          |> where([a], a.member_id == ^member_id)
          |> join(:inner, [a], q in assoc(a, :qualification))
          |> where([a, q], q.team_id == ^team.id)
          |> preload([a, q], qualification: q)
          |> Repo.all()

        {:ok, text_result(Enum.map(awards, &format_member_qualification_award/1))}
    end
  end

  defp call_tool(team, "list_tax_credit_letters", args) do
    year = Map.get(args, "year")
    member_id = Map.get(args, "member_id")

    letters =
      from(tcl in TaxCreditLetter,
        join: m in assoc(tcl, :member),
        where: m.team_id == ^team.id,
        preload: [member: m]
      )
      |> then(fn q -> if year, do: where(q, [tcl], tcl.year == ^year), else: q end)
      |> then(fn q ->
        if member_id, do: where(q, [tcl], tcl.member_id == ^member_id), else: q
      end)
      |> order_by([tcl], desc: tcl.year)
      |> Repo.all()

    {:ok, text_result(Enum.map(letters, &format_tax_credit_letter/1))}
  end

  defp call_tool(_team, name, _args) do
    {:error, -32_602, "Unknown tool: #{name}"}
  end

  # Formatters

  defp format_member(m) do
    %{
      id: m.id,
      name: m.name,
      ref_id: m.ref_id,
      position: m.position,
      email: m.email,
      phone: m.phone,
      address: m.address,
      joined_at: format_datetime(m.joined_at),
      left_at: format_datetime(m.left_at)
    }
  end

  defp format_activity(a) do
    %{
      id: a.id,
      title: a.title,
      ref_id: a.ref_id,
      tracking_number: a.tracking_number,
      activity_kind: a.activity_kind,
      hours_kind: a.hours_kind,
      is_published: a.is_published,
      description: a.description,
      address: a.address,
      tags: a.tags,
      started_at: format_datetime(a.started_at),
      finished_at: format_datetime(a.finished_at)
    }
  end

  defp format_attendance(at) do
    base = %{
      id: at.id,
      activity_id: at.activity_id,
      member_id: at.member_id,
      duration_in_minutes: at.duration_in_minutes,
      status: at.status,
      started_at: format_datetime(at.started_at),
      finished_at: format_datetime(at.finished_at)
    }

    base =
      if Ecto.assoc_loaded?(at.member),
        do: Map.put(base, :member_name, at.member.name),
        else: base

    if Ecto.assoc_loaded?(at.activity),
      do: Map.put(base, :activity_title, at.activity.title),
      else: base
  end

  defp format_qualification(q) do
    %{
      id: q.id,
      title: q.title,
      d4h_qualification_id: q.d4h_qualification_id
    }
  end

  defp format_member_qualification_award(award) do
    base = %{
      id: award.id,
      member_id: award.member_id,
      qualification_id: award.qualification_id,
      starts_at: format_datetime(award.starts_at),
      ends_at: format_datetime(award.ends_at)
    }

    if Ecto.assoc_loaded?(award.qualification),
      do: Map.put(base, :qualification_title, award.qualification.title),
      else: base
  end

  defp format_tax_credit_letter(tcl) do
    base = %{
      id: tcl.id,
      ref_id: tcl.ref_id,
      member_id: tcl.member_id,
      year: tcl.year,
      inserted_at: format_datetime(tcl.inserted_at)
    }

    if Ecto.assoc_loaded?(tcl.member),
      do: Map.put(base, :member_name, tcl.member.name),
      else: base
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(dt), do: DateTime.to_iso8601(dt)

  defp text_result(data) do
    %{"content" => [%{"type" => "text", "text" => Jason.encode!(data)}]}
  end

  defp tool_definitions do
    [
      %{
        "name" => "get_team_info",
        "description" => "Get information about this SAR team",
        "inputSchema" => %{"type" => "object", "properties" => %{}, "required" => []}
      },
      %{
        "name" => "list_members",
        "description" =>
          "List all members of the team. Returns name, position, contact info, and join/leave dates.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "active_only" => %{
              "type" => "boolean",
              "description" =>
                "When true, only return current members (those without a left_at date)"
            }
          },
          "required" => []
        }
      },
      %{
        "name" => "get_member",
        "description" => "Get full details for a specific member by their ID",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "integer", "description" => "The member's ID"}
          },
          "required" => ["id"]
        }
      },
      %{
        "name" => "list_activities",
        "description" =>
          "List activities (operations, training, meetings, etc.) for the team. Supports filtering by kind and year with pagination.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum results to return (default 100, max 1000)"
            },
            "offset" => %{
              "type" => "integer",
              "description" => "Number of results to skip for pagination (default 0)"
            },
            "kind" => %{
              "type" => "string",
              "description" =>
                "Filter by activity_kind (e.g. 'operation', 'training', 'meeting')"
            },
            "year" => %{
              "type" => "integer",
              "description" => "Filter by the year the activity started"
            }
          },
          "required" => []
        }
      },
      %{
        "name" => "get_activity",
        "description" => "Get full details for a specific activity by ID",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "integer", "description" => "The activity's ID"}
          },
          "required" => ["id"]
        }
      },
      %{
        "name" => "list_attendances_for_activity",
        "description" =>
          "Get all member attendances for a specific activity, including each member's name and duration in minutes",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "activity_id" => %{"type" => "integer", "description" => "The activity's ID"}
          },
          "required" => ["activity_id"]
        }
      },
      %{
        "name" => "list_attendances_for_member",
        "description" =>
          "Get all activity attendances for a specific member, showing which activities they attended and for how long",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "member_id" => %{"type" => "integer", "description" => "The member's ID"},
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum results to return (default 100, max 1000)"
            },
            "offset" => %{
              "type" => "integer",
              "description" => "Number of results to skip for pagination (default 0)"
            }
          },
          "required" => ["member_id"]
        }
      },
      %{
        "name" => "list_qualifications",
        "description" => "List all qualifications/certifications defined for this team",
        "inputSchema" => %{"type" => "object", "properties" => %{}, "required" => []}
      },
      %{
        "name" => "get_member_qualifications",
        "description" =>
          "Get all qualifications awarded to a specific member, including their validity dates",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "member_id" => %{"type" => "integer", "description" => "The member's ID"}
          },
          "required" => ["member_id"]
        }
      },
      %{
        "name" => "list_tax_credit_letters",
        "description" =>
          "List tax credit letters issued to team members. Can filter by year or by member.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "year" => %{
              "type" => "integer",
              "description" => "Filter by the tax credit year"
            },
            "member_id" => %{
              "type" => "integer",
              "description" => "Filter by a specific member's ID"
            }
          },
          "required" => []
        }
      }
    ]
  end
end
