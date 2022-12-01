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

%w(ci_archives docs rosdistro_cache status_page).each do |dir|
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
cookbook_file "/home/#{agent_username}/upload_triggers/upload_repo.bash" do
  source 'upload_repo.bash'
  owner agent_username
  group agent_username
  mode '0700'
end
data_bag('ros_buildfarm_upload_keys').each do |id|
  key = data_bag_item('ros_buildfarm_upload_keys', id)[node.chef_environment]
  file "/home/#{agent_username}/upload_triggers/#{key['name']}" do
    content key['content']
    owner agent_username
    group agent_username
    mode '0600'
  end
  if key['symlink']
    link "/home/#{agent_username}/upload_triggers/#{key['symlink']}" do
      to "/home/#{agent_username}/upload_triggers/#{key['name']}"
    end
  end
end

execute 'systemctl daemon-reload' do
  action :nothing
end

# Configure gpg-vault
user 'gpg-vault' do
  manage_home true
  system true
  shell '/usr/sbin/nologin'
  comment 'GPG vault user'
end
execute 'gpg-init' do
  command 'gpg -K'
  environment 'HOME' => '/home/gpg-vault'
  user 'gpg-vault'
  group 'gpg-vault'
  creates '/home/gpg-vault/.gnupg'
end
cookbook_file '/home/gpg-vault/.gnupg/gpg.conf' do
  source 'gpg-vault.conf'
  owner 'gpg-vault'
  group 'gpg-vault'
  mode '0600'
end
cookbook_file '/home/gpg-vault/.gnupg/gpg-agent.conf' do
  source 'repo/gpg-agent.conf'
  owner 'gpg-vault'
  group 'gpg-vault'
  mode '0600'
end
cookbook_file '/etc/systemd/system/gpg-vault-agent.service' do
  source 'gpg-vault-agent.service'
  notifies :run, 'execute[systemctl daemon-reload]', :immediately
end
systemd_unit 'gpg-vault-agent.service' do
  triggers_reload true
  action [:start, :enable]
end
gpg_key = data_bag_item('ros_buildfarm_repository_signing_keys', node.chef_environment)
file '/home/gpg-vault/.gnupg/gpg_public_key.pub' do
  content gpg_key['public_key']
  owner 'gpg-vault'
  group 'gpg-vault'
  mode '0644'
end
execute 'gpg --import /home/gpg-vault/.gnupg/gpg_public_key.pub' do
  environment 'HOME' => '/home/gpg-vault'
  user 'gpg-vault'
  group 'gpg-vault'
  not_if "gpg --list-keys #{gpg_key['fingerprint']}"
end
file '/home/gpg-vault/.gnupg/gpg_private_key.sec' do
  content gpg_key['private_key']
  owner 'gpg-vault'
  group 'gpg-vault'
  mode '0600'
end
execute 'gpg --import /home/gpg-vault/.gnupg/gpg_private_key.sec' do
  environment 'HOME' => '/home/gpg-vault'
  user 'gpg-vault'
  group 'gpg-vault'
  not_if "gpg --list-secret-keys #{gpg_key['fingerprint']}"
end
group 'gpg-vault' do
  append true
  members [agent_username]
  action [:manage]
end

# Remove previous GPG deployment
execute "gpgconf --kill gpg-agent" do
  user agent_username
  group agent_username
  environment 'HOME' => "/home/#{agent_username}"
  only_if "gpg-agent"
end
file "/home/#{agent_username}/.ssh/gpg_public_key.pub" do
  action :delete
end

# Configure GPG for reprepro
# .gnupg/gpg.conf
execute 'gpg-init' do
  command 'gpg -K'
  environment 'HOME' => "/home/#{agent_username}"
  user agent_username
  group agent_username
  creates "/home/#{agent_username}/.gnupg"
end
cookbook_file "/home/#{agent_username}/.gnupg/gpg.conf" do
  source 'gpg.conf'
  owner agent_username
  group agent_username
  mode '0600'
end
link "/home/#{agent_username}/.gnupg/S.gpg-agent" do
  action :delete
  only_if { ::File.symlink?("/home/#{agent_username}/.gnupg/S.gpg-agent") }
end

# Set up ssh authorized keys for publish over ssh.
directory "/home/#{agent_username}/.ssh" do
  owner agent_username
  group agent_username
  mode '0700'
end
ssh_key = data_bag_item('ros_buildfarm_publish_over_ssh_key', node.chef_environment)
file "/home/#{agent_username}/.ssh/authorized_keys" do
  content ssh_key['public_key']
  owner agent_username
  group agent_username
  mode '0600'
end

file "/home/#{agent_username}/.ssh/gpg_private_key.sec" do
  owner agent_username
  group agent_username
  mode '0600'
  content gpg_key['private_key']
end
file '/var/repos/repos.key' do
  owner agent_username
  group agent_username
  mode '0644'
  content gpg_key['public_key']
end

# Import public and private keys.
execute "gpg --import /var/repos/repos.key" do
  user agent_username
  group agent_username
  environment 'PATH' => '/bin:/usr/bin', 'HOME' => "/home/#{agent_username}"
  not_if "gpg --list-keys #{gpg_key['fingerprint']}"
end
execute "gpg --import /home/#{agent_username}/.ssh/gpg_private_key.sec" do
  user agent_username
  group agent_username
  environment 'PATH' => '/bin:/usr/bin', 'HOME' => "/home/#{agent_username}"
  not_if "gpg --list-secret-keys #{gpg_key['fingerprint']}"
end

# Import ROS bootstrap signing key for signature verification
cookbook_file "/home/#{agent_username}/.ssh/ros_bootstrap.pub.asc" do
  owner agent_username
  group agent_username
  mode '0644'
end

# Setting the id blindtrust will disable signature checking for the bootstrap repository.
unless node['ros_buildfarm']['apt_repos']['bootstrap_signing_key_id'] == 'blindtrust'
  execute "gpg --import /home/#{agent_username}/.ssh/ros_bootstrap.pub.asc" do
    user agent_username
    group agent_username
    environment 'PATH' => '/bin:/usr/bin', 'HOME' => "/home/#{agent_username}"
    not_if "gpg --list-keys #{node['ros_buildfarm']['apt_repos']['bootstrap_signing_key_id']}"
  end
end


# Set up reprepro and reprepro config for deb repositories
git "/home/#{agent_username}/reprepro-updater" do
  repository 'https://github.com/ros-infrastructure/reprepro-updater'
  revision 'refactor'
  action :sync # always pull the latest revision.
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
    verify_release: node['ros_buildfarm']['apt_repos']['bootstrap_signing_key_id'],
  ]
end
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
    upstream_config: "/home/#{agent_username}/reprepro_config"
  ]
end

# Initialise repositories with reprepro
%w(building testing main).each do |repo|
  group_execute "/usr/bin/python3 /home/#{agent_username}/reprepro-updater/scripts/setup_repo.py ubuntu_#{repo} -c" do
    environment 'PATH' => '/bin:/usr/bin', 'PYTHONPATH' => "/home/#{agent_username}/reprepro-updater/src", 'HOME' => "/home/#{agent_username}"
    user agent_username
    group agent_username
    secondary_groups ['gpg-vault']
    not_if "/usr/bin/python3 /home/#{agent_username}/reprepro-updater/scripts/setup_repo.py ubuntu_#{repo} -q"
  end
end

# RPM repository setup
apt_repository 'createrepo-agent-ppa' do
  uri 'ppa:osrf/createrepo-agent'
end

%w[createrepo-agent createrepo-c rpm socat].each do |pkg|
  package pkg
end

node['ros_buildfarm']['rpm_repos'].each do |dist, versions|
  dist_dir = "/var/repos/#{dist}"

  %w(building testing main).each do |repo|
    repo_dir = "#{dist_dir}/#{repo}"

    versions.each do |version, architectures|
      version_dir = "#{repo_dir}/#{version}"
      srpms_dir = "#{version_dir}/SRPMS"
      [dist_dir, repo_dir, version_dir, srpms_dir].each do |dir|
        directory dir do
          owner agent_username
          group agent_username
          mode '0755'
        end
      end

      execute "createrepo_c --no-database #{srpms_dir}" do
        user agent_username
        group agent_username
        not_if { ::File.exist?("#{srpms_dir}/repodata/repomd.xml") }
      end

      execute "gpg --armor --detach --sign --yes --default-key=#{gpg_key['fingerprint']} #{srpms_dir}/repodata/repomd.xml" do
        user agent_username
        group agent_username
        environment 'HOME' => "/home/#{agent_username}"
        not_if { ::File.exist?("#{srpms_dir}/repodata/repomd.xml.asc") }
      end

      architectures.each do |arch|
        arch_dir = "#{version_dir}/#{arch}"
        debug_dir = "#{arch_dir}/debug"
        [arch_dir, debug_dir].each do |dir|
          directory dir do
            owner agent_username
            group agent_username
            mode '0755'
          end
        end

        execute "createrepo_c --no-database #{arch_dir} --excludes=debug/*" do
          user agent_username
          group agent_username
          not_if { ::File.exist?("#{arch_dir}/repodata/repomd.xml") }
        end

        execute "gpg --armor --detach --sign --yes --default-key=#{gpg_key['fingerprint']} #{arch_dir}/repodata/repomd.xml" do
          user agent_username
          group agent_username
          environment 'HOME' => "/home/#{agent_username}"
          not_if { ::File.exist?("#{arch_dir}/repodata/repomd.xml.asc") }
        end

        execute "createrepo_c --no-database #{debug_dir}" do
          user agent_username
          group agent_username
          not_if { ::File.exist?("#{debug_dir}/repodata/repomd.xml") }
        end

        execute "gpg --armor --detach --sign --yes --default-key=#{gpg_key['fingerprint']} #{debug_dir}/repodata/repomd.xml" do
          user agent_username
          group agent_username
          environment 'HOME' => "/home/#{agent_username}"
          not_if { ::File.exist?("#{debug_dir}/repodata/repomd.xml.asc") }
        end
      end
    end
  end
end

if not node['ros_buildfarm']['rpm_bootstrap_urls'].empty?
  file "/home/#{agent_username}/ros_bootstrap_rpm_urls.txt" do
    owner agent_username
    group agent_username
    mode '0644'
    content node['ros_buildfarm']['rpm_bootstrap_urls'].join("\n")
  end
end


package 'nginx'
service 'nginx' do
  action [:start, :enable]
end


server_name = node['ros_buildfarm']['repo']['server_name']
cert_path = if server_name
              "/etc/ssl/certs/#{server_name}/fullchain.pem"
            else
              nil
            end
key_path = if server_name
             "/etc/ssl/private/#{server_name}.key"
           else
             nil
           end

# Initial configuration of SSL certs for HTTPS
if node['ros_buildfarm']['letsencrypt_enabled']
  if server_name.nil?
    Chef::Log.fatal "No repo server name set for #{node.chef_environment} but it is required when using letsencrypt."
    Chef::Log.fatal "Define the node['ros_buildfarm']['repo']['server_name'] attribute or set node['ros_buildfarm']['letsencrypt_enabled'] = false"
    raise
  end

  # Bootstrap https with self-signed certificates
  package 'ssl-cert'
  directory "/etc/ssl/certs/#{server_name}"

  execute "cp /etc/ssl/certs/ssl-cert-snakeoil.pem #{cert_path}" do
    not_if { ::File.readable? cert_path }
  end
  execute "cp /etc/ssl/private/ssl-cert-snakeoil.key #{key_path}" do
    not_if { ::File.readable? key_path }
  end
end

template '/etc/nginx/sites-available/repo' do
  source 'nginx/repo.conf.erb'
  variables Hash[
    letsencrypt_enabled: node['ros_buildfarm']['letsencrypt_enabled'],
    cert_path: cert_path,
    key_path: key_path,
    rpm_repos: node['ros_buildfarm']['rpm_repos'],
    server_name: server_name,
  ]
  notifies :restart, 'service[nginx]', :immediately
end
link '/etc/nginx/sites-enabled/default' do
  action :delete
  notifies :restart, 'service[nginx]'
end
link '/etc/nginx/sites-enabled/repo' do
  to '/etc/nginx/sites-available/repo'
  notifies :restart, 'service[nginx]'
end
template '/etc/nginx/sites-available/repo' do
  source 'nginx/repo.conf.erb'
  variables Hash[
    letsencrypt_enabled: node['ros_buildfarm']['letsencrypt_enabled'],
    cert_path: cert_path,
    key_path: key_path,
    rpm_repos: node['ros_buildfarm']['rpm_repos'],
    server_name: server_name,
  ]
  notifies :restart, 'service[nginx]', :immediately
end

# Continue with HTTPS certificate configuration now that nginx is configured.
if node['ros_buildfarm']['letsencrypt_enabled']
  include_recipe "ros_buildfarm::acmesh"

  # Create Let's Encrypt signed cert if it has not already been done.
  execute 'acme-issue-cert' do
    environment 'HOME' => '/root'
    command %W(
      /root/.acme.sh/acme.sh --issue
      --webroot /var/www/html
      --domain #{server_name}
      --fullchain-file #{cert_path}
      --key-file #{key_path}
      --reloadcmd /root/cert-update-hook.sh
      --server letsencrypt
      --force
    )
    not_if { ::File.directory? "/root/.acme.sh/#{server_name}" }
  end
end

# Configure rsync endpoints for repositories
if not node['ros_buildfarm']['repo']['rsyncd_endpoints'].empty?
  package 'rsync'
  template '/etc/rsyncd.conf' do
    source 'rsyncd.conf.erb'
    variables Hash[
      rsyncd_endpoints: node['ros_buildfarm']['repo']['rsyncd_endpoints']
    ]
    notifies :restart, 'service[rsync]'
  end
  service 'rsync' do
    action [:start, :enable]
  end
end

# Configure read-through container registry cache
if node['ros_buildfarm']['repo']['container_registry_cache_enabled']
  package 'docker-registry'
  cookbook_file '/etc/docker/registry/config.yml' do
    source 'docker-registry-config.yml'
    notifies :restart, 'service[docker-registry]'
  end
  service 'docker-registry' do
    action [:start, :enable]
  end
end
