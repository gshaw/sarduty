defmodule App.Model.TemplateGroup do
  use App, :model

  alias App.Model.Group
  alias App.Model.Template

  # One group whose members a template adds to an activity (#162).
  schema "template_groups" do
    belongs_to :template, Template
    belongs_to :group, Group
    timestamps(type: :utc_datetime_usec)
  end
end
