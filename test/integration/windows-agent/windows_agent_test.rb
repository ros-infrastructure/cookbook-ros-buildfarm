# InSpec tests for recipe ros_buildfarm::windows_agent

# System configuration

describe registry_key('HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\FileSystem') do
  its('LongPathsEnabled') { should eq 1 }
end

describe directory('C:\\J') do
  it { should exist }
end

describe powershell("Get-NetFirewallRule -DisplayName 'Block metadata service altogether' | Get-NetFirewallAddressFilter | Select-Object -ExpandProperty RemoteAddress") do
  its('stdout') { should include '169.254.169.254' }
end

# Packages

describe powershell("Get-ItemProperty 'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*' | Where-Object { $_.DisplayName -like '*OpenJDK*25*' } | Measure-Object | Select-Object -ExpandProperty Count") do
  its('stdout.strip.to_i') { should be >= 1 }
end

describe command('git --version') do
  its('exit_status') { should eq 0 }
end

# Chocolatey must be the pinned version, even if the base image shipped another one.
describe powershell('choco --version') do
  its('stdout.strip') { should eq '2.7.5' } # keep in sync with windows_chocolatey_version
end

# Docker

describe service('docker') do
  it { should be_installed }
  it { should be_running }
end

# The docker service must run the pinned version, even if the base image shipped another one.
describe powershell('dockerd --version') do
  its('stdout') { should include 'version 29.10.0,' } # keep in sync with windows_docker_version
end

describe powershell('(Get-MpPreference).ExclusionPath') do
  its('stdout') { should include 'C:\\J' }
  its('stdout') { should include 'C:\\ProgramData\\docker' }
end

describe powershell('(Get-MpPreference).DisableRealtimeMonitoring') do
  its('stdout.strip') { should eq 'True' }
end

# Jenkins swarm agent

agent_dir = 'C:\\jenkins-agent'

describe file("#{agent_dir}\\jenkins-agent.exe") do
  it { should exist }
end

describe command("Get-ChildItem '#{agent_dir}\\swarm-client-*.jar' | Measure-Object | Select-Object -ExpandProperty Count") do
  its('stdout.strip') { should eq '1' }
end

describe directory("#{agent_dir}\\logs") do
  it { should exist }
end

# The WinSW configuration must be valid XML and pass the expected arguments to the swarm client.
describe powershell("([xml](Get-Content -Raw '#{agent_dir}\\jenkins-agent.xml')).service.arguments.InnerText") do
  its('exit_status') { should eq 0 }
  its('stdout') { should match(/-jar "C:\\jenkins-agent\\swarm-client-.*\.jar"/) }
  its('stdout') { should include '-url http://localhost:8080' }
  its('stdout') { should include "-passwordFile \"#{agent_dir}\\token\"" }
  its('stdout') { should include '-fsroot "C:\\J"' }
  its('stdout') { should include '-labels "buildagent"' }
end

# The service must run the JDK installed by the recipe, not whatever java is on PATH.
java_exe = 'C:\\Program Files\\Microsoft\\jdk-25\\bin\\java.exe'

describe file(java_exe) do
  it { should exist }
end

describe powershell("([xml](Get-Content -Raw '#{agent_dir}\\jenkins-agent.xml')).service.executable") do
  its('stdout.strip') { should eq java_exe }
end

# The token must only be readable by Administrators and SYSTEM.
describe powershell("((Get-Acl '#{agent_dir}\\token').Access | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique) -join ','") do
  its('stdout.strip') { should eq 'BUILTIN\\Administrators,NT AUTHORITY\\SYSTEM' }
end

describe service('jenkins-agent') do
  it { should be_installed }
  it { should be_enabled }
end
