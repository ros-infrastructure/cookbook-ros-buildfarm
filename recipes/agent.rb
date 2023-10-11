apt_update
package 'docker.io'

# Create a directory for the apt-daily-upgrade.timer.d override (doesn't exist by default)
directory '/etc/systemd/system/apt-daily-upgrade.timer.d' do
  recursive true
end

# Moves the unattended daily upgrades to 1am
cookbook_file '/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf' do
  source 'apt-daily-upgrade.timer.override'
  notifies :reload_or_try_restart, 'systemd_unit[apt-daily-upgrade.timer]', :delayed
end

systemd_unit 'apt-daily-upgrade.timer' do
  action :nothing
end

template '/etc/apt/apt.conf.d/50unattended-upgrades' do
  source '50unattended-upgrades.erb'
  variables(
    blacklist: node['ros_buildfarm']['unattended_upgrades']['package_blacklist']
  )

end

# Add a containerd service override to work around
# https://bugs.launchpad.net/ubuntu/+source/unattended-upgrades/+bug/1870876?comments=all
directory '/etc/systemd/system/containerd.service.d' do
  mode "0755"
end
file '/etc/systemd/system/containerd.service.d/override.conf' do
  content <<~EOF
    [Unit]
    Before=docker.service
    Wants=docker.service
  EOF
  mode '0644'
  notifies :run, 'execute[systemctl-daemon-reload]', :immediately
  notifies :restart, 'service[containerd]'
end
directory '/etc/containerd'
file '/etc/containerd/config.toml' do
  content 'disabled_plugins = ["cri"]'
  notifies :restart, 'service[containerd]'
end
directory '/etc/docker/seccomp'
cookbook_file '/etc/docker/seccomp/default-with-personality.json' do
  source 'docker-seccomp-default-with-personality.json'
end
template '/etc/docker/daemon.json' do
  source 'docker-daemon.json.erb'
  variables Hash[
    registry_mirrors: node['docker']['registry_mirrors']
  ]
  notifies :restart, 'service[docker]'
end
service 'containerd' do
  action :nothing
end
service 'docker' do
  action [:start, :enable]
end

cookbook_file '/root/docker-disk-cleanup.sh' do
  mode '0755'
end

cron 'docker_disk_cleanup' do
  time :hourly
  command "/root/docker-disk-cleanup.sh"
end

agent_username = node['ros_buildfarm']['agent']['agent_username']
agent_homedir = "/home/#{agent_username}"

user agent_username do
  manage_home true
  comment 'Jenkins Agent User'
end

# Add agent user to the docker group to allow them to build and run docker
# containers.
group 'docker' do
  append true
  members [agent_username]
  action :manage # Group should be created by docker package.
end

data_bag('ros_buildfarm_ssh_known_hosts').each do |id|
  hostkey_info = data_bag_item('ros_buildfarm_ssh_known_hosts', id)[node.chef_environment]
  ssh_known_hosts_entry hostkey_info['host'] do
    key hostkey_info['key']
    key_type hostkey_info['key_type']
  end
end

package 'openjdk-8-jdk-headless'

swarm_client_version = node['ros_buildfarm']['jenkins']['plugins']['swarm']
swarm_client_url = "https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/#{swarm_client_version}/swarm-client-#{swarm_client_version}.jar"
swarm_client_jarfile_path = "/home/#{agent_username}/swarm-client-#{swarm_client_version}.jar"

# Download swarm client program from url and install it to the jenkins-agent user's home directory.
remote_file swarm_client_jarfile_path do
  source swarm_client_url
  owner agent_username
  group agent_username
  mode '0444'
end

package 'python3-empy'

directory "/home/#{agent_username}/.ccache" do
  group agent_username
  owner agent_username
end

# Install version control utilities
%w[bzr git mercurial subversion].each do |vcspkg|
  package vcspkg
end

# Client utilities for pulp content manager
package "python3-pip"
%w[pulp-rpm-client==3.9.0 pulpcore-client==3.9.1].each do |pulppkg|
  execute "python3 -m pip install #{pulppkg}"
end

# TODO install this only on amd64?
package 'qemu-user-static'

jenkins_username = node['ros_buildfarm']['agent']['username']
agent_jenkins_user = search('ros_buildfarm_jenkins_users', "username:#{jenkins_username}").first
template '/etc/default/jenkins-agent' do
  source 'jenkins-agent.env.erb'
  variables Hash[
    java_args: node['ros_buildfarm']['agent']['java_args'],
    jarfile: swarm_client_jarfile_path,
    jenkins_url: node['ros_buildfarm']['jenkins_url'],
    username: jenkins_username,
    name: node['ros_buildfarm']['agent']['nodename'],
    description: node['ros_buildfarm']['agent']['description'],
    executors: node['ros_buildfarm']['agent']['executors'],
    user_home: agent_homedir,
    labels: node['ros_buildfarm']['agent']['labels'],
  ]
  notifies :restart, 'service[jenkins-agent]'
end
directory '/etc/jenkins-agent'
file '/etc/jenkins-agent/token' do
  content agent_jenkins_user['password']
  mode '0640'
  owner 'root'
  group agent_username
end

template '/etc/systemd/system/jenkins-agent.service' do
  source 'jenkins-agent.service.erb'
  variables Hash[
    service_name: 'jenkins-agent',
    username: agent_username,
  ]
  notifies :run, 'execute[systemctl-daemon-reload]', :immediately
  notifies :restart, 'service[jenkins-agent]'
end

execute 'systemctl-daemon-reload' do
  command 'systemctl daemon-reload'
  action :nothing
end

service 'jenkins-agent' do
  action [:start, :enable]
end
