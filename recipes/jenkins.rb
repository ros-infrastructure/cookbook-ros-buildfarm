## Jenkins Server ##

# Run an apt update if one hasn't been run in 24 hours (the default frequency).
# Without this the recipe fails on AWS instances with empty apt caches.
apt_update

package 'openjdk-8-jdk-headless'
include_recipe 'jenkins::master'

# Set up authentication
chef_user = search('ros_buildfarm_jenkins_users', 'chef_user:true').first
node.run_state[:jenkins_username] = chef_user['username']
node.run_state[:jenkins_password] = chef_user['password']
node.default['jenkins']['executor']['protocol'] = 'http'

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
    plugin_version: node['ros_buildfarm']['jenkins']['publish-over-ssh'],
    ssh_key: data_bag_item('ros_buildfarm_publish_over_ssh_key', node.chef_environment)['ssh_key']
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
  auth_strategy_script = data_bag_item('ros_buildfarm_jenkins_scripts', 'auth_strategy')
  if auth_strategy_script.nil?
    Chef::Log.fatal('No auth strategy script in ros_buildfarm_jenkins_scripts but auth_strategy is set to groovy.')
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
  server_name = node['ros_buildfarm']['server_name']
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
      server_name: node['ros_buildfarm']['server_name'],
      cert_path: cert_path,
      key_path: key_path,
    ]
    notifies :restart, 'service[nginx]', :immediately
  end

  # Install acme.sh for certificate signing and renewal.  git is required for acme.sh's setup
  package 'git'
  execute 'git clone https://github.com/acmesh-official/acme.sh' do
    cwd '/root'
    not_if 'test -d /root/acme.sh'
  end
  execute 'acmesh-install' do
    cwd '/root/acme.sh'
    cmd = './acme.sh --install --home /root/.acme.sh'
    cmd << " --accountemail #{node['ros_buildfarm']['letsencrypt_email']}" if node['ros_buildfarm']['letsencrypt_email']
    command cmd
    not_if 'test -x /root/.acme.sh/acme.sh'
  end

  # Create Let's Encrypt signed cert if it has not already been done.
  execute 'acme-issue-cert' do
    command %W(
      /root/.acme.sh/acme.sh --issue
      --domain #{server_name}
      --fullchain-file #{cert_path}
      --key-file #{key_path}
    )
  end
else
  template '/etc/nginx/sites-enabled/jenkins' do
    source 'nginx/jenkins-webproxy.http.conf.erb'
    variables Hash[
      server_name: node['ros_buildfarm']['server_name']
    ]
    notifies :restart, 'service[nginx]'
  end
end

package 'python3-yaml'

package 'docker.io'

data_bag('ros_buildfarm_private_key_credentials').each do |item|
  private_key_credential = data_bag_item('ros_buildfarm_private_key_credentials', item)
  jenkins_private_key_credentials private_key_credential['id'] do
    id private_key_credential['id']
    description private_key_credential['description']
    private_key private_key_credential['private_key']
  end
end

data_bag('ros_buildfarm_password_credentials').each do |item|
  password_credential = data_bag_item('ros_buildfarm_password_credentials', item)
  jenkins_password_credentials password_credential['id'] do
    id password_credential['id']
    description password_credential['description']
    password password_credential['password']
  end
end

# Configure agent on jenkins
# TODO: (nuclearsandwich) This is going to require re-organization to suite an all-in-one setup.
node.default['ros_buildfarm']['agent']['nodename'] = 'agent_on_jenkins'
node.default['ros_buildfarm']['agent']['executors'] = 1
node.default['ros_buildfarm']['agent']['labels'] = %w(agent_on_master agent_on_jenkins)

include_recipe '::agent'
