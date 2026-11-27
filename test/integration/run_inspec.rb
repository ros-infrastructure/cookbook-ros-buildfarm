# Runs an InSpec profile on the local Windows machine, used by CI instead of `kitchen verify`.
# kitchen-inspec cannot select train's command runner, and the default named-pipe runner hangs
# on GitHub's Windows runners. windows_shell starts one PowerShell per command instead.
require 'inspec'

runner = Inspec::Runner.new(command_runner: :windows_shell, reporter: ['cli'])
runner.add_target(ARGV.fetch(0))
exit runner.run
