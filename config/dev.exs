import Config

# {ips, 0} = System.cmd("ip", ~w|address show|)
# [[_, _ip]] = Regex.scan(~r/inet ([\d.]+)\/\d+ scope global tun0/, ips)

ip = "127.0.0.1"
IO.puts("Configuring cloister for ip: #{ip}")

config :cloister,
  sentry: ~w|cloister@#{ip} c1@#{ip} c2@#{ip}|a,
  consensus: 2,
  magic?: :shortnames
