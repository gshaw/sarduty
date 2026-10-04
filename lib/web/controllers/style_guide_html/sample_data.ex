defmodule Web.StyleGuideHTML.SampleData do
  @moduledoc false

  # cspell:ignore Tremblay
  # Made-up rows for the style guide, shaped like the app's pages.

  def letters do
    [
      %{
        id: 101,
        name: "Avery Chen",
        email: "avery@example.com",
        primary: "212h 30m",
        secondary: "18h 00m",
        total: "230h 30m",
        letter: "TCL-2025-014"
      },
      %{
        id: 117,
        name: "Blake Morrison",
        email: "blake@example.com",
        primary: "198h 15m",
        secondary: "4h 45m",
        total: "203h 00m",
        letter: nil
      },
      %{
        id: 123,
        name: "Casey Dhillon",
        email: "casey@example.com",
        primary: "156h 00m",
        secondary: "62h 30m",
        total: "218h 30m",
        letter: "TCL-2025-015"
      },
      %{
        id: 131,
        name: "Devon Okafor",
        email: "devon@example.com",
        primary: "88h 45m",
        secondary: "12h 15m",
        total: "101h 00m",
        letter: nil
      },
      %{
        id: 152,
        name: "Finley Tremblay",
        email: "finley@example.com",
        primary: "41h 00m",
        secondary: "9h 30m",
        total: "50h 30m",
        letter: nil
      }
    ]
  end

  def recommendations do
    [
      %{op: :add, name: "Avery Chen", email: "avery@example.com", phone: "604-555-0101"},
      %{op: :add, name: "Casey Dhillon", email: "casey@example.com", phone: "604-555-0123"},
      %{op: :remove, name: "Devon Okafor", email: "devon@example.com", phone: "604-555-0131"},
      %{op: :not_invited, name: "Jordan Park", email: "jordan@example.com", phone: "604-555-0177"}
    ]
  end

  def clauses do
    [
      %{name: "First Aid", qualifications: ["OFA Level 1", "Wilderness First Aid", "EMR"]},
      %{name: "Ground Search", qualifications: ["GSAR Member", "Missing: Team Leader 2019"]},
      %{name: "", qualifications: []}
    ]
  end

  def preview do
    %{
      to_remove: [%{name: "Devon Okafor", reason: "No First Aid qualification"}],
      to_add: [%{name: "Avery Chen", reason: "Holds OFA Level 1 and GSAR Member"}],
      expiring: [
        %{name: "Casey Dhillon", reason: "Wilderness First Aid expires Nov 12", days: 12}
      ]
    }
  end
end
