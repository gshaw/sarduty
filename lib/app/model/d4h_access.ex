defmodule App.Model.D4HAccess do
  @moduledoc """
  What D4H lets a team's key do (#727), the one home for which D4H rights each thing
  SAR Duty does needs. D4H's `/whoami` sends the key's rights as a map of resource →
  action → true or false, stored on the team as `d4h_permissions`.

  A key acts as the D4H member who made it. Owners' keys have every right SAR Duty
  uses; Editors' lack a few, such as adding custom fields (#724). Custom field answers
  need only the record's own UPDATE.

  Pure. A nil map, a Records team's or one never checked, refuses nothing.
  """

  @read [
    {"Team", "READ"},
    {"Member", "READ"},
    {"Incident", "READ"},
    {"Exercise", "READ"},
    {"Event", "READ"},
    {"ActivityAttendance", "READ"},
    {"MemberGroup", "READ"},
    {"MemberQualification", "READ"},
    {"MemberQualificationAward", "READ"},
    {"Equipment", "READ"},
    {"Tag", "READ"}
  ]

  # In the order the Access key tab lists them. Adding someone to a group is
  # MemberGroup.UPDATE (#727, decision 3).
  @features [
    %{
      id: :read,
      name: "Copy your team",
      what: "Members, activities, attendance, groups, awards, and equipment.",
      needs: @read
    },
    %{
      id: :attendance,
      name: "Send attendance",
      what: "Take attendance, replies, and adding members to an activity.",
      needs: [
        {"ActivityAttendance", "CREATE"},
        {"ActivityAttendance", "UPDATE"},
        {"ActivityAttendance", "DELETE"}
      ]
    },
    %{
      id: :groups,
      name: "Change groups",
      what: "Groups, who is in them, and group rules.",
      needs: [{"MemberGroup", "CREATE"}, {"MemberGroup", "UPDATE"}, {"MemberGroup", "DELETE"}]
    },
    %{
      id: :activities,
      name: "Add and change activities",
      what: "Details, tags, publishing, and templates.",
      needs:
        for(type <- ~w(Incident Exercise Event), action <- ~w(CREATE UPDATE), do: {type, action})
    },
    %{
      id: :equipment_usage,
      name: "Equipment on activities",
      what: "Which items went out on an activity.",
      needs: [{"Equipment", "UPDATE_USAGE"}]
    },
    %{
      id: :members,
      name: "Change members",
      what: "Details, photos, and retiring.",
      needs: [{"Member", "UPDATE"}, {"Member", "RETIRE"}]
    },
    %{
      id: :equipment,
      name: "Change equipment",
      what: "An item's status and barcode.",
      needs: [{"Equipment", "UPDATE"}, {"Equipment", "UPDATE_STATUS"}]
    },
    %{
      id: :field_values,
      name: "Fill in fields",
      what: "Answers to custom fields on activities, members, and equipment.",
      needs: for(type <- ~w(Incident Exercise Event Member Equipment), do: {type, "UPDATE"})
    },
    %{
      id: :awards,
      name: "Record awards",
      what: "Awards and their certificates.",
      needs: [
        {"MemberQualificationAward", "CREATE"},
        {"MemberQualificationAward", "DELETE"},
        {"Document", "CREATE"}
      ]
    },
    %{
      id: :whiteboard,
      name: "Whiteboard",
      what: "Notes on the Dashboard.",
      needs: [
        {"Whiteboard", "READ"},
        {"Whiteboard", "CREATE"},
        {"Whiteboard", "UPDATE"},
        {"Whiteboard", "DELETE"}
      ]
    }
  ]

  @doc "Everything SAR Duty does with a D4H key, in order."
  def features, do: @features

  @doc "Whether `permissions` has every right `feature` needs. A nil map allows all."
  def can?(nil, _feature), do: true

  def can?(permissions, feature) when is_map(permissions) and is_atom(feature) do
    %{needs: needs} = Enum.find(@features, &(&1.id == feature)) || raise "No feature #{feature}"
    Enum.all?(needs, fn {resource, action} -> get_in(permissions, [resource, action]) == true end)
  end

  @doc "The features `permissions` refuses, in order. None for a nil map."
  def refused(permissions), do: Enum.reject(@features, &can?(permissions, &1.id))
end
