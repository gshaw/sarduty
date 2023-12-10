defmodule App do
  @doc """
  The entrypoint for defining database backed models.  E.g.

      use App, :model

  The definitions below are executed for every model. Keep them short and
  clean, focused on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions. Instead, define
  helper function in modules and import those modules.
  """
  def model do
    quote do
      use Ecto.Schema

      import Ecto.Changeset
      import Ecto.Query
    end
  end

  def view_model do
    quote do
      use Ecto.Schema

      import Ecto.Changeset
    end
  end

  @doc """
  When used, dispatch to the appropriate module.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
