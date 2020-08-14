##JENKINS SERVER##
  
include_recipe 'jenkins::master'

#rosplugins need to download plugin TODO
#copy loop into recipe use node['ros_buildfarm']['jenkins_plugins']
node['ros_buildfarm']['jenkins']['plugins'].each do |plugin, ver|
  jenkins_plugin plugin do
    version ver
    install_deps false
    notifies :restart, 'service[jenkins]', :delayed
  end
end

node.default['ros_buildfarm']['agent']['nodename'] = "agent_on_master"
node.default['ros_buildfarm']['agent']['executors'] = 1
node.default['ros_buildfarm']['agent']['labels'] = ["agent_on_master"]

include_recipe '::agent' 

directory '/var/lib/jenkins/casc_configs'
template '/var/lib/jenkins/casc_configs/jenkins.yaml' do
  group node['jenkins']['master']['group']
  source 'jenkins.yaml.erb'
end

#authentication TODO
jenkins_user 'admin' do
  email 'todo@something.com'
  public_keys [node['ros_buildfarm']['jenkins']['admin']['key']]
end

timezone node['ros_buildfarm']['jenkins']['timezone']

package 'nginx'
#Steven TODO 
template '/etc/nginx/sites-enabled/jenkins.conf' do
end
service 'nginx' do
  action [ :enable, :start]
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
