# ---------------------
# System configuration
# ---------------------

# Enable the w32time service explicitly, replaces meinberg-ntp
windows_service 'w32time' do
  action [:enable, :start]
end

# Jenkins workspace root. The agent service runs as LocalSystem, which has full access.
directory node['ros_buildfarm']['agent']['windows_fsroot'] do
  recursive true
  action :create
end

# Enable LongPaths
registry_key 'HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\FileSystem' do
  values [{
    name: 'LongPathsEnabled',
    type: :dword,
    data: 1},
    ]
  action :create
end

# Block EC2 metadata calls from the instance
batch 'block_ec2_metadata' do 
  code 'netsh advfirewall firewall add rule name="Block metadata service altogether" dir=out protocol=TCP remoteip=169.254.169.254 action=block'
end

# -----------------
# Install packages
# -----------------

jdk_version = node['ros_buildfarm']['agent']['jdk_version'].to_s
jdk = node['ros_buildfarm']['agent']['windows_jdk'][jdk_version]
raise "No Windows JDK defined for version #{jdk_version}" if jdk.nil?

# https://learn.microsoft.com/en-us/java/openjdk/download
package "Microsoft Build of OpenJDK #{jdk_version}" do
  source "https://aka.ms/download-jdk/microsoft-jdk-#{jdk['full_version']}-windows-x64.exe"
  checksum jdk['checksum']
  options "/VERYSILENT /SUPPRESSMSGBOXES /ALLUSERS /TASKS=\"FeatureEnvironment,FeatureJarFileRunWith\" /DIR=\"#{jdk['install_dir']}\""
  action :install
end

# Built into Chef since 18.3, avoids depending on the chocolatey cookbook.
# https://docs.chef.io/resources/chocolatey_installer/
chocolatey_installer 'chocolatey' do
  chocolatey_version '2.7.5'
  action :install
end

chocolatey_package 'git' do
  action :install
end

windows_feature 'VirtualMachinePlatform'
windows_feature 'Microsoft-Hyper-V'
windows_feature 'Containers'

docker_script = ::File.join(Chef::Config[:file_cache_path], 'docker_install.ps1')

cookbook_file docker_script do
  source 'agent/docker_install.ps1'
end

powershell_script 'install-docker' do
  code "& '#{docker_script}' -NoRestart -DockerVersion '#{node['ros_buildfarm']['agent']['windows_docker_version']}'"
  not_if '(Get-Service docker -ErrorAction SilentlyContinue) -ne $null'
end

# Disabling realtime monitoring prevents Windows Defender from scanning newly created files.
# So far, it is the only resolution to defender taking too much cpu during builds. Still, it might
# be a bit overkill. Excluding the following directories and processes only seemed to reduce cpu
# usage of windows defender to 50%
powershell_script 'configure-defender-exclusions' do
  code <<-EOH
  # Add Docker paths to prevent them from being scanned by Microsoft's Antimalware service
  Add-MpPreference -ExclusionPath "C:\\Users\\Administrator\\.docker"
  Add-MpPreference -ExclusionPath "C:\\J"
  Add-MpPreference -ExclusionPath "C:\\ProgramData\\docker"
  Add-MpPreference -ExclusionPath "C:\\ci"
  Add-MpPreference -ExclusionProcess "docker.exe"
  Add-MpPreference -ExclusionProcess "dockerd.exe"
  Add-MpPreference -ExclusionProcess "MSBuild.exe"
  Add-MpPreference -ExclusionProcess "cmake.exe"
  Add-MpPreference -ExclusionProcess "cl.exe"
  Add-MpPreference -ExclusionProcess "link.exe"
  Set-MpPreference -DisableRealtimeMonitoring $True
  EOH
  live_stream true
end

include_recipe '::windows_jenkins_swarm_agent'

