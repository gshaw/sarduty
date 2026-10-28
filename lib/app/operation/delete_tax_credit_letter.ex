defmodule App.Operation.DeleteTaxCreditLetter do
  @moduledoc """
  Deletes a letter. Its reference number stops verifying, and so do the numbers of the
  letters it replaced, which go with it: only a current letter verifies. Expects the
  letter from `TaxCreditLetter.find!/2`, so it is the team's.
  """

  alias App.Model.TaxCreditLetter
  alias App.Repo

  def call(%TaxCreditLetter{} = letter), do: Repo.delete!(letter)
end
