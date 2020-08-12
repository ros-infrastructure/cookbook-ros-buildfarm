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

include_recipe '::agent' #ros buildfarm agent recipe, TODO: change attributes in this recipe before including 

#jenkins config as code do i need to do more like make the contents of the yaml file
#copy configuration file from config file to template 
template '/var/jenkins/casc_configs/jenkins.yaml' do
  group node['jenkins']['master']['group']
  source 'jenkins.yaml.erb' #idk what this file should be named
end

#idk if this is required but the plugin says this environement variable needs to be defined
execute 'CASC_JENKINS_CONFIG' do
  environment ({'CASC_JENKINS_CONFIG' => '/var/jenkins/casc_configs/jenkins.yaml'})
end

#user directories, attribute or variable here? not needed for now

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

package 'docker'

#data bag query and loop through it
node['ros_buildfarm']['jenkins']['credentials'].each do |name, agent, des, key|
  jenkins_private_key_credentials agent do
    id name
    description des
    private_key key
  end
end

#data bag query loop
node['ros_buildfarm']['jenkins']['credentials'].each do |name, agent, des, pass|
  jenkins_password_credentials agent do
    id name
    description des
    password pass
  end
end
