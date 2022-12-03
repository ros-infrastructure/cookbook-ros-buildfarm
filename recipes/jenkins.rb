## Jenkins Server ##


# Normalize attribute hierarchy
# Some attributes were inconsistently nested in the ros_buildfarm cookbook.
# The default and expected attributes have been changed but in order
# to remain compatible with existing configurations a warning is being added
# if the old attributes are set and differ from the new ones.
%w(admin_email server_name).each do |attr|
  if node['ros_buildfarm'][attr] # the old attribute is defined
    if node['ros_buildfarm']['jenkins'][attr].nil?
      Chef::Log.warn(
        "The attribute `node['ros_buildfarm']['#{attr}']` is now `node['ros_buildfarm']['jenkins']['#{attr}']`. " +
        "Support for the previous attribute may be removed in a future release of this cookbook. " +
        "Replacing the `node['ros_buildfarm']['#{attr}']` attribute with `node['ros_buildfarm']['jenkins']['#{attr}']` is recommended."
      )
      node.default['ros_buildfarm']['jenkins'][attr] = node['ros_buildfarm'][attr]
    elsif node['ros_buildfarm']['jenkins'][attr] != node['ros_buildfarm'][attr]
      Chef::Log.warn(
        "The attribute `node['ros_buildfarm']['#{attr}']` is now `node['ros_buildfarm']['jenkins']['#{attr}']`. " +
        "Support for the previous attribute may be removed in a future release of this cookbook. " +
        "Removing the `node['ros_buildfarm']['#{attr}']` attribute is recommended."
      )
      node.default['ros_buildfarm'][attr] = node['ros_buildfarm']['jenkins'][attr]
    end
  end
end

# Run an apt update if one hasn't been run in 24 hours (the default frequency).
# Without this the recipe fails on AWS instances with empty apt caches.
apt_update

package 'openjdk-8-jdk-headless'
# Jenkins downgrade protection
#
# The Jenkins package has transitioned to using systemd units instead of
# sysvinit style init scripts. In order to maintain this cookbook the last
# version of Jenkins which is packaged with a sysvinit script is pinned.
# However Jenkins cannot be safely downgraded and some configurations of
# Jenkins will continue to function once initially configured even after the
# systemd switch.
# To protect users from unintentional downgrades we're going to do something really ugly here.
package 'jenkins' do
  action :lock
  only_if { -> do
    jenkins_info = `dpkg -s jenkins`
    if $?.exitstatus != 0
       return false
    end

    version_line = jenkins_info.lines.select{|line| line =~ /^Version: /}.first
    if version_line.nil?
      return false
    end

    # Transform "Version: 2.319.1\n" to ["2", "319", "1"]
    version_components = version_line.chomp.split(": ")[1].split(".")
    # The first systemd versions are 2.335 (weekly) and 2.332.1 (LTS)
    if version_components[0].to_i > 2 or version_components[1].to_i >= 332
      node.run_state[:jenkins_package_version_lock] = version_components.join('.')
      Chef::Log.warn("Chef detected this Jenkins version: #{node.run_state[:jenkins_package_version_lock]}")
      return true
    end
    # Jenkins is installed but is older than the maximum and can be upgraded.
    return false
  end.call }
end

ruby_block 'prevent jenkins downgrade' do
  block do
    if node.run_state[:jenkins_package_version_lock]
      if node['jenkins']['master']['version'] != node.run_state[:jenkins_package_version_lock]
        Chef::Log.fatal("Before this cookbook continues. please set the node['jenkins']['master']['version'] attribute to #{node.run_state[:jenkins_package_version_lock]} or this cookbook will attempt to downgrade your Jenkins version.")
        Chef::Log.fatal("See https://github.com/ros-infrastructure/cookbook-ros-buildfarm/issues/121 for more information")
        raise
      end
    end
  end
end

include_recipe 'jenkins::master'

# Set up authentication
chef_user = search('ros_buildfarm_jenkins_users', 'chef_user:true').first
node.run_state[:jenkins_username] = chef_user['username']
node.run_state[:jenkins_password] = chef_user['password']
node.default['jenkins']['executor']['protocol'] = 'http'

# Remove plugins that were required previously but are not now.
node['ros_buildfarm']['jenkins']['remove_plugins'].each do |plugin|
  jenkins_plugin plugin do
    action :uninstall
    notifies :restart, 'service[jenkins]', :delayed
  end
end
# Install bundled publish-over-ssh plugin which was delisted from the Jenkins plugin server
cookbook_file '/tmp/publish-over-ssh.hpi' do
  source 'publish-over-ssh.hpi'
  owner 'jenkins'
  mode '0600'
end
jenkins_plugin 'publish-over-ssh' do
  source 'file:///tmp/publish-over-ssh.hpi'
end
# Install plugins required to run ros_buildfarm.
node['ros_buildfarm']['jenkins']['plugins'].each do |plugin, ver|
  jenkins_plugin plugin do
    version ver
    install_deps false
    notifies :restart, 'service[jenkins]', :delayed
  end
end

## Jenkins configuration
# Most of our Jenkins configuration has been consolidated into this one yaml
# file thanks to the Jenkins configuration-as-code plugin which provides a
# stable interface to Jenkins' internal describable and data binding APIs.
# This decreases the configuration file drift based on plugin version artifacts
# and consolidates everything in to the single file.
template '/var/lib/jenkins/jenkins.yaml' do
  source 'jenkins/jenkins.yaml.erb'
  owner node['jenkins']['master']['user']
  group node['jenkins']['master']['group']
  variables Hash[
    scheme: if node['ros_buildfarm']['letsencrypt_enabled'] then 'https' else 'http' end,
    server_name: node['ros_buildfarm']['jenkins']['server_name'],
    admin_email: node['ros_buildfarm']['jenkins']['admin_email'],
  ]
  notifies :restart, 'service[jenkins]', :immediately
end

## Configuration for the publish-over-ssh plugin.
# TODO: (nuclearsandwich) This is going to require re-organization to suite an all-in-one setup as
# the agent username attribute for the repo host specifically will change.
node.default['ros_buildfarm']['ssh_publisher']['repo_username'] = node['ros_buildfarm']['agent']['agent_username']
# By default we rely expect the repo host to be used for each of the other duties with different remote root directories.
# This bit of Ruby metaprogramming here makes me nervous in a chef recipe.
# I am doing it anyway because I can't bring myself to copy the logic.
# In the long term I expect that this entire configuration may need to be re-thought but for now we're porting it more or less directly from the existing buildfarm_deployment.
%w(hostname username port timeout).each do |attr|
  unless node['ros_buildfarm']['ssh_publisher']["docs_#{attr}"]
    node.default['ros_buildfarm']['ssh_publisher']["docs_#{attr}"] = node['ros_buildfarm']['ssh_publisher']["repo_#{attr}"]
  end
  unless node['ros_buildfarm']['ssh_publisher']["rosdistro_cache_#{attr}"]
    node.default['ros_buildfarm']['ssh_publisher']["rosdistro_cache_#{attr}"] = node['ros_buildfarm']['ssh_publisher']["repo_#{attr}"]
  end
  unless node['ros_buildfarm']['ssh_publisher']["status_page_#{attr}"]
    node.default['ros_buildfarm']['ssh_publisher']["status_page_#{attr}"] = node['ros_buildfarm']['ssh_publisher']["repo_#{attr}"]
  end
end
# Sadly the publish-over-ssh plugin does not completely implement the necessary
# APIs so we have to fall back to the XML configuration file.
template '/var/lib/jenkins/jenkins.plugins.publish_over_ssh.BapSshPublisherPlugin.xml' do
  source 'jenkins/jenkins.plugins.publish_over_ssh.BapSshPublisherPlugin.xml.erb'
  owner node['jenkins']['master']['user']
  group node['jenkins']['master']['group']
  variables Hash[
    plugin_version: node['ros_buildfarm']['jenkins']['plugins']['publish-over-ssh'],
    ssh_key: data_bag_item('ros_buildfarm_publish_over_ssh_key', node.chef_environment)['private_key']
  ]
  notifies :restart, 'service[jenkins]', :immediately
end

# Jenkins authentication.
# This cookbook currently supports two modes of authentication:
# * Jenkins default:
#   This method uses the Jenkins internal user database and manages permissions directly with chef.
# * Groovy scripted:
#   This method can be used to enable more complex authentication / authorization strategies and security realms.
if node['ros_buildfarm']['jenkins']['auth_strategy'] == 'groovy'
  auth_strategy_script = data_bag_item('ros_buildfarm_jenkins_scripts', 'auth_strategy')[node.chef_environment]
  if auth_strategy_script.nil?
    Chef::Log.fatal("No auth strategy script for #{node.chef_environment} in ros_buildfarm_jenkins_scripts but auth_strategy is set to groovy.")
    raise
  end
  jenkins_script 'auth_strategy' do
    command auth_strategy_script['command']
  end
elsif node['ros_buildfarm']['jenkins']['auth_strategy'] == 'default'
  jenkins_script 'establish security realm' do
    command <<~GROOVY
      import hudson.model.*
      import jenkins.model.*
      import hudson.security.HudsonPrivateSecurityRealm
      import hudson.security.SecurityRealm

      def jenkins = Jenkins.getInstance()
      // Boolean `!` binds closer than instanceof so parenthesize the instanceof operation
      if (!(jenkins.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
        jenkins.setSecurityRealm(new HudsonPrivateSecurityRealm(false))
        jenkins.save()
      }
    GROOVY
  end

  # Restart jenkins after updating the security realm otherwise running without
  # authentication yields 403 errors when configuring.
  service 'jenkins' do
    action :restart
  end

  # Aggregate permissions to assign to each user with a groovy script.
  permissions = []
  data_bag('ros_buildfarm_jenkins_users').each do |id|
    user = data_bag_item('ros_buildfarm_jenkins_users', id)

    if user['permissions']
      user['permissions'].each do |perm|
        permissions << [perm, user['username']]
      end
    end

    # Create users unless the username is anonymous.
    # An anonymous user is used to set permissions for anonymous users but I do
    # not know what would happen if we tried to create a concrete user with the
    # username anonymous so let's just don't.
    next if user['username'] == 'anonymous'
    jenkins_user user['username'] do
      password user['password']
      public_keys user['public_keys']
      email user['email'] if user['email']
    end
  end
  jenkins_script 'matrix_authentication_permissions' do
    command <<~GROOVY
      import hudson.model.*
      import jenkins.model.*
      import hudson.security.ProjectMatrixAuthorizationStrategy

      def jenkins = Jenkins.getInstance()
      matrix_auth = new ProjectMatrixAuthorizationStrategy()

      #{permissions.map { |p, u| "matrix_auth.add(#{p}, \"#{u}\")" }.join "\n"}

      if (!matrix_auth.equals(jenkins.getAuthorizationStrategy())) {
        jenkins.setAuthorizationStrategy(matrix_auth)
        jenkins.save()
      }
    GROOVY
  end
else
  Chef::Log.warn("Jenkins auth_strategy attribute `#{node['ros_buildfarm']['jenkins']['auth_strategy']}` is unknown. No authentication will be configured.")
end

timezone node['ros_buildfarm']['jenkins']['timezone']

## Configure web proxy ##
package 'nginx'
service 'nginx' do
  action [ :enable, :start]
end
# Disable the default debian server.
file '/etc/nginx/sites-enabled/default' do
  action :delete
  manage_symlink_source false
end

if node['ros_buildfarm']['letsencrypt_enabled']
  server_name = node['ros_buildfarm']['jenkins']['server_name']
  cert_path = "/etc/ssl/certs/#{server_name}/fullchain.pem"
  key_path = "/etc/ssl/private/#{server_name}.key"

  # Bootstrap https with self-signed certificates
  package 'ssl-cert'
  directory "/etc/ssl/certs/#{server_name}"

  execute "cp /etc/ssl/certs/ssl-cert-snakeoil.pem #{cert_path}" do
    not_if "test -r #{cert_path}"
  end
  execute "cp /etc/ssl/private/ssl-cert-snakeoil.key #{key_path}" do
    not_if "test -r #{key_path}"
  end

  template '/etc/nginx/sites-enabled/jenkins' do
    source 'nginx/jenkins-webproxy.ssl.conf.erb'
    variables Hash[
      server_name: node['ros_buildfarm']['jenkins']['server_name'],
      cert_path: cert_path,
      key_path: key_path,
    ]
    notifies :restart, 'service[nginx]', :immediately
  end

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
    not_if {
      # TODO the second guard clause can be removed after >= 0.6.0
      File.directory?("/root/.acme.sh/#{server_name}") and
      File.read("/root/.acme.sh/#{server_name}/#{server_name}.conf").match(/Le_ReloadCmd='__ACME_BASE64__START_L3Jvb3QvY2VydC11cGRhdGUtaG9vay5zaA==__ACME_BASE64__END_'/)
    }
  end
else
  template '/etc/nginx/sites-enabled/jenkins' do
    source 'nginx/jenkins-webproxy.http.conf.erb'
    variables Hash[
      server_name: node['ros_buildfarm']['jenkins']['server_name']
    ]
    notifies :restart, 'service[nginx]'
  end
end

package 'python3-yaml'

package 'docker.io'

data_bag('ros_buildfarm_password_credentials').each do |item|
  password_credential = data_bag_item('ros_buildfarm_password_credentials', item)
  jenkins_password_credentials password_credential['id'] do
    id password_credential['id']
    description password_credential['description']
    username password_credential['username'] if password_credential['username']
    password password_credential['password']
  end
end

data_bag('ros_buildfarm_private_key_credentials').each do |item|
  private_key_credential = data_bag_item('ros_buildfarm_private_key_credentials', item)[node.chef_environment]
  jenkins_private_key_credentials private_key_credential['name'] do
    id private_key_credential['name']
    description private_key_credential['description']
    private_key private_key_credential['private_key']
  end
end

data_bag('ros_buildfarm_secret_text_credentials').each do |item|
  secret_text_credential = data_bag_item('ros_buildfarm_secret_text_credentials', item)[node.chef_environment]
  jenkins_secret_text_credentials secret_text_credential['name'] do
    id secret_text_credential['name']
    description secret_text_credential['description']
    secret secret_text_credential['secret_text']
  end
end

# Remove Jenkins fingerprint files
# Jenkins tracks the fingerprints of certain files so that different jobs may use different versions.
# The chef credential resources do not seem idempotent in the face of existing credentials so when chef
# is run and they are updated the fingerprint of the credential changes which causes an issue with jobs
# using them.
# I would like to find a more elegant solution, either of getting Jenkins to use the current version
# if the fingerprinted file is missing or making the credential resources idemponent. I'm not sure
# if that's possible however given that Jenkins will encrypt sensitive data with an instance-specific key.
# For now we are clobbering the fingerprints directory and hoping we get away with it. Unfortunately
# this requires yet another Jenkins restart
service 'jenkins' do
  action :stop
end
directory '/var/lib/jenkins/fingerprints' do
  action :delete
  recursive true
end
directory '/var/lib/jenkins/fingerprints' do
  owner 'jenkins'
  group 'jenkins'
end
service 'jenkins' do
  action :start
end

# Configure agent on jenkins
# TODO: (nuclearsandwich) This is going to require re-organization to suite an all-in-one setup.
node.default['ros_buildfarm']['agent']['nodename'] = 'agent_on_jenkins'
node.default['ros_buildfarm']['agent']['executors'] = 1
node.default['ros_buildfarm']['agent']['labels'] = %w(agent_on_master agent_on_jenkins)
node.default['ros_buildfarm']['jenkins_url'] = 'http://localhost:8080/'

## Postfix and OpenDKIM for SMTP
if node['ros_buildfarm']['smtp']
  include_recipe '::_jenkins_smtp'
end

include_recipe '::agent'

group 'docker' do
  members ['jenkins']
  append true
  action :manage
end
