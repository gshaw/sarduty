defmodule App.Repo.Migrations.AddWhoAndIpKeyToEvents do
  use Ecto.Migration

  # Events get the two values they're looked up by as columns (#974): `who`, the keyed
  # hash of a typed email or number, moved out of `data`, and `ip_key`, the IP as the
  # limits count it (IPv6 by its /64). The login limits count from them (#975).
  # Production had 13,769 events on 2026-11-09, 422 with an IP, so no batching.
  def up do
    alter table(:events) do
      add :who, :string
      add :ip_key, :string
    end

    execute """
    UPDATE events SET who = json_extract(data, '$.who'), data = json_remove(data, '$.who')
    WHERE json_extract(data, '$.who') IS NOT NULL
    """

    execute "UPDATE events SET ip_key = ip WHERE ip IS NOT NULL AND instr(ip, ':') = 0"
    execute &fill_ipv6_keys/0

    create index(:events, [:kind, :who, :occurred_at])
    create index(:events, [:kind, :ip_key, :occurred_at])
  end

  def down do
    drop index(:events, [:kind, :ip_key, :occurred_at])
    drop index(:events, [:kind, :who, :occurred_at])

    execute "UPDATE events SET data = json_set(data, '$.who', who) WHERE who IS NOT NULL"

    alter table(:events) do
      remove :ip_key
      remove :who
    end
  end

  defp fill_ipv6_keys do
    %{rows: rows} = repo().query!("SELECT DISTINCT ip FROM events WHERE instr(ip, ':') > 0")

    for [ip] <- rows do
      repo().query!("UPDATE events SET ip_key = ? WHERE ip = ?", [App.RateLimit.ip_key(ip), ip])
    end
  end
end
