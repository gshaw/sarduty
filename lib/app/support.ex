defmodule App.Support do
  @moduledoc """
  How people reach the SAR Duty site admins, the people who run SAR Duty (#780): one
  address, and their names for Get help. SAR Duty admins log in by email
  (`App.Accounts.admin_emails/0`); this list is only who Get help names.
  """

  @email "support@sarduty.com"
  @site_admins ["Gerry Shaw", "Andrew Wallwork"]

  @doc "The address every message to the SAR Duty site admins goes to."
  def email, do: @email

  @doc "The SAR Duty site admins' names, as Get help lists them."
  def site_admins, do: @site_admins
end
