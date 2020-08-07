package "reprepro"

package "openssh-server"

host_keys = data_bag_item("ros_buildfarm_host_private_keys", "repo.#{node.chef_environment}")
%w(dsa ecdsa ed25519 rsa).each do |type|
  file "/etc/ssh/ssh_host_#{type}_key" do
    content host_keys[type]["private"]
    mode "0600"
  end
  file "/etc/ssh/ssh_host_#{type}_key.pub" do
    content host_keys[type]["public"]
    mode "0644"
  end
end

# Update attributes to get a "building repository" agent instead of a generic
# "buildagent".
node.default['ros_buildfarm']['agent']['nodename'] = "building_repository"
node.default['ros_buildfarm']['agent']['executors'] = 1
node.default['ros_buildfarm']['agent']['labels'] = ["building_repository"]
include_recipe "ros_buildfarm::agent"

agent_username = node["ros_buildfarm"]["agent"]["agent_username"]

# Create web root and web directories
# TODO: why are these two 644 and the next two 755?
# For now culting it from the puppet config.
%w(/var/repos /var/repos/ubuntu) do |dir|
  directory dir do
    owner agent_username
    group agent_username
    mode "0644"
  end
end

%(docs rosdistro_cache status_page).each do |dir|
  directory "/var/repos/#{dir}" do
    owner agent_username
    group agent_username
    mode "0755"
  end
end
