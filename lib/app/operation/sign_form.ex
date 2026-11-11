defmodule App.Operation.SignForm do
  @moduledoc """
  Who signs a form and for whom (#993). A form names its signer with `signed by`, such
  as `` signed by task.`Task Leader's Name` ``: the task leader is the one member in good
  standing with that name, ignoring case and extra spaces (`App.Model.Member.named/4`).

  - The task leader signs in their own name: "/s/ Cameron Ruiz".
  - Any other team admin signs in their own name, for the task leader: "/s/ Alex Chen
    for Cameron Ruiz". The task leader's name never follows "/s/" unless they signed.
  - With no member by that name, or two, it's for the field's text, and nobody hears.

  The date is the day it's signed, and the signer block, such as the Expense request's
  Name, Email, and Telephone, comes from the signer's member record. A draft is never
  signed. App.Operation.PrintForm prints with what `call/4` gives, and
  App.Operation.PublishDocument keeps who signed and emails the task leader.
  """

  alias App.Document
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo
  alias App.Report.Context

  @doc """
  The task leader named `name`, as App.Document.signed_by/3 reads it from a form's
  values: `%{name, members}`, `members` the team's members with that name, none, one,
  or more, read from `repo`. A blank name has none.
  """
  def leader(name, team, now, repo \\ Repo)
  def leader(nil, _team, _now, _repo), do: %{name: nil, members: []}

  def leader(name, %Team{} = team, now, repo),
    do: %{name: name, members: Member.named(team, name, now, repo)}

  @doc """
  `signer` signs form `doc` with the values it read, on the team's day today: what
  `signing/3` gives, or nil when the form names no signer.
  """
  def call(%Document{signed_by: nil}, _values, _context, _signer), do: nil

  def call(%Document{} = doc, values, %Context{} = context, %Member{} = signer) do
    name = Document.signed_by(doc, values, context.timezone)
    signing(signer, leader(name, context.team, context.now, context.repo), context.today)
  end

  @doc """
  Pure. `signer`, a member, signs for `leader` (`leader/4`'s) on `day`: `%{signed_by,
  signed_for, email, phone, signed_on, leader, leader_name, problem}`. `signed_for` is
  nil when the signer is the task leader, else the task leader's name, or the field's
  text when no one member has it. `leader` is the task leader's member, or nil when
  there's none or two, so nobody is emailed; `leader_name` is the field's text, and
  `problem` what `problem/1` says of it. `values/1` turns it into a form's values.
  """
  def signing(%Member{} = signer, %{name: name, members: members} = found, %Date{} = day) do
    leader = one(members)

    %{
      signed_by: signer.name,
      signed_for: signed_for(signer, leader, name),
      email: blank_to_nil(signer.email),
      phone: blank_to_nil(signer.phone),
      signed_on: day,
      leader: leader,
      leader_name: name,
      problem: problem(found)
    }
  end

  defp one([member]), do: member
  defp one(_none_or_more), do: nil

  defp signed_for(%Member{id: id}, %Member{id: id}, _name), do: nil
  defp signed_for(_signer, %Member{name: name}, _text), do: name
  defp signed_for(_signer, nil, text), do: text

  defp blank_to_nil(text) when is_binary(text), do: if(String.trim(text) != "", do: text)
  defp blank_to_nil(_blank), do: nil

  @doc """
  Pure. Whether the task leader hears that someone signed for them (#993): they're one
  member, with an email. The confirm says so, and App.Operation.PublishDocument sends it.
  """
  def tells_leader?(%{signed_for: whom, leader: %Member{email: email}}) when is_binary(whom),
    do: is_binary(email) and String.trim(email) != ""

  def tells_leader?(_signed), do: false

  @doc "Pure. A signing's values for a form, as App.Document.signer/1 reads them."
  def values(signed),
    do:
      Document.signer(%{
        name: signed.signed_by,
        email: signed.email,
        phone: signed.phone,
        signed_on: signed.signed_on,
        signed_for: signed.signed_for
      })

  @doc """
  Pure. What the form page says when its task leader is no one member (#993): "No member
  is named Ave Chen", "2 members are named Ave Chen", or nil when one is, or the field is
  blank, which Needed to publish says.
  """
  def problem(%{name: nil}), do: nil
  def problem(%{members: [_one]}), do: nil
  def problem(%{name: name, members: []}), do: "No member is named #{name}"

  def problem(%{name: name, members: members}),
    do:
      "#{Service.Format.count(length(members), one: "%d member is", many: "%d members are")} named #{name}"
end
