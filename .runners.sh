alias mixtest="MIX_ENV=test mix deps.compile test_cluster_task && MIX_ENV=test mix test.cluster"
alias iextest="MIX_ENV=test mix deps.compile test_cluster_task && MIX_ENV=test iex -S mix test.cluster"
alias iexrun="MIX_ENV=dev mix deps.compile test_cluster_task && MIX_ENV=dev iex -S mix run.cluster"
