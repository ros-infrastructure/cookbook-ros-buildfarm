# Connects a Windows machine to the Jenkins manager as a swarm agent.
# Chocolatey must already be installed on the machine.

chocolatey_package 'git'
chocolatey_package "temurin#{node['ros_buildfarm']['agent']['jdk_version']}jre"

win = node['ros_buildfarm']['agent']['windows']
agent_username = win['agent_username']
agent_homedir = "C:\\Users\\#{agent_username}"
fsroot = win['fsroot']
logdir = "#{agent_homedir}\\logs"
service_name = 'jenkins-agent'
winsw_path = "#{agent_homedir}\\jenkins-agent-windows-service.exe"

directory fsroot do
  recursive true
end

registry_key 'HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\FileSystem' do
  values [{ name: 'LongPathsEnabled', type: :dword, data: 1 }]
end

# Docker (ported from ros2ci::windows_docker)
%w(VirtualMachinePlatform Microsoft-Hyper-V Containers).each do |feature|
  windows_feature feature
end

cookbook_file 'C:\\docker_install.ps1' do
  source 'docker_install.ps1'
end

powershell_script 'install-docker' do
  code 'C:\\docker_install.ps1'
  not_if 'Get-Command docker -ErrorAction SilentlyContinue'
end

# Keeps Windows Defender from consuming the CPU during builds.
powershell_script 'docker-defender-exclusions' do
  code <<~EOH
    Add-MpPreference -ExclusionPath "#{agent_homedir}\\.docker"
    Add-MpPreference -ExclusionPath "#{fsroot}"
    Add-MpPreference -ExclusionPath "C:\\ProgramData\\docker"
    Add-MpPreference -ExclusionProcess "docker.exe"
    Add-MpPreference -ExclusionProcess "dockerd.exe"
    Add-MpPreference -ExclusionProcess "MSBuild.exe"
    Add-MpPreference -ExclusionProcess "cmake.exe"
    Add-MpPreference -ExclusionProcess "cl.exe"
    Add-MpPreference -ExclusionProcess "link.exe"
    Set-MpPreference -DisableRealtimeMonitoring $True
  EOH
end

swarm_version = node['ros_buildfarm']['jenkins']['plugins']['swarm']
swarm_jar = "swarm-client-#{swarm_version}.jar"
swarm_jar_path = "#{agent_homedir}\\#{swarm_jar}"

remote_file swarm_jar_path do
  source "https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/#{swarm_version}/#{swarm_jar}"
  retries 5
end

remote_file winsw_path do
  source 'https://github.com/winsw/winsw/releases/download/v2.2.0/WinSW.NET4.exe'
  retries 5
end

directory logdir

jenkins_username = node['ros_buildfarm']['agent']['username']
agent_jenkins_user = search('ros_buildfarm_jenkins_users', "username:#{jenkins_username}").first

template "#{agent_homedir}\\jenkins-agent-windows-service.xml" do
  source 'jenkins-agent-windows.xml.erb'
  sensitive true
  variables Hash[
    service_name: service_name,
    description: node['ros_buildfarm']['agent']['description'],
    java_args: win['java_args'],
    jarfile: swarm_jar_path,
    jenkins_url: node['ros_buildfarm']['jenkins_url'],
    username: jenkins_username,
    password: agent_jenkins_user['password'],
    name: node['ros_buildfarm']['agent']['nodename'],
    executors: node['ros_buildfarm']['agent']['executors'],
    labels: node['ros_buildfarm']['agent']['labels'],
    fsroot: fsroot,
    logdir: logdir
  ]
  notifies :restart, "service[#{service_name}]"
end

execute 'install-jenkins-agent-service' do
  command "\"#{winsw_path}\" install"
  not_if "powershell -Command \"Get-Service '#{service_name}'\""
end

service service_name do
  action [:enable, :start]
end
