if File.exists?("tmp/samples.dump") do
  NauticNet.Seeds.clean_and_restore_samples()
else
  IO.puts("tmp/samples.dump not found; aborting")
end
