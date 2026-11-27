# Install the Jenkins swarm client and run it as a Windows service through WinSW.
# Windows counterpart of the swarm client setup in recipes/agent.rb.

service_name = 'jenkins-agent'
agent_dir = node['ros_buildfarm']['agent']['windows_agent_dir']
logdir = "#{agent_dir}\\logs"
password_file = "#{agent_dir}\\token"

directory agent_dir do
  recursive true
end

directory logdir

# Download swarm client
swarm_client_version = node['ros_buildfarm']['jenkins']['plugins']['swarm']
swarm_client_url = "https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/#{swarm_client_version}/swarm-client-#{swarm_client_version}.jar"
swarm_client_jarfile_path = "#{agent_dir}\\swarm-client-#{swarm_client_version}.jar"

remote_file swarm_client_jarfile_path do
  source swarm_client_url
  retries 5
end

# WinSW reads its configuration from an XML file sharing the executable's base name.
winsw = node['ros_buildfarm']['agent']['windows_winsw']
winsw_exe = "#{agent_dir}\\#{service_name}.exe"

remote_file winsw_exe do
  source "https://github.com/winsw/winsw/releases/download/v#{winsw['version']}/WinSW-x64.exe"
  checksum winsw['checksum']
  retries 5
end

# Jenkins credentials, same lookup as the Linux agent
jenkins_username = node['ros_buildfarm']['agent']['username']
agent_jenkins_user = search('ros_buildfarm_jenkins_users', "username:#{jenkins_username}").first
raise "No user '#{jenkins_username}' found in the ros_buildfarm_jenkins_users data bag" if agent_jenkins_user.nil?

file password_file do
  content agent_jenkins_user['password']
  sensitive true
  inherits false
  rights :full_control, ['BUILTIN\\Administrators', 'NT AUTHORITY\\SYSTEM']
end

# Absolute path to the JDK installed by windows_agent. Services only see the system
# PATH from boot time, so a bare `java` would miss a JDK installed in the same run
# or pick up another Java already on the machine.
jdk = node['ros_buildfarm']['agent']['windows_jdk'][node['ros_buildfarm']['agent']['jdk_version'].to_s]
java_exe = "#{jdk['install_dir']}\\bin\\java.exe"

template "#{agent_dir}\\#{service_name}.xml" do
  source 'jenkins-agent-windows.xml.erb'
  variables Hash[
    service_name: service_name,
    java_exe: java_exe,
    java_args: node['ros_buildfarm']['agent']['java_args'],
    jarfile: swarm_client_jarfile_path,
    jenkins_url: node['ros_buildfarm']['jenkins_url'],
    username: jenkins_username,
    password_file: password_file,
    name: node['ros_buildfarm']['agent']['nodename'],
    description: node['ros_buildfarm']['agent']['description'],
    executors: node['ros_buildfarm']['agent']['executors'],
    fsroot: node['ros_buildfarm']['agent']['windows_fsroot'],
    labels: node['ros_buildfarm']['agent']['labels'],
    logdir: logdir,
  ]
  notifies :restart, "service[#{service_name}]"
end

execute 'install-jenkins-agent-service' do
  command "\"#{winsw_exe}\" install"
  not_if "sc.exe query #{service_name}"
end

service service_name do
  action [:enable, :start]
  notifies :run, 'powershell_script[remove-old-swarm-clients]', :immediately
end

# Remove swarm client jars left over from previous versions. Runs only after the
# service (re)starts, as Windows cannot delete the jar the running agent holds open.
powershell_script 'remove-old-swarm-clients' do
  code <<-EOH
    Get-ChildItem '#{agent_dir}\\swarm-client-*.jar' |
      Where-Object { $_.FullName -ne '#{swarm_client_jarfile_path}' } |
      Remove-Item -ErrorAction SilentlyContinue
    # A jar that is still locked is retried on the next restart, do not fail the run for it.
    exit 0
  EOH
  action :nothing
end
