machine do
  cpus 1
  cpu_kind 'shared'
  memory_mb 512
end

sqlite3 do
  size 3
end

redis do
  plan "Free"
end
