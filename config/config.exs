import Config

# {ips, 0} = System.cmd("ip", ~w|address show|)
# [[_, _ip]] = Regex.scan(~r/inet ([\d.]+)\/\d+ scope global tun0/, ips)

{ip, 0} = System.cmd("hostname", [])
IO.puts("Configuring cloister for ip: #{ip}")

config :logger,
  level: :info,
  backends: [:console],
  metadata: :all,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :cloister,
  sentry: ~w|cloister@#{ip}|a,
  consensus: 1,
  magic?: :shortnames

if File.exists?("config/#{Mix.env()}.exs"), do: import_config("#{Mix.env()}.exs")
