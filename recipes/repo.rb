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


