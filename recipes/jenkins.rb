##JENKINS SERVER##

# Run an apt update if one hasn't been run in 24 hours (the default frequency).
# Without this the recipe fails on AWS instances with empty apt caches.
apt_update

package 'openjdk-8-jdk-headless'
include_recipe 'jenkins::master'

# Install plugins required to run ros_buildfarm.
node['ros_buildfarm']['jenkins']['plugins'].each do |plugin, ver|
  jenkins_plugin plugin do
    version ver
    install_deps false
    notifies :restart, 'service[jenkins]', :delayed
  end
end

template '/var/lib/jenkins/jenkins.yaml' do
  group node['jenkins']['master']['group']
  source 'jenkins.yaml.erb'
  notifies :restart, "service[jenkins]", :immediately
end


# Jenkins authentication.
# This cookbook currently supports two modes of authentication:
# * Jenkins default:
#   This method uses the Jenkins internal user database and manages permissions directly with chef.
# * Groovy scripted:
#   This method can be used to enable more complex authentication / authorization strategies and security realms.
if node['ros_buildfarm']['jenkins']['auth_strategy'] == 'groovy'
  auth_strategy_script = data_bag_item("ros_buildfarm_jenkins_scripts", "auth_strategy")
  if auth_strategy_script.nil?
    Chef::Log.fatal("No auth strategy script in ros_buildfarm_jenkins_scripts but auth_strategy is set to groovy.")
    raise
  end
  jenkins_script 'auth_strategy' do
    command auth_strategy_script['command']
  end
elsif node['ros_buildfarm']['jenkins']['auth_strategy'] == 'default'
  jenkins_script 'establish security realm' do
    script = <<-GROOVY.gsub %r(^ {6}), ''
      import hudson.model.*
      import jenkins.model.*
      import hudson.security.HudsonPrivateSecurityRealm
      import hudson.security.SecurityRealm

      def jenkins = Jenkins.getInstance()
      if (! jenkins.getSecurityRealm() instanceof HudsonPrivateSecurityRealm) {
        jenkins.setSecurityRealm(new HudsonPrivateSecurityRealm(false))
        jenkins.save()
      }
    GROOVY
    Chef::Log.info("Running groovy script:\n#{script}")
    command script
  end

  # Aggregate permissions to assign to each user with a groovy script.
  permissions = []
  data_bag('ros_buildfarm_jenkins_users').each do |id|
    user = data_bag_item('ros_buildfarm_jenkins_users', id)
    # Generate randomized password for chef jenkins user
    # which should only use ssh authentication.
    #if user['chef_user']
      #user['password'] = SecureRandom.uuid
    #entchend

    if user['permissions']
      user['permissions'].each do |perm|
        permissions << [perm, user['username']]
      end
    end

    jenkins_user user['username'] do
      password user['password']
      public_keys user['public_keys']
      email user['email'] if user['email']
    end

  end
  jenkins_script 'matrix_authentication_permissions' do
    command <<-GROOVY.gsub %r(^ {6}), ''
      import hudson.model.*
      import jenkins.model.*
      import hudson.security.ProjectMatrixAuthorizationStrategy

      def jenkins = Jenkins.getInstance()
      matrix_auth = new ProjectMatrixAuthorizationStrategy()

      #{permissions.map{|p, u| "matrix_auth.add(#{p}, \"#{u}\")"}.join "\n"}
      matrix_auth.add(Jenkins.READ, "anonymous")
      matrix_auth.add(Job.DISCOVER, "anonymous")
      matrix_auth.add(Job.READ, "anonymous")
      matrix_auth.add(View.READ, "anonymous")

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

package 'nginx'
#Steven TODO 
#template '/etc/nginx/sites-enabled/jenkins.conf' do
#end
#service 'nginx' do
#  action [ :enable, :start]
#end

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
node.default['ros_buildfarm']['agent']['nodename'] = "agent_on_jenkins"
node.default['ros_buildfarm']['agent']['executors'] = 1
node.default['ros_buildfarm']['agent']['labels'] = ["agent_on_master", "agent_on_jenkins"]

include_recipe '::agent'
