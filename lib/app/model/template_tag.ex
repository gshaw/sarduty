defmodule App.Model.TemplateTag do
  use App, :model

  alias App.Model.Tag
  alias App.Model.Template

  # One tag a template adds to an activity (#162).
  schema "template_tags" do
    belongs_to :template, Template
    belongs_to :tag, Tag
    timestamps(type: :utc_datetime_usec)
  end
end
