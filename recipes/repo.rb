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

# Configure gpg-vault
user 'gpg-vault' do
  manage_home true
  comment 'GPG vault user'
end
execute 'gpg-init' do
  command 'gpg -K'
  environment 'HOME' => '/home/gpg-vault'
  not_if { File.directory? '/home/gpg-vault/.gnupg' }
  user 'gpg-vault'
  group 'gpg-vault'
end
cookbook_file '/home/gpg-vault/.gnupg/gpg-agent.conf' do
  source 'repo/gpg-agent.conf'
  owner 'gpg-vault'
  group 'gpg-vault'
  mode '0600'
end
directory '/var/run/gpg-vault' do
  owner 'gpg-vault'
  group 'gpg-vault'
  mode '0750'
end
cookbook_file '/etc/systemd/system/gpg-vault-agent.service' do
  source 'gpg-vault-agent.service'
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

# Configure GPG for reprepro
# .gnupg/gpg.conf
directory "/home/#{agent_username}/.gnupg" do
  owner agent_username
  group agent_username
  mode '0700'
end
cookbook_file "/home/#{agent_username}/.gnupg/gpg.conf" do
  source 'gpg.conf'
  owner agent_username
  group agent_username
  mode '0600'
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
  execute "/usr/bin/python3 /home/#{agent_username}/reprepro-updater/scripts/setup_repo.py ubuntu_#{repo} -c" do
    environment 'PATH' => '/bin:/usr/bin', 'PYTHONPATH' => "/home/#{agent_username}/reprepro-updater/src", 'HOME' => "/home/#{agent_username}"
    user agent_username
    group agent_username
    not_if "/usr/bin/python3 /home/#{agent_username}/reprepro-updater/scripts/setup_repo.py ubuntu_#{repo} -q"
  end
end

# Pulp setup
pulp_data_directory = '/var/repos/.pulp'
user 'pulp' do
  manage_home true
  comment 'Pulp content manager'
  uid '1200'
end
group 'docker' do
  append true
  members ['pulp']
  action [:manage]
end
directory pulp_data_directory do
  owner 'pulp'
  mode '0700'
end
directory "#{pulp_data_directory}/media" do
  owner 'pulp'
end

cookbook_file "#{pulp_data_directory}/initialize.py" do
  owner 'pulp'
  source 'rpm_repo_init.py'
  mode '0600'
end

package 'redis'
service 'redis' do
  action [:start, :enable]
end
cookbook_file '/etc/redis/redis.conf' do
  source "redis.conf"
  notifies :restart, 'service[redis]', :immediately
end

package 'postgresql'
service 'postgresql' do
  action [:start, :enable]
end
execute "Create pulp postgres user" do
  command %(/usr/bin/psql -c "CREATE USER pulp WITH SUPERUSER LOGIN")
  not_if %(/usr/bin/psql -tc "SELECT 1 from pg_user WHERE usename = 'pulp'" | grep -q 1)
  user 'postgres'
end
execute "Create pulp postgres database" do
  command %(/usr/bin/psql -c "CREATE DATABASE pulp OWNER pulp")
  not_if %(/usr/bin/psql -tc "SELECT 1 FROM pg_database WHERE datname = 'pulp'" | grep -q 1)
  user 'postgres'
end


directory "/usr/local/bin"
remote_file "/usr/local/bin/systemd-docker" do
  source 'https://github.com/subdavis/systemd-docker/releases/download/1.0.0/systemd-docker'
  mode '0755'
end
cookbook_file "#{pulp_data_directory}/Dockerfile" do
  source 'pulp/Dockerfile'
end

if node['ros_buildfarm']['repo']['enable_pulp_services']
  execute 'docker build -t pulp_image .' do
    cwd pulp_data_directory
  end

  execute 'pulp_django_migration' do
    command 'docker run --user 1200:1200 --rm -v /var/run/postgresql:/var/run/postgresql pulp_image pulpcore-manager migrate --noinput'
  end

  execute 'pulp_collect_static' do
    command "docker run --user 1200:1200 --rm -v #{pulp_data_directory}:/var/repos/.pulp pulp_image pulpcore-manager collectstatic --noinput"
  end

  pulp_admin_password = data_bag_item('ros_buildfarm_password_credentials', 'pulp_admin')['password']
  execute 'set_pulp_admin_password' do
    command "docker run --user 1200:1200 --rm -v /var/run/postgresql:/var/run/postgresql pulp_image pulpcore-manager reset-admin-password -p '#{pulp_admin_password}'"
  end

  # TODO * Create gnupg directory for pulp
  execute 'systemctl daemon-reload' do
    action :nothing
  end

  template "/etc/systemd/system/pulp-api-endpoint.service" do
    source "pulp/pulp.service.erb"
    variables Hash[
      description: "Pulp API Endpoint",
      after_units: %w(postgresql.service redis-server.service),
      required_units: %w(postgresql.service redis-server.service),
      docker_create_args: %(-u 1200:1200 -v #{pulp_data_directory}:/var/repos/.pulp -v /var/run/postgresql:/var/run/postgresql -v /var/run/redis:/var/run/redis -p 24817:24817),
      docker_cmd: %(pulpcore-manager runserver 0.0.0.0:24817),
      container: 'pulp-api-endpoint',
    ]
    notifies :run, 'execute[systemctl daemon-reload]', :immediately
    notifies :restart, 'service[pulp-api-endpoint]'
  end
  service 'pulp-api-endpoint' do
    action [:start, :enable]
  end

  template "/etc/systemd/system/pulp-content-endpoint.service" do
    source "pulp/pulp.service.erb"
    variables Hash[
      description: "Pulp Content Endpoint",
      after_units: %w(postgresql.service redis-server.service),
      required_units: %w(postgresql.service redis-server.service),
      docker_create_args: %(-u 1200:1200 -v #{pulp_data_directory}:/var/repos/.pulp -v /var/run/postgresql:/var/run/postgresql -v /var/run/redis:/var/run/redis -p 24816:24816),
      docker_cmd: 'pulp-content',
    ]
    notifies :run, 'execute[systemctl daemon-reload]', :immediately
    notifies :restart, 'service[pulp-content-endpoint]'
  end
  service 'pulp-content-endpoint' do
    action [:start, :enable]
  end

  template "/etc/systemd/system/pulp-resource-manager.service" do
    source "pulp/pulp.service.erb"
    variables Hash[
      description: "Pulp Resource Manager",
      after_units: %w(postgresql.service redis-server.service),
      required_units: %w(postgresql.service redis-server.service),
      docker_create_args: %(-u 1200:1200 -v #{pulp_data_directory}:/var/repos/.pulp -v /var/run/postgresql:/var/run/postgresql -v /var/run/redis:/var/run/redis),
      docker_cmd: %(rq worker -n resource-manager -w pulpcore.tasking.worker.PulpWorker -c pulpcore.rqconfig),
    ]
    notifies :run, 'execute[systemctl daemon-reload]', :immediately
    notifies :restart, 'service[pulp-resource-manager]'
  end
  service 'pulp-resource-manager' do
    action [:start, :enable]
  end

  template "/etc/systemd/system/pulp-worker@.service" do
    source "pulp/pulp.service.erb"
    variables Hash[
      description: "Pulp Worker",
      after_units: %w(postgresql.service redis-server.service),
      required_units: %w(postgresql.service redis-server.service),
      docker_create_args: %(-u 1200:1200 -v #{pulp_data_directory}:/var/repos/.pulp -v /var/run/postgresql:/var/run/postgresql -v /var/run/redis:/var/run/redis),
      docker_cmd: %(rq worker -n pulp-worker-%i -w pulpcore.tasking.worker.PulpWorker -c pulpcore.rqconfig),
    ]
    notifies :run, 'execute[systemctl daemon-reload]', :immediately

    0.upto(node['ros_buildfarm']['repo']['pulp_worker_count'] - 1) do |i|
      notifies :restart, "service[pulp-worker@#{i}]"
    end
  end
  0.upto(node['ros_buildfarm']['repo']['pulp_worker_count'] - 1) do |i|
    service "pulp-worker@#{i}" do
      action [:start, :enable]
    end
  end

  # * Create rpm repos
  node['ros_buildfarm']['rpm_repos'].each do |dist, versions|
    versions.each do |version, architectures|
      repo_name = "#{dist}-#{version}"
      execute "Create #{repo_name}-SRPMS" do
        command %W[
          python3
          #{pulp_data_directory}/initialize.py
          #{repo_name}-SRPMS
          ros-building-#{repo_name}-SRPMS
          ros-testing-#{repo_name}-SRPMS
          ros-main-#{repo_name}-SRPMS
        ]
        environment Hash[
          "PULP_BASE_URL" => "http://127.0.0.1:24817",
          "PULP_USERNAME" => "admin",
          "PULP_PASSWORD" => pulp_admin_password,
        ]
      end

      architectures.each do |arch|
        execute "Create #{repo_name}-#{arch}" do
          command %W[
            python3
            #{pulp_data_directory}/initialize.py
            #{repo_name}-#{arch}
            ros-building-#{repo_name}-#{arch}
            ros-testing-#{repo_name}-#{arch}
            ros-main-#{repo_name}-#{arch}
          ]
          environment Hash[
            "PULP_BASE_URL" => "http://127.0.0.1:24817",
            "PULP_USERNAME" => "admin",
            "PULP_PASSWORD" => pulp_admin_password,
          ]
        end
        execute "Create #{repo_name}-#{arch}-debug" do
          command %W[
            python3
            #{pulp_data_directory}/initialize.py
            #{repo_name}-#{arch}
            ros-building-#{repo_name}-#{arch}-debug
            ros-testing-#{repo_name}-#{arch}-debug
            ros-main-#{repo_name}-#{arch}-debug
          ]
          environment Hash[
            "PULP_BASE_URL" => "http://127.0.0.1:24817",
            "PULP_USERNAME" => "admin",
            "PULP_PASSWORD" => pulp_admin_password,
          ]
        end
      end
    end
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
