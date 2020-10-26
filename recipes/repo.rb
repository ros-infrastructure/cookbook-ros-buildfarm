# Update packages before starting cookbook run.
apt_update

package 'reprepro'

package 'openssh-server'

host_keys = data_bag_item('ros_buildfarm_host_keys', 'repo')[node.chef_environment]
%w(dsa ecdsa ed25519 rsa).each do |type|
  file "/etc/ssh/ssh_host_#{type}_key" do
    content host_keys[type]['private']
    mode '0600'
  end
  file "/etc/ssh/ssh_host_#{type}_key.pub" do
    content host_keys[type]['public']
    mode '0644'
  end
end

# Update attributes to get a "building repository" agent instead of a generic
# "buildagent".
node.default['ros_buildfarm']['agent']['nodename'] = 'building_repository'
node.default['ros_buildfarm']['agent']['executors'] = 1
node.default['ros_buildfarm']['agent']['labels'] = ['building_repository']
include_recipe 'ros_buildfarm::agent'

agent_username = node['ros_buildfarm']['agent']['agent_username']

# Create web root and web directories
%w(/var/repos /var/repos/ubuntu).each do |dir|
  directory dir do
    owner agent_username
    group agent_username
    mode '0755'
  end
end

%w(docs rosdistro_cache status_page).each do |dir|
  directory "/var/repos/#{dir}" do
    owner agent_username
    group agent_username
    mode '0755'
  end
end

package 'python3-yaml'
package 'python3-debian'

# upload scripts and keys
directory "/home/#{agent_username}/upload_triggers" do
  owner agent_username
  group agent_username
end
# TODO: at some point this file will need to be templatized and only installed if needed.
cookbook_file "/home/#{agent_username}/upload_repo.bash" do
  source 'upload_repo.bash'
  owner agent_username
  group agent_username
  mode '0700'
end
data_bag('ros_buildfarm_upload_keys').each do |id|
  key = data_bag_item('ros_buildfarm_upload_keys', id)
  file "/home/#{agent_username}/upload_triggers/#{key['name']}" do
    content key['content']
    owner agent_username
    group agent_username
    mode '0600'
  end
end

# Configure GPG for reprepro
# .gnupg/gpg.conf
directory "/home/#{agent_username}/.gnupg" do
  owner agent_username
  group agent_username
end
cookbook_file "/home/#{agent_username}/.gnupg/gpg.conf" do
  source 'gpg.conf'
  owner agent_username
  group agent_username
end

gpg_key = data_bag_item('ros_buildfarm_repository_signing_keys', node.chef_environment)
directory "/home/#{agent_username}/.ssh" do
  owner agent_username
  group agent_username
end
file "/home/#{agent_username}/.ssh/gpg_private_key.sec" do
  owner agent_username
  group agent_username
  mode '0600'
  content gpg_key['private_key']
end
file "/home/#{agent_username}/.ssh/gpg_public_key.pub" do
  owner agent_username
  group agent_username
  mode '0644'
  content gpg_key['public_key']
end
file '/var/repos/repos.key' do
  owner agent_username
  group agent_username
  mode '0644'
  content gpg_key['public_key']
end

# Import public and private keys.
execute "gpg --import /home/#{agent_username}/.ssh/gpg_public_key.pub" do
  user agent_username
  group agent_username
  environment 'PATH' => '/bin:/usr/bin', 'HOME' => "/home/#{agent_username}"
  not_if "gpg --list-keys | grep #{gpg_key['fingerprint']}"
end
execute "gpg --import /home/#{agent_username}/.ssh/gpg_private_key.sec" do
  user agent_username
  group agent_username
  environment 'PATH' => '/bin:/usr/bin', 'HOME' => "/home/#{agent_username}"
  not_if "gpg --list-secret-keys | grep #{gpg_key['fingerprint']}"
end

# Set up reprepro and reprepro config for deb repositories
directory "/home/#{agent_username}/.buildfarm" do
  owner agent_username
  group agent_username
end
template "/home/#{agent_username}/.buildfarm/reprepro-updater.ini" do
  source 'reprepro-updater.ini.erb'
  owner agent_username
  group agent_username
  mode '0600'
  variables Hash[
    architectures: node['ros_buildfarm']['apt_repos']['architectures'],
    signing_key: gpg_key['fingerprint'],
    suites: node['ros_buildfarm']['apt_repos']['suites'],
  ]
end

git "/home/#{agent_username}/reprepro-updater" do
  repository 'https://github.com/ros-infrastructure/reprepro-updater'
  revision 'refactor'
  user agent_username
  group agent_username
end

directory "/home/#{agent_username}/reprepro_config" do
  owner agent_username
  group agent_username
end
template "/home/#{agent_username}/reprepro_config/ros_bootstrap.yaml" do
  source 'ros_bootstrap.yaml.erb'
  owner agent_username
  group agent_username
  variables Hash[
    architectures: node['ros_buildfarm']['apt_repos']['architectures'],
    component: node['ros_buildfarm']['apt_repos']['component'],
    repository_url: node['ros_buildfarm']['apt_repos']['bootstrap_url'],
    suites: node['ros_buildfarm']['apt_repos']['suites'],
  ]
end

# Initialise repositories with reprepro
%w(building testing main).each do |repo|
  execute "/usr/bin/python3 /home/#{agent_username}/reprepro-updater/scripts/setup_repo.py ubuntu_#{repo} -c" do
    environment 'PATH' => '/bin:/usr/bin', 'PYTHONPATH' => "/home/#{agent_username}/reprepro-updater/src", 'HOME' => "/home/#{agent_username}"
    user agent_username
    group agent_username
    not_if "/usr/bin/python3 /home/#{agent_username}/reprepro-updater/scripts/setup_repo.py ubunut_#{repo} -q"
  end
end

package 'nginx'
cookbook_file '/etc/nginx/sites-available/repo' do
  source 'nginx/repo.conf'
  notifies :restart, 'service[nginx]'
end
link '/etc/nginx/sites-enabled/default' do
  action :delete
  notifies :restart, 'service[nginx]'
end
link '/etc/nginx/sites-enabled/repo' do
  to '/etc/nginx/sites-available/repo'
  notifies :restart, 'service[nginx]'
end
service 'nginx' do
  action [:start, :enable]
end
