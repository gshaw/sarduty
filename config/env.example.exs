vars = %{
  "MAPBOX_ACCESS_TOKEN" => "pk___"
}

Enum.each(vars, fn {k, v} -> System.put_env(k, v) end)
