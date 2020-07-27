package 'docker.io'

agent_username = node['ros_buildfarm']['agent']['agent_username']

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

data_bag('ros_buildfarm_host_keys').each do |hostkey|
  hostkey_info = data_bag_item('ros_buildfarm_host_keys', hostkey)
  ssh_known_hosts_entry hostkey_info['host'] do
    key hostkey_info['key']
    key_type hostkey_info['key_type']
  end
end

package 'openjdk-8-jdk-headless'

swarm_client_version = node['ros_buildfarm']['jenkins']['plugins']['swarm']
swarm_client_url = "https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/#{swarm_client_version}/swarm-client-#{swarm_client_version}.jar"

# Download swarm client program from url and install it to the jenkins-agent user's home directory.
remote_file "/home/#{agent_username}/swarm-client-#{swarm_client_version}.jar" do
  source swarm_client_url
  owner agent_username
  group agent_username
  mode '0444'
end

package 'python-empy'

directory "/home/#{agent_username}/.ccache" do
  group agent_username
  owner agent_username
end

# Install version control utilities
%w[bzr git mercurial subversion].each do |vcspkg|
  package vcspkg
end

# TODO install this only on amd64?
package 'qemu-user-static'
