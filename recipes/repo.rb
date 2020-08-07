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

